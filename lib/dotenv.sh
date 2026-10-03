# Lecture d'un fichier dotenv, seule du dépôt (story 2.4, constat D7 de la rétrospective de l'epic 0).
#
# À charger par « . scripts/lib/dotenv.sh ».
#
#   dotenv_read <fichier> <préfixe>   affiche, une par ligne, « CLE=valeur » pour les lignes dont la
#                                     clé commence par <préfixe> ; rend 1 si le fichier est illisible
#   dotenv_value <ligne>              la valeur d'une ligne « CLE=valeur », guillemets retirés
#
# Un fichier dotenv n'est jamais lu par « source » ni « set -a » : il contient des secrets qui n'ont
# rien à faire dans l'environnement d'un processus enfant (AD-9, AD-24). Une valeur entre guillemets
# doubles ou simples perd ses guillemets ; une valeur sans guillemets perd un commentaire « # … »
# précédé d'une espace, puis ses espaces de fin. Aucune fonction n'affiche de valeur d'elle-même.

# $1 = ligne « CLE=valeur »
dotenv_value() {
  local value=${1#*=}
  case $value in
    \"*) value=${value#\"}; value=${value%%\"*} ;;
    \'*) value=${value#\'}; value=${value%%\'*} ;;
    *) value=${value%%[[:space:]]#*}; value=${value%"${value##*[![:space:]]}"} ;;
  esac
  printf '%s' "$value"
}

# $1 = fichier, $2 = préfixe des clés retenues (par exemple HUGO_LEGAL_ ou GITEA_)
dotenv_read() {
  local file=$1 prefix=$2 line key
  [[ -r $file ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ $line == "$prefix"* ]] || continue
    [[ $line == *=* ]] || continue
    key=${line%%=*}
    # une clé n'est faite que de majuscules, de chiffres et de tirets bas : le reste n'est pas du dotenv
    [[ $key =~ ^[A-Z][A-Z0-9_]*$ ]] || continue
    printf '%s=%s\n' "$key" "$(dotenv_value "$line")"
  done < "$file"
}
