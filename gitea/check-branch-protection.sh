#!/usr/bin/env bash
# Contrôle, en lecture seule, de la protection des branches du projet : relit par l'API la règle de
# forge.base et de forge.release-branch, les styles de fusion du dépôt et ses clés de déploiement, et les
# compare à la règle commune et aux valeurs de la section [protection] de workflow.config (schéma 7).
#
#   check-branch-protection.sh
#
# Sur un écart, il nomme chaque écart (champ de l'API, valeur lue, valeur attendue), puis donne la liste
# exacte des réglages à poser dans l'interface de la forge, écran par écran et champ par champ, avec les
# libellés de l'interface. ⛔ Il n'écrit jamais rien sur la forge : les réglages se posent à la main, puis
# ce contrôle relit, et c'est sa relecture qui fait foi — jamais la réponse de la forge à une écriture.
#
# Codes de sortie (convention à trois codes, procedures/shell-scripts.md) :
#   0 conforme : chaque champ relu est égal à la valeur attendue ;
#   1 écart constaté : réglage différent, règle absente, règle en trop sur une autre branche, style de
#     fusion ouvert ou fermé à tort, clé de déploiement qui peut pousser (refuse) ;
#   2 vérification impossible : usage, outil absent, workflow.config refusé ou d'avant le schéma 7, dépôt
#     distant inattendu, jeton absent ou refusé (HTTP 401), lecture refusée (403 : lire les règles exige le
#     droit d'administration du dépôt), réponse illisible ou incomplète, liste de clés sans fin (die).
#     ⛔ Jamais 0 sur une lecture qui a échoué.
# Limites, écrites aussi dans sa sortie : les protections d'étiquettes ne sont pas relues, et une autre
# branche durable sans règle n'est pas détectée.
# Procédure : procedures/gitea-branches.md
set -euo pipefail
set +x # même lancé avec bash -x, la trace s'arrête ici, avant la lecture du jeton

script_name=check-branch-protection
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/config.sh
. "$script_dir/../lib/config.sh"
# shellcheck source=gitea.sh
. "$script_dir/gitea.sh"
# shellcheck source=../lib/protection.sh
. "$script_dir/../lib/protection.sh"

# la liste des clés se lit page par page, jusqu'à une page vide ; au-delà, refus plutôt qu'une liste tronquée
readonly max_key_pages=20

require_tools
(($# == 0)) || die "usage : check-branch-protection.sh (sans argument)"

root=""
config_project_root root || die "à lancer dans le dépôt."
cd "$root"
config_load "$root/workflow.config" || exit 2
config_schema_level=""
config_get config_schema_level workflow.schema
((config_schema_level >= 7)) \
  || die "workflow.config au schéma $config_schema_level : le contrôle exige le schéma 7, section [protection] (procedures/workflow-config.md, « Du schéma 6 au schéma 7 »)."
config_get forge_env_file forge.env-file
readonly forge_env_file
gitea_configure
check_origin

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

protection_expected "$tmp/attendu.json" || die "valeurs attendues illisibles dans workflow.config."

load_gitea_env "$root/$forge_env_file"
check_token_owner "$tmp/user.json"

read_api() { # $1 chemin de l'API, $2 fichier de réponse, $3 ce qui est lu (pour le message)
  local code
  code=$(gitea_api GET "$1" "$2")
  [[ $code == 200 ]] && return 0
  case $code in
    403|404) die "lecture refusée : $3 (HTTP $code) ; lire les règles et les clés exige le droit d'administration du dépôt, pour le compte du jeton. $(forge_message "$2")" ;;
    *) die "lecture impossible : $3 (HTTP $code). $(forge_message "$2")" ;;
  esac
}

repo_path=/repos/$gitea_canonical_repo
read_api "$repo_path" "$tmp/depot.json" "réglages du dépôt"
read_api "$repo_path/branch_protections" "$tmp/regles.json" "règles de protection des branches"

# les clés de déploiement, toutes les pages : la fin ne se déduit jamais d'une page plus courte
page=1
printf '[]' > "$tmp/cles.json"
while :; do
  ((page <= max_key_pages)) \
    || die "clés de déploiement : plus de $max_key_pages pages sans page vide ; aucune conclusion sur une liste tronquée."
  read_api "$repo_path/keys?limit=50&page=$page" "$tmp/page.json" "clés de déploiement (page $page)"
  count=$(jq 'if type == "array" then length else error("liste attendue") end' "$tmp/page.json" 2>/dev/null) \
    || die "réponse illisible : clés de déploiement (page $page), une liste JSON attendue."
  ((count > 0)) || break
  { jq -s '.[0] + .[1]' "$tmp/cles.json" "$tmp/page.json" > "$tmp/cles.next" && mv "$tmp/cles.next" "$tmp/cles.json"; } \
    || die "clés de déploiement : assemblage des pages impossible."
  page=$((page + 1))
done

rc=0
shapes=$(protection_check_shapes "$tmp/attendu.json" "$tmp/depot.json" "$tmp/regles.json" "$tmp/cles.json") || rc=$?
((rc == 0)) || die "$shapes"

printf '%s: %s\n' "$script_name" "$gitea_canonical_repo — règle commune de protection des branches (procedures/gitea-branches.md)"
rc=0
protection_compare "$tmp/attendu.json" "$tmp/depot.json" "$tmp/regles.json" "$tmp/cles.json" || rc=$?
case $rc in
  0) exit 0 ;;
  1) refuse "écart constaté : poser les réglages ci-dessus dans l'interface, puis relancer ce contrôle." ;;
  *) die "comparaison impossible." ;;
esac
