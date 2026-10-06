#!/usr/bin/env bash
# Tests hors ligne des scripts du poste de développement et de la CI.
#
#   tests/run.sh                  tous les cas de tests/test-*.sh du dépôt commun, arrêt au premier échec
#   tests/run.sh <fichier>...     les cas de ces fichiers de test seulement (ceux d'un projet, par exemple)
#
# Chaque cas tourne dans son propre processus bash : set -e y reste actif, alors qu'il serait suspendu
# dans un if ou derrière ||. Aucun réseau, ni .env ni chemin privé. Trois gardes le vérifient :
#   - un cas ne lance jamais le vrai docker, curl, psql ni ssh : de faux binaires, placés en tête du PATH
#     de chaque cas, notent l'appel et sortent en 2, et le cas échoue en nommant l'outil, même s'il a
#     avalé cet échec. Un cas qui a besoin de l'un d'eux place son propre faux devant ; un outil employé
#     hors réseau se demande nommément : file_only_curl ou real_command (tests/lib.sh) ;
#   - git status, les diffs de l'arbre et de l'index, HEAD et les références locales sont relevés avant et après
#     la suite : tout écart fait échouer ;
#   - les sorties que le projet protège (tests.protected-outputs de son workflow.config), ignorées par
#     git, sont relevées de même ; « none » le dit et ne relève rien.
# Dépendances : bash, git, jq, grep et outils de base.
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
readonly protected_outputs

for tool in bash git jq grep awk sed mktemp find sort cmp diff paste; do
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

# État git du dépôt : un cas qui écrit dans l'arbre de travail (fichier créé, supprimé ou modifié),
# dans l'index ou dans l'historique local, sans passer par $work. Les empreintes des diffs complètent
# git status : un fichier déjà modifié avant la suite garde la même ligne « M » s'il est modifié de
# nouveau, et un fichier indexé la même ligne « A » si l'index change encore. HEAD, les branches, les
# étiquettes et la remise (stash) voient un commit, un reset ou un stash qui laisseraient l'arbre
# propre. Les branches distantes n'y sont pas : un fetch lancé à côté de la suite ne la fait pas
# échouer. Les fichiers ignorés n'y figurent pas : ce sont les sorties protégées, relevées à part.
git_state() { # $1 = fichier où écrire l'état
  {
    git status --porcelain=v1 --untracked-files=all --ignore-submodules=none \
      && git diff --no-ext-diff --binary | git hash-object --stdin \
      && git diff --cached --no-ext-diff --binary | git hash-object --stdin \
      && { git symbolic-ref -q HEAD || echo "HEAD détachée"; } \
      && { git rev-parse -q --verify HEAD || echo "HEAD sans commit"; } \
      && git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags refs/stash
  } > "$1"
}
git_state "$logs/git-avant" || { echo "tests: état git du dépôt illisible." >&2; exit 2; }

# Faux docker, curl, psql et ssh, en tête du PATH de chaque cas. Chaque faux porte le chemin absolu
# du journal des appels : un cas qui vide son environnement en gardant son PATH (env -i PATH="$PATH")
# ou relie le faux ailleurs par un lien (ln -s "$(command -v curl)") reste vu. Un cas qui remplace son
# PATH sort de la garde, env -i sans PATH compris (le PATH par défaut du système s'applique alors).
forbidden_dir="$logs/interdits"
forbidden_log="$logs/appels-interdits"
# Le chemin du journal, cité pour sh entre apostrophes, les siennes échappées : le faux est en sh.
quote="'"
quoted_log="'${forbidden_log//$quote/$quote\\$quote$quote}'"
mkdir "$forbidden_dir" || { echo "tests: dossier des faux outils impossible à créer." >&2; exit 2; }
# marque lue par real_command (tests/lib.sh), qui saute ce dossier pour trouver le vrai binaire
: > "$forbidden_dir/.faux-du-lanceur" || { echo "tests: marque des faux outils impossible à écrire." >&2; exit 2; }
for tool in docker curl psql ssh; do
  # shellcheck disable=SC2016 # faux binaire écrit sur le disque : son « $* » s'y développe à l'exécution
  if ! printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> %s\necho "tests: appel réel à %s interdit dans un cas de test : placer un faux devant lui dans le PATH du cas." >&2\nexit 2\n' \
    "$tool" "$quoted_log" "$tool" > "$forbidden_dir/$tool"; then
    echo "tests: faux $tool impossible à écrire." >&2
    exit 2
  fi
  chmod 755 "$forbidden_dir/$tool" || { echo "tests: faux $tool impossible à rendre exécutable." >&2; exit 2; }
done

total=0
ignores=()
for file in "${files[@]}"; do
  [[ -f $file ]] || { echo "tests: fichier de test absent : $file" >&2; exit 2; }
  label=${file#"$root"/}
  cases=$(bash "$file" --list) || { echo "tests: liste des cas illisible : $label" >&2; exit 2; }
  [[ -n $cases ]] || { echo "tests: aucun cas dans $label" >&2; exit 2; }
  while IFS= read -r name; do
    rc=0
    : > "$forbidden_log"
    PATH="$forbidden_dir:$PATH" TESTS_FORBIDDEN_DIR="$forbidden_dir" \
      bash "$file" "$name" > "$logs/sortie" 2>&1 || rc=$?
    # Un appel réel fait échouer le cas quel que soit son code : un « || true » l'aurait avalé.
    if [[ -s $forbidden_log ]]; then
      printf 'tests: ÉCHEC %s : %s (code %s) — appel réel à %s : aucun faux devant lui dans le PATH du cas.\n' \
        "$label" "$name" "$rc" "$(awk '{ print $1 }' "$forbidden_log" | sort -u | paste -sd, -)" >&2
      sed 's/^/  /' "$forbidden_log" "$logs/sortie" >&2
      exit 1
    fi
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
git_state "$logs/git-apres" || { echo "tests: état git du dépôt illisible." >&2; exit 2; }
if ! cmp -s "$logs/git-avant" "$logs/git-apres"; then
  echo "tests: ÉCHEC la suite a modifié l'état git du dépôt : un cas écrit hors de \$work. Écart (avant, après) :" >&2
  # diff rend 1 quand les fichiers diffèrent, ce qui est le cas ici : l'écart est écrit, puis affiché
  diff "$logs/git-avant" "$logs/git-apres" > "$logs/git-ecart" || [[ $? == 1 ]] || echo "  (écart illisible)" >&2
  sed 's/^/  /' "$logs/git-ecart" >&2
  exit 1
fi
if ((${#ignores[@]})); then
  printf 'tests: %s cas réussis, %s ignorés :\n' "$total" "${#ignores[@]}"
  printf '  %s\n' "${ignores[@]}"
else
  printf 'tests: %s cas réussis.\n' "$total"
fi
