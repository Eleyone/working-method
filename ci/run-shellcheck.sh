#!/usr/bin/env bash
# Analyse par shellcheck de tous les scripts suivis du dépôt commun, à TOUS les niveaux (style compris), avec le
# binaire épinglé que fournit ci/ensure-shellcheck.sh. Lancé par ci/checks-job.sh ; isolé dans son
# propre script pour que chacune de ses gardes ait un cas de test (tests/test-ci-checks.sh).
#
#   ci/run-shellcheck.sh
#
# Les exclusions sont écrites ligne par ligne, chacune avec sa raison ; aucune n'est globale
# (.shellcheckrc ne règle que la lecture des fichiers chargés). Procédure : procedures/shell-scripts.md
# Codes de sortie : 0 aucun constat ; 1 au moins un constat ; 2 shellcheck impossible à fournir, liste
# des scripts illisible ou vide — une analyse sans fichier n'est jamais une réussite.
set -euo pipefail

script_name=run-shellcheck
die() { printf '%s: %s\n' "$script_name" "$*" >&2; exit 2; }
(($# == 0)) || die "aucun argument attendu."
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

sc_dir=$(sh ci/ensure-shellcheck.sh) || die "shellcheck épinglé impossible à fournir."
# La liste est lue d'abord, avec son code : « shellcheck $(git ls-files …) » lancerait shellcheck sans
# aucun fichier sur un échec de git, et l'étape passerait. Séparée par des octets nuls : un nom de
# fichier qui contient un saut de ligne reste un seul nom. Elle passe par un fichier, supprimé à la
# sortie quoi qu'il arrive : « done < <(git …) » masquerait l'échec de git (procedures/shell-scripts.md).
# Lecture par « read -d '' », bash 4.3 : « mapfile -d » demanderait bash 4.4.
liste=$(mktemp) || die "fichier temporaire impossible."
trap 'rm -f "$liste"' EXIT
git ls-files -z -- '*.sh' bin/check-bash bin/install bin/install.bash > "$liste" \
  || die "liste des scripts illisible (git ls-files)."
script_list=()
while IFS= read -r -d '' script; do
  script_list+=("$script")
done < "$liste"
((${#script_list[@]})) || die "aucun script suivi : rien à analyser n'est pas une réussite."

version=$("$sc_dir/shellcheck" --version | sed -n 's/^version: *//p') \
  || die "shellcheck ne répond pas à --version : binaire inutilisable."
printf '%s: shellcheck %s, tous niveaux, sur %s script(s).\n' "$script_name" "$version" "${#script_list[@]}"
# sans option de sévérité : tous les niveaux comptent. « -- » : un fichier suivi dont le nom commence par
# « - » (« -eSC2086.sh ») reste un fichier, jamais une option qui désactiverait une règle.
"$sc_dir/shellcheck" -- "${script_list[@]}"
