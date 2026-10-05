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
#   5. shellcheck sur tous les scripts, à TOUS les niveaux (style compris), avec le binaire épinglé que
#      fournit ci/ensure-shellcheck.sh (décision d'Arnaud du 04/10/2026). Les exclusions sont écrites
#      ligne par ligne, chacune avec sa raison ; aucune n'est globale (.shellcheckrc). Un shellcheck
#      impossible à fournir fait échouer l'étape : jamais « non lancé » compté comme réussi.
#   6. ci/bmad-reinstall.sh, le test de réinstallation de BMAD (story 1, décision 9) : il rejoue
#      l'installeur BMAD — node 20.12 ou plus, npx et le réseau (npm, GitHub) sont donc requis ici, sur
#      le runner comme sur le poste ; une réinstallation impossible fait échouer l'étape (code 2).
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
step "shellcheck (tous niveaux)" bash ci/run-shellcheck.sh
step "réinstallation de BMAD (réseau)" bash ci/bmad-reinstall.sh

printf '\n'
if ((${#failed[@]})); then
  printf '%s: %s étape(s) en échec : %s\n' "$script_name" "${#failed[@]}" "${failed[*]}" >&2
  exit 1
fi
printf '%s: toutes les étapes lancées passent.\n' "$script_name"
