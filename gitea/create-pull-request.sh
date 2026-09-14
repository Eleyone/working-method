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

readonly canonical_repo="Eleyone/eleyone.fr"
readonly token_procedure="docs/procedures/gitea-token.md"

die() { printf 'create-pull-request: %b\n' "$*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq est introuvable. Installation : sudo apt install jq"
command -v curl >/dev/null 2>&1 || die "curl est introuvable."

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

# .env est lu ligne par ligne, jamais avec source, et aucune valeur n'est affichée
[[ -f .env ]] || die ".env absent à la racine du dépôt. Procédure : $token_procedure"
gitea_url="" gitea_user="" gitea_token=""
while IFS= read -r line || [[ -n $line ]]; do
  value=${line#*=}; value=${value%$'\r'}; value=${value%\"}; value=${value#\"}
  case $line in
    GITEA_URL=*) gitea_url=$value ;;
    GITEA_USER=*) gitea_user=$value ;;
    GITEA_TOKEN=*) gitea_token=$value ;;
  esac
done < .env
[[ -n $gitea_url ]] || die "GITEA_URL absente de .env. Procédure : $token_procedure"
[[ -n $gitea_user ]] || die "GITEA_USER absente de .env. Procédure : $token_procedure"
[[ -n $gitea_token ]] || die "GITEA_TOKEN absente de .env. Procédure : $token_procedure"

api() { # méthode, chemin, fichier de réponse[, fichier de corps] ; affiche le code HTTP
  local args=(-s -K - -o "$3" -w '%{http_code}' -X "$1")
  [[ -z ${4:-} ]] || args+=(-H 'Content-Type: application/json' --data "@$4")
  # le jeton passe par l'entrée standard : il n'apparaît pas dans la liste des processus
  printf 'header = "Authorization: token %s"\n' "$gitea_token" \
    | curl "${args[@]}" "${gitea_url%/}/api/v1$2" || true
}

forge_message() { # message d'erreur de la forge, sans adresse
  jq -r '.message // empty' "$1" 2>/dev/null | head -c 300 \
    | sed -E 's#[a-zA-Z][a-zA-Z0-9+.-]*://[^[:space:]]+#<adresse>#g' || true
}

# nom canonique du dépôt : vérifié avant tout appel d'écriture
remote_url=$(git remote get-url origin 2>/dev/null) || die "aucun dépôt distant origin."
repo_path=$(printf '%s\n' "$remote_url" \
  | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]*/##; s#^[^/:]*@[^:]*:##; s#\.git$##; s#/+$##')
[[ $repo_path == "$canonical_repo" ]] || die "le dépôt distant origin n'est pas $canonical_repo : rien n'est ouvert."

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

code=$(api GET /user "$tmp/user.json")
[[ $code == 200 ]] || die "la forge refuse le jeton ou ne répond pas (HTTP $code). Procédure : $token_procedure"
[[ $(jq -r '.login // empty' "$tmp/user.json") == "$gitea_user" ]] \
  || die "le jeton n'appartient pas au compte GITEA_USER. Procédure : $token_procedure"

page=1
while :; do
  code=$(api GET "/repos/$canonical_repo/pulls?state=open&limit=50&page=$page" "$tmp/open.json")
  [[ $code == 200 ]] || die "lecture des PR ouvertes impossible (HTTP $code) : $(forge_message "$tmp/open.json")"
  existing=$(jq -r --arg b "$branch" '[.[] | select(.head.ref == $b) | .number] | first // empty' "$tmp/open.json")
  [[ -z $existing ]] || die "une PR est déjà ouverte pour $branch : n° $existing."
  (($(jq 'length' "$tmp/open.json") == 50)) || break
  page=$((page + 1))
done

jq -n --arg head "$branch" --arg base "$base" --arg title "$title" --rawfile body "$body_file" \
  '{head: $head, base: $base, title: $title, body: $body}' > "$tmp/payload.json" 2>/dev/null \
  || die "corps illisible : texte UTF-8 attendu."
code=$(api POST "/repos/$canonical_repo/pulls" "$tmp/created.json" "$tmp/payload.json")
[[ $code == 201 ]] || die "la forge refuse la création (HTTP $code) : $(forge_message "$tmp/created.json")"
number=$(jq -r '.number' "$tmp/created.json")

# le corps publié est relu et comparé octet par octet au fichier
code=$(api GET "/repos/$canonical_repo/pulls/$number" "$tmp/pr.json")
jq -j '.body' "$tmp/pr.json" > "$tmp/published" 2>/dev/null || true
if [[ $code != 200 ]] || ! cmp -s "$tmp/published" "$body_file"; then
  die "PR n° $number ouverte, mais son corps publié diffère du fichier : le corriger sur la forge."
fi

printf 'PR n° %s ouverte : %s → %s\n' "$number" "$branch" "$base"
