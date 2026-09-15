#!/usr/bin/env bash
# Tests hors ligne des scripts du poste de développement et de la CI.
#
#   scripts/tests/run.sh                  tous les cas de scripts/tests/test-*.sh, arrêt au premier échec
#   scripts/tests/run.sh <fichier>...     les cas de ces fichiers de test seulement
#
# Chaque cas tourne dans son propre processus bash : set -e y reste actif, alors qu'il serait suspendu
# dans un if ou derrière ||. Aucun réseau, ni .env ni docs/private/. Dépendances : bash, git, jq,
# grep GNU et outils de base, présents sur le poste et dans CHECK_IMAGE.
# Code de sortie : 0 tous les cas réussis ; 1 un cas échoue ; 2 tests impossibles à lancer.
# Procédure : docs/procedures/shell-scripts.md
set -euo pipefail

tests_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$tests_dir/../.." && pwd)
cd "$root"

for tool in bash git jq grep awk sed mktemp; do
  command -v "$tool" >/dev/null 2>&1 || { echo "tests: $tool introuvable." >&2; exit 2; }
done

if (($#)); then files=("$@"); else files=("$tests_dir"/test-*.sh); fi
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT

total=0
for file in "${files[@]}"; do
  [[ -f $file ]] || { echo "tests: fichier de test absent : $file" >&2; exit 2; }
  label=${file#"$root"/}
  cases=$(bash "$file" --list) || { echo "tests: liste des cas illisible : $label" >&2; exit 2; }
  [[ -n $cases ]] || { echo "tests: aucun cas dans $label" >&2; exit 2; }
  while IFS= read -r name; do
    rc=0
    bash "$file" "$name" > "$logs/sortie" 2>&1 || rc=$?
    if ((rc != 0)); then
      printf 'tests: ÉCHEC %s : %s (code %s)\n' "$label" "$name" "$rc" >&2
      sed 's/^/  /' "$logs/sortie" >&2
      exit 1
    fi
    total=$((total + 1))
  done <<< "$cases"
done
printf 'tests: %s cas réussis.\n' "$total"
