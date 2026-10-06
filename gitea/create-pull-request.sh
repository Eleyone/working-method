#!/usr/bin/env bash
# Ouvre une pull request sur la forge Gitea, depuis la branche courante, par l'API REST.
#
#   create-pull-request.sh --title "<titre>" [--body-file <fichier>]
#
# Base déduite du préfixe de branche : un préfixe de forge.branch-prefixes (workflow.config) mène à
# forge.base. Aucune PR depuis la base ni vers la branche de publication (forge.release-branch).
# Corps lu dans un fichier (par défaut .pr-body.md à la racine, ignoré par git), passé par
# jq --rawfile et envoyé par curl --data @. Le jeton ne s'affiche jamais ; la sortie donne
# le numéro de la PR, jamais son adresse, qui contient le nom de la forge.
#
# Codes de sortie (convention à trois codes, procedures/shell-scripts.md) : 0 PR ouverte ; 1 écart
# constaté, la branche ou l'arbre ne permet pas de l'ouvrir — préfixe ou base refusés, modifications non
# commitées, branche non poussée sur ce commit, refus du garde-fou, motif privé dans le titre ou le
# corps, PR déjà ouverte, corps publié différent du fichier (refuse) ; 2 l'ouverture n'a pas pu être
# tentée — usage, prérequis, configuration, lecture de git ou de la forge, création refusée (die).
# Procédure : procedures/create-pull-request.md
set -euo pipefail
set +x # même lancé avec bash -x, la trace s'arrête ici, avant la lecture du jeton

script_name=create-pull-request
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/config.sh
. "$script_dir/../lib/config.sh"
# shellcheck source=gitea.sh
. "$script_dir/gitea.sh"

require_tools

