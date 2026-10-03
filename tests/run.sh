#!/usr/bin/env bash
# Tests hors ligne des scripts du poste de développement et de la CI.
#
#   tests/run.sh                  tous les cas de tests/test-*.sh du dépôt commun, arrêt au premier échec
#   tests/run.sh <fichier>...     les cas de ces fichiers de test seulement (ceux d'un projet, par exemple)
#
# Chaque cas tourne dans son propre processus bash : set -e y reste actif, alors qu'il serait suspendu
# dans un if ou derrière ||. Aucun réseau, ni .env ni chemin privé. La suite ne touche jamais les
# sorties que le projet protège (tests.protected-outputs de son workflow.config) : leur état est relevé
# avant et après, et un écart fait échouer ; « none » le dit et ne relève rien. Dépendances : bash, git,
# jq, grep et outils de base.
# Code de sortie : 0 tous les cas réussis ; 1 un cas échoue ; 2 tests impossibles à lancer.
# Un cas qui rend 3 est sans objet dans cet environnement (skip_case) : il est compté à part et sa
# raison s'affiche dans le résumé.
# Procédure : procedures/shell-scripts.md
set -euo pipefail

tests_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/config.sh
. "$tests_dir/../lib/config.sh"
root=""
config_project_root root || { echo "tests: à lancer dans un dépôt git." >&2; exit 2; }
cd "$root"
config_load "$root/workflow.config" || exit 2
config_get protected_outputs tests.protected-outputs

for tool in bash git jq grep awk sed mktemp find sort cmp; do
  command -v "$tool" >/dev/null 2>&1 || { echo "tests: $tool introuvable." >&2; exit 2; }
done

if (($#)); then files=("$@"); else files=("$tests_dir"/test-*.sh); fi
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT

# État des sorties de build du projet : un cas qui lance un script destructeur sans racine jetable les
# effacerait en silence (rétrospective de l'epic 2 du projet source, F1 : build.sh vidait sa
# destination avant le générateur).
outputs_state() { # $1 = fichier où écrire l'état
  local dir
  : > "$1" || return 1
  [[ $protected_outputs != none ]] || return 0
  for dir in $protected_outputs; do
    if [[ -e $dir ]]; then
      # stat plutôt que « find -printf », que le find de BusyBox ignore (runner de la forge, piège
      # connu de procedures/shell-scripts.md) : chemin, type, taille, date de modification
      find "$dir" -exec stat -c '%n|%F|%s|%Y' {} + >> "$1" || return 1
    else
      printf '%s\tabsent\n' "$dir" >> "$1" || return 1
    fi
  done
  LC_ALL=C sort -o "$1" "$1"
}
if [[ $protected_outputs == none ]]; then
  echo "tests: aucune sortie protégée (tests.protected-outputs = none) : rien n'est relevé avant ni après." >&2
fi
outputs_state "$logs/avant" || { echo "tests: état de $protected_outputs illisible." >&2; exit 2; }

total=0
ignores=()
for file in "${files[@]}"; do
  [[ -f $file ]] || { echo "tests: fichier de test absent : $file" >&2; exit 2; }
  label=${file#"$root"/}
  cases=$(bash "$file" --list) || { echo "tests: liste des cas illisible : $label" >&2; exit 2; }
  [[ -n $cases ]] || { echo "tests: aucun cas dans $label" >&2; exit 2; }
  while IFS= read -r name; do
    rc=0
    bash "$file" "$name" > "$logs/sortie" 2>&1 || rc=$?
    # code 3 : cas sans objet ici (skip_case). Il est compté à part et sa raison s'affiche, pour
    # qu'une couverture moindre ne passe jamais inaperçue.
    if ((rc == 3)); then
      raison=$(sed -n 's/^IGNORÉ : //p' "$logs/sortie" | head -n 1)
      ignores+=("$label : $name — ${raison:-sans raison donnée}")
      continue
    fi
    if ((rc != 0)); then
      printf 'tests: ÉCHEC %s : %s (code %s)\n' "$label" "$name" "$rc" >&2
      sed 's/^/  /' "$logs/sortie" >&2
      exit 1
    fi
    total=$((total + 1))
  done <<< "$cases"
done
outputs_state "$logs/apres" || { echo "tests: état de $protected_outputs illisible." >&2; exit 2; }
if ! cmp -s "$logs/avant" "$logs/apres"; then
  echo "tests: ÉCHEC la suite a modifié une sortie protégée du projet ($protected_outputs) : un cas lance un script sans racine jetable." >&2
  exit 1
fi
if ((${#ignores[@]})); then
  printf 'tests: %s cas réussis, %s ignorés :\n' "$total" "${#ignores[@]}"
  printf '  %s\n' "${ignores[@]}"
else
  printf 'tests: %s cas réussis.\n' "$total"
fi
