#!/usr/bin/env bash
# Job de contrôles du dépôt commun : ce que sa CI lance, et ce que le poste lance de la même façon.
#
#   ci/checks-job.sh
#
# Étapes, toutes lancées même après un échec, chacune nommée dans le résumé :
#   1. jq, fourni par ci/ensure-jq.sh s'il manque (binaire épinglé : le runner n'en a pas) ;
#   2. tests/run.sh, toute la suite hors ligne ;
#   3. ci/check-secrets.sh, aucun secret dans l'arbre ni dans l'historique (AC 11) ;
#   4. ci/check-names.sh, aucun nom de projet consommateur dans l'arbre (AC 3) ;
#   5. shellcheck sur les scripts, s'il est installé — sinon le job le dit, et ne le compte pas réussi.
# Le prérequis bash est vérifié AVANT ce script, par bin/check-bash en POSIX sh (étape du workflow).
#
# Codes de sortie : 0 tout passe ; 1 au moins une étape en échec ; 2 jq impossible à fournir.
# Procédures : procedures/shell-scripts.md, procedures/secrets.md
set -euo pipefail

script_name=checks-job
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

if ! command -v jq >/dev/null 2>&1; then
  jq_dir=$(sh ci/ensure-jq.sh) || { printf '%s: jq impossible à fournir : aucun test ne tourne sans lui.\n' "$script_name" >&2; exit 2; }
  PATH="$jq_dir:$PATH"
fi

failed=()
step() { # $1 libellé, $2… commande
  local label=$1 rc=0
  shift
  printf '\n%s: --- %s\n' "$script_name" "$label"
  "$@" || rc=$?
  ((rc == 0)) || failed+=("$label (code $rc)")
}

step "tests" bash tests/run.sh
step "aucun secret" bash ci/check-secrets.sh
step "aucun nom de projet" bash ci/check-names.sh
if command -v shellcheck >/dev/null 2>&1; then
  scripts=$(git ls-files -- '*.sh' bin/check-bash bin/install bin/install.bash) || { failed+=("shellcheck (liste des scripts illisible)"); scripts=""; }
  if [[ -n $scripts ]]; then
    mapfile -t script_list <<< "$scripts"
    step "shellcheck (erreurs)" shellcheck -S error -x "${script_list[@]}"
  fi
else
  printf '\n%s: --- shellcheck absent de cette machine : non lancé, et non compté comme réussi.\n' "$script_name"
fi

printf '\n'
if ((${#failed[@]})); then
  printf '%s: %s étape(s) en échec : %s\n' "$script_name" "${#failed[@]}" "${failed[*]}" >&2
  exit 1
fi
printf '%s: toutes les étapes lancées passent.\n' "$script_name"
