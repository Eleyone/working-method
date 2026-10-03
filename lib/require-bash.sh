# Prérequis bash de tout l'outillage, vérifié AVANT la première ligne de bash : écrit en POSIX sh,
# pour qu'un poste ou un runner sans bash, ou avec un bash trop ancien, reçoive un message et le
# code 2 — jamais une erreur de syntaxe à mi-parcours (AC 9 de la story outillage-14).
#
# À charger par « . lib/require-bash.sh » depuis un script POSIX sh, puis appeler require_bash.
#
#   require_bash    0 si « bash » du PATH est en version 4.3 ou plus ; sinon message sur la sortie
#                   d'erreur et code 2. Il ne quitte pas : c'est l'appelant qui sort.
#
# Pourquoi 4.3 : « local -n » (références de variables), employé par lib/shell.sh et lib/config.sh,
# est apparu en bash 4.3 ; « declare -A » (sprint-consistency.sh) date de 4.0.

require_bash_min_major=4
require_bash_min_minor=3

require_bash() {
  _rb_path=$(command -v bash 2>/dev/null) || _rb_path=""
  if [ -z "$_rb_path" ]; then
    printf 'prérequis : bash est introuvable dans le PATH ; bash %s.%s ou plus est requis par l’outillage commun.\n' \
      "$require_bash_min_major" "$require_bash_min_minor" >&2
    return 2
  fi
  # shellcheck disable=SC2016 # le développement se fait dans le bash interrogé, pas ici
  _rb_version=$("$_rb_path" -c 'printf "%s %s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null) || _rb_version=""
  # shellcheck disable=SC2086 # découpage voulu : « majeure mineure »
  set -- $_rb_version
  case "${1:-}:${2:-}" in
    *[!0-9:]*|:*|*:) printf 'prérequis : version de bash illisible (%s) ; bash %s.%s ou plus est requis.\n' \
        "$_rb_path" "$require_bash_min_major" "$require_bash_min_minor" >&2
      return 2 ;;
  esac
  if [ "$1" -gt "$require_bash_min_major" ] \
    || { [ "$1" -eq "$require_bash_min_major" ] && [ "$2" -ge "$require_bash_min_minor" ]; }; then
    return 0
  fi
  printf 'prérequis : bash %s.%s trouvé (%s) ; bash %s.%s ou plus est requis par l’outillage commun.\n' \
    "$1" "$2" "$_rb_path" "$require_bash_min_major" "$require_bash_min_minor" >&2
  return 2
}