title="" body_file=""
while (($#)); do
  case $1 in
    --title) (($# >= 2)) || die "--title attend une valeur."; title=$2; shift 2 ;;
    --body-file) (($# >= 2)) || die "--body-file attend une valeur."; body_file=$2; shift 2 ;;
    *) die "usage : create-pull-request.sh --title \"<titre>\" [--body-file <fichier>]" ;;
  esac
done
[[ -z $body_file || $body_file == /* ]] || body_file="$PWD/$body_file"

root=""
config_project_root root || die "à lancer dans le dépôt."
cd "$root"
config_load "$root/workflow.config" || exit 2
config_get forge_base forge.base
config_get release_branch forge.release-branch
config_get branch_prefixes forge.branch-prefixes
config_get guard_command guard.command
config_get guard_patterns guard.patterns-file
config_get forge_env_file forge.env-file
readonly forge_base release_branch branch_prefixes guard_command guard_patterns forge_env_file
gitea_configure
body_file=${body_file:-$root/.pr-body.md}
[[ -n $title ]] || die "titre manquant : --title \"<titre>\"."
[[ -s $body_file ]] || die "corps absent ou vide : ${body_file#"$root"/}."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

check_origin

branch=$(git symbolic-ref --quiet --short HEAD) || die "HEAD détachée : se placer sur la branche de la PR."
base=$(branch_base "$branch" "$forge_base" "$release_branch" "$branch_prefixes") || refuse "$base"

pending=$(git status --porcelain 2>/dev/null) || die "lecture de l'état du dépôt impossible : rien n'est ouvert."
[[ -z $pending ]] || refuse "modifications non commitées : tout commiter avant d'ouvrir la PR."

patterns_file=""
if [[ $guard_command == none ]]; then
  printf '%s: garde-fou désactivé (guard.command = none) : ni audit des commits, ni contrôle des motifs privés.\n' "$script_name" >&2
else
  [[ -x $root/$guard_command ]] || die "$guard_command absent ou non exécutable (guard.command)."
  patterns_file=${PRIVATE_PATTERNS_FILE:-$root/$guard_patterns}
  require_patterns_file "$patterns_file" "l'ouverture d'une PR exige l'audit"
fi

git fetch --quiet origin "$base" 2>/dev/null || die "lecture de la branche $base sur la forge impossible."
base_sha=$(git rev-parse FETCH_HEAD 2>/dev/null) || die "lecture de la branche $base récupérée impossible."
remote_head=$(git ls-remote --heads origin "refs/heads/$branch" 2>/dev/null) \
  || die "lecture du dépôt distant impossible."
[[ ${remote_head%%$'\t'*} == "$(git rev-parse HEAD)" ]] \
  || refuse "la branche $branch n'est pas poussée sur ce commit : la pousser avant d'ouvrir la PR."

if [[ -n $patterns_file ]]; then
  PRIVATE_PATTERNS_FILE=$patterns_file "$root/$guard_command" history "$base_sha..HEAD" \
    || refuse "le garde-fou public/privé refuse la branche : rien n'est ouvert."
fi

printf '%s\n' "$title" > "$tmp/title"
: > "$tmp/patterns"
if [[ -n $patterns_file ]]; then
  rc=0
  grep -vE '^[[:space:]]*(#|$)' "$patterns_file" > "$tmp/patterns" 2>/dev/null || rc=$?
  ((rc <= 1)) || die "lecture du fichier de motifs impossible : rien n'est ouvert."
fi
if [[ -s $tmp/patterns ]]; then
  rc=0
  grep -qiF -f "$tmp/patterns" "$tmp/title" "$body_file" || rc=$?
  ((rc != 0)) || refuse "le titre ou le corps contient un motif privé (contenu masqué) : rien n'est ouvert."
  ((rc == 1)) || die "vérification du titre et du corps impossible : rien n'est ouvert."
fi

# .env n'est lu qu'ici, juste avant le premier appel à l'API
load_gitea_env "$root/$forge_env_file"
check_token_owner "$tmp/user.json"

page=1
while :; do
  code=$(gitea_api GET "/repos/$gitea_canonical_repo/pulls?state=open&limit=50&page=$page" "$tmp/open.json")
  [[ $code == 200 ]] || die "lecture des PR ouvertes impossible (HTTP $code) : $(forge_message "$tmp/open.json")"
  existing=$(jq -r --arg b "$branch" '[.[] | select(.head.ref == $b) | .number] | first // empty' "$tmp/open.json" 2>/dev/null) \
    || die "liste des PR ouvertes illisible."
  [[ -z $existing ]] || refuse "une PR est déjà ouverte pour $branch : n° $existing."
  count=$(jq 'length' "$tmp/open.json" 2>/dev/null) || die "liste des PR ouvertes illisible."
  [[ $count =~ ^[0-9]+$ ]] || die "liste des PR ouvertes illisible."
  ((count == 50)) || break
  page=$((page + 1))
done

jq -n --arg head "$branch" --arg base "$base" --arg title "$title" --rawfile body "$body_file" \
  '{head: $head, base: $base, title: $title, body: $body}' > "$tmp/payload.json" 2>/dev/null \
  || die "corps illisible : texte UTF-8 attendu."
code=$(gitea_api POST "/repos/$gitea_canonical_repo/pulls" "$tmp/created.json" "$tmp/payload.json")
[[ $code == 201 ]] || die "la forge refuse la création (HTTP $code) : $(forge_message "$tmp/created.json")"
number=$(jq -r '.number' "$tmp/created.json")

# le corps publié est relu et comparé octet par octet au fichier
code=$(gitea_api GET "/repos/$gitea_canonical_repo/pulls/$number" "$tmp/pr.json")
jq -j '.body' "$tmp/pr.json" > "$tmp/published" 2>/dev/null || true
if [[ $code != 200 ]] || ! cmp -s "$tmp/published" "$body_file"; then
  refuse "PR n° $number ouverte, mais son corps publié diffère du fichier : le corriger sur la forge."
fi

printf 'PR n° %s ouverte : %s → %s\n' "$number" "$branch" "$base"
