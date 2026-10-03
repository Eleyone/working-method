#!/usr/bin/env bash
# Mécanisme des contrôles bloquants d'un projet : découverte dynamique des scripts de contrôle, cumul
# des écarts, codes de sortie. Extrait du point d'entrée des contrôles du projet source ; ce qui lui
# était propre (ses builds, son chargeur de valeurs, son niveau --release) reste dans le projet, qui
# appelle ce script après ses propres étapes.
#
#   checks/run-checks.sh                    lance chaque contrôle par « bash <contrôle> »
#   checks/run-checks.sh -- <commande>...   lance chaque contrôle par « <commande>... bash <contrôle> »,
#                                           par exemple sous le chargeur de valeurs du projet
#
# Les contrôles sont les scripts « *.sh » du dossier checks.dir de workflow.config, triés, lib.sh exclu :
# un contrôle ajouté ne modifie pas ce script. Tous tournent, même après un échec, et tous les écarts
# s'affichent avant le résumé. CHECK_LEVEL, s'il est posé par le projet, est transmis tel quel et
# nommé dans le résumé. checks.dir = none : aucun contrôle, et le script le dit.
# Codes de sortie : 0 conforme ; 1 écart constaté ; 2 anomalie (contrôle en code 2 ou plus, option
# inconnue, dossier introuvable, workflow.config refusé).
# Procédure : procedures/check.md
set -euo pipefail

script_name=run-checks
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/config.sh
. "$script_dir/../lib/config.sh"

prefix=()
while (($#)); do
  case $1 in
    --) shift; prefix=("$@"); break ;;
    *) printf '%s: option inconnue « %s ».\nusage : %s [-- <commande>...]\n' "$script_name" "$1" "$0" >&2; exit 2 ;;
  esac
done

root=""
config_project_root root || { printf '%s: à lancer dans le dépôt du projet.\n' "$script_name" >&2; exit 2; }
cd "$root"
config_load "$root/workflow.config" || exit 2
config_get checks_dir checks.dir
if [[ $checks_dir == none ]]; then
  printf '%s: aucun dossier de contrôles (checks.dir = none) : aucun contrôle lancé.\n' "$script_name"
  exit 0
fi
[[ -d $root/$checks_dir ]] \
  || { printf '%s: dossier de contrôles introuvable : %s (checks.dir).\n' "$script_name" "$checks_dir" >&2; exit 2; }
level_label=""
[[ -z ${CHECK_LEVEL:-} ]] || level_label=", niveau $CHECK_LEVEL"

shopt -s nullglob
scripts=()
for candidate in "$root/$checks_dir"/*.sh; do
  [[ $(basename "$candidate") != lib.sh ]] || continue
  scripts+=("$candidate")
done
shopt -u nullglob

failed=()
anomaly=0
# Le préfixe sert au chargeur de valeurs d'un projet : dans le projet source, sans lui, aucun contrôle
# ne voyait les valeurs qu'il devait chercher dans la sortie — un garde-fou qui ne gardait rien
# (constat de la revue de spec de la story 9.1 du projet source).
for candidate in "${scripts[@]}"; do
  name=$(basename "$candidate" .sh)
  rc=0
  "${prefix[@]}" bash "$candidate" || rc=$?
  case $rc in
    0) ;;
    1) failed+=("$name") ;;
    *) failed+=("$name (code $rc)"); anomaly=1 ;;
  esac
done

if ((${#scripts[@]} == 0)); then
  printf '%s: aucun script de contrôle dans %s/%s.\n' "$script_name" "$checks_dir" "$level_label"
  exit 0
fi

if ((${#failed[@]})); then
  printf '%s: %s contrôle(s) en échec sur %s : %s\n' \
    "$script_name" "${#failed[@]}" "${#scripts[@]}" "${failed[*]}" >&2
  ((anomaly == 0)) || exit 2
  exit 1
fi

printf '%s: %s contrôle(s) passés%s.\n' "$script_name" "${#scripts[@]}" "$level_label"
