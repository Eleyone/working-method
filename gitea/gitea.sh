# Bibliothèque commune des scripts du poste de développement qui appellent la forge Gitea.
#
# À charger par « . scripts/lib/gitea.sh » depuis un script qui a déjà coupé la trace du shell
# (set +x) et défini script_name. Aucune fonction n'affiche une valeur de .env.
#
#   die <message>                  message sur la sortie d'erreur, sortie en échec
#   require_tools                  jq et curl présents
#   load_gitea_env <fichier .env>  lit GITEA_URL, GITEA_USER, GITEA_TOKEN, juste avant le premier appel à l'API
#   check_origin                   le dépôt distant origin est le dépôt canonique
#   gitea_api <méthode> <chemin> <réponse> [<corps JSON>]   affiche le code HTTP (000 sans réponse)
#   forge_message <réponse>        message d'erreur de la forge, sans adresse
#   check_token_owner <réponse>    le jeton appartient au compte GITEA_USER
#
# Procédures : docs/procedures/gitea-token.md, docs/procedures/create-pull-request.md,
# docs/procedures/llm-review.md

readonly gitea_canonical_repo="Eleyone/eleyone.fr"
readonly gitea_token_procedure="docs/procedures/gitea-token.md"

die() { printf '%s: %b\n' "${script_name:-script}" "$*" >&2; exit 1; }

require_tools() {
  command -v jq >/dev/null 2>&1 || die "jq est introuvable. Installation : sudo apt install jq"
  command -v curl >/dev/null 2>&1 || die "curl est introuvable."
}

# .env est lu ligne par ligne, jamais avec source. Une valeur entre guillemets doubles ou simples
# perd ses guillemets ; une valeur sans guillemets perd un commentaire « # … » précédé d'une espace.
# Les variables ne sont pas exportées : aucun sous-processus n'en hérite.
load_gitea_env() {
  local env_file=$1 line key value
  [[ -f $env_file ]] || die ".env absent à la racine du dépôt. Procédure : $gitea_token_procedure"
  gitea_url="" gitea_user="" gitea_token=""
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    case $line in
      GITEA_URL=*|GITEA_USER=*|GITEA_TOKEN=*) ;;
      *) continue ;;
    esac
    key=${line%%=*}
    value=${line#*=}
    case $value in
      \"*) value=${value#\"}; value=${value%%\"*} ;;
      \'*) value=${value#\'}; value=${value%%\'*} ;;
      *) value=${value%%[[:space:]]#*}; value=${value%"${value##*[![:space:]]}"} ;;
    esac
    case $key in
      GITEA_URL) gitea_url=$value ;;
      GITEA_USER) gitea_user=$value ;;
      GITEA_TOKEN) gitea_token=$value ;;
    esac
  done < "$env_file"
  [[ -n $gitea_url ]] || die "GITEA_URL absente de .env. Procédure : $gitea_token_procedure"
  [[ -n $gitea_user ]] || die "GITEA_USER absente de .env. Procédure : $gitea_token_procedure"
  [[ -n $gitea_token ]] || die "GITEA_TOKEN absente de .env. Procédure : $gitea_token_procedure"
}

# Nom canonique du dépôt : vérifié avant tout appel d'écriture. Le message n'affiche jamais l'adresse.
check_origin() {
  local remote_url repo_path
  remote_url=$(git remote get-url origin 2>/dev/null) || die "aucun dépôt distant origin."
  repo_path=$(printf '%s\n' "$remote_url" \
    | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]*/##; s#^[^/:]*@[^:]*:##; s#\.git$##; s#/+$##')
  [[ $repo_path == "$gitea_canonical_repo" ]] \
    || die "le dépôt distant origin n'est pas $gitea_canonical_repo : rien n'est fait."
}

gitea_api() {
  local args=(-s -K - -o "$3" -w '%{http_code}' -X "$1")
  [[ -z ${4:-} ]] || args+=(-H 'Content-Type: application/json' --data "@$4")
  # le jeton passe par l'entrée standard : il n'apparaît pas dans la liste des processus
  printf 'header = "Authorization: token %s"\n' "$gitea_token" \
    | curl "${args[@]}" "${gitea_url%/}/api/v1$2" || true
}

forge_message() {
  jq -r '.message // empty' "$1" 2>/dev/null | head -c 300 \
    | sed -E 's#[a-zA-Z][a-zA-Z0-9+.-]*://[^[:space:]]+#<adresse>#g' || true
}

check_token_owner() {
  local code
  code=$(gitea_api GET /user "$1")
  [[ $code == 200 ]] \
    || die "la forge refuse le jeton ou ne répond pas (HTTP $code). Procédure : $gitea_token_procedure"
  [[ $(jq -r '.login // empty' "$1") == "$gitea_user" ]] \
    || die "le jeton n'appartient pas au compte GITEA_USER. Procédure : $gitea_token_procedure"
}
