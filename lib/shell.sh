# Enveloppes communes des outils que tous les scripts lancent en boucle. Écrites **une seule fois**
# pour tout le dépôt : contrôles, tests, scripts opérationnels et bibliothèques de décision.
#
# À charger par « . scripts/lib/shell.sh » depuis un script qui a défini script_name.
#
#   shell_grep_status <variable> <arguments de grep…>
#       ne quitte jamais : rend 0 trouvé, 1 rien trouvé, le code de grep au-delà. Réservé aux
#       fonctions de bibliothèque, qui répondent par leur code de retour comme une commande.
#   shell_grep_into <variable> <arguments de grep…>
#       remplit la variable et rend **toujours 0** ; une erreur de lecture arrête le script.
#       L'absence se lit dans la variable, vide : rendre 1 tuerait un appel nu sous « set -e »,
#       et ramènerait le « || true » que ces enveloppes existent pour supprimer. Qui veut
#       distinguer les deux emploie shell_grep_status.
#   shell_grep <arguments de grep…>
#       la même distinction, mais le résultat va sur la sortie standard : réservé aux pipelines,
#       où une variable n'aurait pas de sens.
#
# Pourquoi une variable plutôt qu'une sortie : appelée dans « $(…) », une fonction ne peut pas
# arrêter son appelant — son « exit » ne quitte que le sous-shell, et l'erreur se perd (piège connu,
# docs/procedures/shell-scripts.md). La forme qui remplit une variable est la seule qui y survive.
#
# Pourquoi une seule écriture : la même garde avait fini par exister en quatre exemplaires, dont le
# dernier est né le jour où l'avant-dernier a été écrit pour cette raison exacte (rétrospective de
# l'epic 3, constat A2). Dupliquer une garde correcte est un défaut au même titre que l'oublier.
#
# shell_error_exit fixe le code d'arrêt : 2 par défaut, la convention « anomalie » du projet ; les
# tests le mettent à 1, code d'un cas en échec.

shell_die() { printf '%s: %s\n' "${script_name:-script}" "$*" >&2; exit "${shell_error_exit:-2}"; }

shell_grep_status() { # $1 = nom de la variable à remplir, $2… = arguments de grep
  local -n shell_grep_destination=$1
  shift
  local shell_grep_code=0
  # le code est rendu tel quel : un message qui cite « code 127 » dit que grep est introuvable,
  # là où un code rabattu sur 2 ferait croire à un fichier illisible
  shell_grep_destination=$(grep "$@") || shell_grep_code=$?
  return "$shell_grep_code"
}

shell_grep_into() { # $1 = nom de la variable à remplir, $2… = arguments de grep
  local shell_grep_code=0
  shell_grep_status "$@" || shell_grep_code=$?
  ((shell_grep_code <= 1)) \
    || shell_die "recherche impossible (grep, code $shell_grep_code) : ${*: -1}"
  return 0
}

shell_grep() { # arguments de grep ; le résultat va sur la sortie standard
  local shell_grep_code=0
  grep "$@" || shell_grep_code=$?
  ((shell_grep_code <= 1)) || shell_die "recherche impossible (grep, code $shell_grep_code) : ${*: -1}"
  return "$shell_grep_code"
}
