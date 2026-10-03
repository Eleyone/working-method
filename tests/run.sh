#!/usr/bin/env bash
# Tests hors ligne des scripts du poste de développement et de la CI.
#
#   scripts/tests/run.sh                  tous les cas de scripts/tests/test-*.sh, arrêt au premier échec
#   scripts/tests/run.sh <fichier>...     les cas de ces fichiers de test seulement
#
# Chaque cas tourne dans son propre processus bash : set -e y reste actif, alors qu'il serait suspendu
# dans un if ou derrière ||. Aucun réseau, ni .env ni docs/private/. La suite ne touche jamais public/
# ni build/ du dépôt : leur état est relevé avant et après, et un écart fait échouer. Dépendances : bash, git, jq,
# grep GNU et outils de base, présents sur le poste et dans CHECK_IMAGE.
# Code de sortie : 0 tous les cas réussis ; 1 un cas échoue ; 2 tests impossibles à lancer.
# Un cas qui rend 3 est sans objet dans cet environnement (skip_case) : il est compté à part et sa
# raison s'affiche dans le résumé.
# Procédure : docs/procedures/shell-scripts.md
set -euo pipefail

tests_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$tests_dir/../.." && pwd)
cd "$root"

for tool in bash git jq grep awk sed mktemp find sort cmp; do
  command -v "$tool" >/dev/null 2>&1 || { echo "tests: $tool introuvable." >&2; exit 2; }
done

if (($#)); then files=("$@"); else files=("$tests_dir"/test-*.sh); fi
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT

# État des sorties de build du dépôt : un cas qui lance un script destructeur sans racine jetable les
# effacerait en silence (rétrospective de l'epic 2, F1 : build.sh vide sa destination avant Hugo).
outputs_state() { # $1 = fichier où écrire l'état
  local dir
  : > "$1" || return 1
  for dir in public build; do
    if [[ -e $dir ]]; then
      find "$dir" -printf '%p\t%y\t%s\t%T@\n' >> "$1" || return 1
    else
      printf '%s\tabsent\n' "$dir" >> "$1" || return 1
    fi
  done
  LC_ALL=C sort -o "$1" "$1"
}
outputs_state "$logs/avant" || { echo "tests: état de public/ et build/ illisible." >&2; exit 2; }

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
outputs_state "$logs/apres" || { echo "tests: état de public/ et build/ illisible." >&2; exit 2; }
if ! cmp -s "$logs/avant" "$logs/apres"; then
  echo "tests: ÉCHEC la suite a modifié public/ ou build/ du dépôt : un cas lance un script sans racine jetable." >&2
  exit 1
fi
if ((${#ignores[@]})); then
  printf 'tests: %s cas réussis, %s ignorés :\n' "$total" "${#ignores[@]}"
  printf '  %s\n' "${ignores[@]}"
else
  printf 'tests: %s cas réussis.\n' "$total"
fi
