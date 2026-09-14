#!/usr/bin/env bash
# Ouvre une pull request sur la forge Gitea, depuis la branche courante, par l'API REST.
#
#   create-pull-request.sh --title "<titre>" [--body-file <fichier>]
#
# Base déduite du préfixe de branche : feat/, fix/, chore/, docs/ → dev. Aucune PR vers main.
# Corps lu dans un fichier (par défaut .pr-body.md à la racine, ignoré par git), passé par
# jq --rawfile et envoyé par curl --data @. Le jeton ne s'affiche jamais ; la sortie donne
# le numéro de la PR, jamais son adresse, qui contient le nom de la forge.
# Procédure : docs/procedures/create-pull-request.md
set -euo pipefail
set +x # même lancé avec bash -x, la trace s'arrête ici, avant la lecture du jeton

script_name=create-pull-request
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/gitea.sh
. "$script_dir/lib/gitea.sh"

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

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "à lancer dans le dépôt."
cd "$root"
body_file=${body_file:-$root/.pr-body.md}
[[ -n $title ]] || die "titre manquant : --title \"<titre>\"."
[[ -s $body_file ]] || die "corps absent ou vide : ${body_file#"$root"/}."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

check_origin

branch=$(git symbolic-ref --quiet --short HEAD) || die "HEAD détachée : se placer sur la branche de la PR."
case $branch in
  feat/?*|fix/?*|chore/?*|docs/?*) base=dev ;;
  hotfix/*) die "branche $branch : une PR de hotfix vers main s'ouvre avec le skill hotfix." ;;
  dev|main) die "branche $branch : ce skill n'ouvre aucune PR vers main ; la publication de dev passe par le skill release." ;;
  *) die "préfixe de branche refusé : $branch. Préfixes admis : feat/, fix/, chore/, docs/." ;;
esac

pending=$(git status --porcelain 2>/dev/null) || die "lecture de l'état du dépôt impossible : rien n'est ouvert."
[[ -z $pending ]] || die "modifications non commitées : tout commiter avant d'ouvrir la PR."

patterns_file=${PRIVATE_PATTERNS_FILE:-$root/docs/private/forbidden-patterns.txt}
[[ -f $patterns_file ]] \
  || die "fichier de motifs absent : l'ouverture d'une PR exige l'audit (docs/procedures/check-private.md)."

git fetch --quiet origin "$base" 2>/dev/null || die "lecture de la branche $base sur la forge impossible."
base_sha=$(git rev-parse FETCH_HEAD 2>/dev/null) || die "lecture de la branche $base récupérée impossible."
remote_head=$(git ls-remote --heads origin "refs/heads/$branch" 2>/dev/null) \
  || die "lecture du dépôt distant impossible."
[[ ${remote_head%%$'\t'*} == "$(git rev-parse HEAD)" ]] \
  || die "la branche $branch n'est pas poussée sur ce commit : la pousser avant d'ouvrir la PR."

PRIVATE_PATTERNS_FILE=$patterns_file "$root/scripts/check-private.sh" history "$base_sha..HEAD" \
  || die "le garde-fou public/privé refuse la branche : rien n'est ouvert."

printf '%s\n' "$title" > "$tmp/title"
grep -vE '^[[:space:]]*(#|$)' "$patterns_file" > "$tmp/patterns" || true
if [[ -s $tmp/patterns ]]; then
  rc=0
  grep -qiF -f "$tmp/patterns" "$tmp/title" "$body_file" || rc=$?
  ((rc != 0)) || die "le titre ou le corps contient un motif privé (contenu masqué) : rien n'est ouvert."
  ((rc == 1)) || die "vérification du titre et du corps impossible : rien n'est ouvert."
fi

# .env n'est lu qu'ici, juste avant le premier appel à l'API
load_gitea_env "$root/.env"
check_token_owner "$tmp/user.json"

page=1
while :; do
  code=$(gitea_api GET "/repos/$gitea_canonical_repo/pulls?state=open&limit=50&page=$page" "$tmp/open.json")
  [[ $code == 200 ]] || die "lecture des PR ouvertes impossible (HTTP $code) : $(forge_message "$tmp/open.json")"
  existing=$(jq -r --arg b "$branch" '[.[] | select(.head.ref == $b) | .number] | first // empty' "$tmp/open.json")
  [[ -z $existing ]] || die "une PR est déjà ouverte pour $branch : n° $existing."
  (($(jq 'length' "$tmp/open.json") == 50)) || break
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
  die "PR n° $number ouverte, mais son corps publié diffère du fichier : le corriger sur la forge."
fi

printf 'PR n° %s ouverte : %s → %s\n' "$number" "$branch" "$base"
