# shellcheck shell=bash
# Bibliothèque commune des scripts du poste de développement qui appellent la forge Gitea.
#
# À charger par « . gitea/gitea.sh » depuis un script qui a déjà coupé la trace du shell (set +x),
# défini script_name, et chargé workflow.config (lib/config.sh). Aucune fonction n'affiche une valeur
# de .env.
#
#   die <message>                  message sur la sortie d'erreur, sortie en échec
#   require_tools                  jq et curl présents
#   gitea_configure                lit forge.repo dans workflow.config : le dépôt canonique
#   load_gitea_env <fichier .env>  lit GITEA_URL, GITEA_USER, GITEA_TOKEN, juste avant le premier appel à l'API
#   check_origin                   le dépôt distant origin est le dépôt canonique
#   gitea_api <méthode> <chemin> <réponse> [<corps JSON>]   affiche le code HTTP (000 sans réponse)
#   forge_message <réponse>        message d'erreur de la forge, sans adresse
#   check_token_owner <réponse>    le jeton appartient au compte GITEA_USER
#   require_patterns_file <fichier> <conséquence>   fichier de motifs présent, avec au moins un motif
#   branch_base <branche> <base> <publication|none> <préfixes>
#                                  base d'une PR ouverte depuis cette branche : 0 et la base, 1 et la raison
#
# Procédures (dépôt commun) : procedures/gitea-token.md, procedures/create-pull-request.md,
# procedures/llm-review.md, procedures/verify-and-merge-pr.md

# shellcheck source=../lib/dotenv.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/dotenv.sh"

# Le nom canonique du dépôt n'est plus écrit ici : il vient de forge.repo (gitea_configure).
gitea_canonical_repo=""
readonly gitea_token_procedure="procedures/gitea-token.md du dépôt commun"

die() { printf '%s: %b\n' "${script_name:-script}" "$*" >&2; exit 1; }

require_tools() {
  command -v jq >/dev/null 2>&1 || die "jq est introuvable. Installation : sudo apt install jq"
  command -v curl >/dev/null 2>&1 || die "curl est introuvable."
}

# Le dépôt canonique est lu dans workflow.config, déjà chargé et validé par l'appelant.
gitea_configure() {
  config_get gitea_canonical_repo forge.repo || die "forge.repo illisible : workflow.config non chargé."
  [[ -n $gitea_canonical_repo ]] || die "forge.repo vide."
}

# .env est lu par le lecteur commun de lib/dotenv.sh, jamais avec source (story 2.4 du projet source).
# Les variables ne sont pas exportées : aucun sous-processus n'en hérite.
load_gitea_env() {
  local env_file=$1 line key value lines
  [[ -f $env_file ]] || die "${env_file##*/} absent (forge.env-file). Procédure : $gitea_token_procedure"
  gitea_url="" gitea_user="" gitea_token=""
  # la liste est lue dans une variable d'abord : « done < <(fonction) » masquerait l'échec du lecteur
  # et la boucle tournerait sur une liste vide (piège connu, procedures/shell-scripts.md)
  lines=$(dotenv_read "$env_file" GITEA_) || die ".env illisible. Procédure : $gitea_token_procedure"
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    key=${line%%=*}
    value=${line#*=}
    case $key in
      GITEA_URL) gitea_url=$value ;;
      GITEA_USER) gitea_user=$value ;;
      GITEA_TOKEN) gitea_token=$value ;;
    esac
  done <<< "$lines"
  [[ -n $gitea_url ]] || die "GITEA_URL absente de .env. Procédure : $gitea_token_procedure"
  [[ -n $gitea_user ]] || die "GITEA_USER absente de .env. Procédure : $gitea_token_procedure"
  [[ -n $gitea_token ]] || die "GITEA_TOKEN absente de .env. Procédure : $gitea_token_procedure"
}

# Nom canonique du dépôt : vérifié avant tout appel d'écriture. Le message n'affiche jamais l'adresse.
check_origin() {
  local remote_url repo_path
  [[ -n $gitea_canonical_repo ]] || die "dépôt canonique inconnu : gitea_configure n'a pas été appelé."
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

# Un fichier de motifs sans aucun motif (seulement des commentaires ou des lignes blanches) ferait
# passer le garde-fou sur les chemins seuls : il est refusé comme un fichier absent.
require_patterns_file() { # $1 fichier de motifs, $2 conséquence affichée
  local rc=0
  [[ -f $1 ]] || die "fichier de motifs absent : $2 (guard.patterns-file, procédure du garde-fou du projet)."
  grep -qvE '^[[:space:]]*(#|$)' "$1" 2>/dev/null || rc=$?
  ((rc != 1)) || die "fichier de motifs sans aucun motif : $2 (guard.patterns-file, procédure du garde-fou du projet)."
  ((rc == 0)) || die "fichier de motifs illisible : $2."
}

# Base d'une PR selon le préfixe de sa branche. Aucune PR n'est ouverte depuis la base ni depuis la
# branche de publication, ni vers celle-ci : la publication a son propre chemin, hors de cet outil.
branch_base() { # $1 branche, $2 forge.base, $3 forge.release-branch ou none, $4 forge.branch-prefixes
  local branch=$1 base=$2 release=$3 prefixes=$4 prefix admitted=""
  if [[ $branch == "$base" || ( $release != none && $branch == "$release" ) ]]; then
    printf "branche %s : aucune PR ne s'ouvre depuis la base ni depuis la branche de publication.\n" "$branch"
    return 1
  fi
  for prefix in $prefixes; do
    admitted+="${admitted:+, }$prefix/"
    if [[ $branch == "$prefix"/?* ]]; then
      printf '%s\n' "$base"
      return 0
    fi
  done
  printf 'préfixe de branche refusé : %s. Préfixes admis : %s.\n' "$branch" "$admitted"
  return 1
}
