# Outils communs des fichiers de test, chargés en tête de chaque scripts/tests/test-*.sh.
#
# Un fichier de test définit des fonctions case_<nom> et se termine par « run_case "$@" » :
#   bash scripts/tests/test-x.sh --list    liste les cas
#   bash scripts/tests/test-x.sh <nom>     lance un cas ; code non nul en cas d'échec
# Chaque cas dispose d'un dossier temporaire $work, supprimé à la fin.
set -euo pipefail

tests_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$tests_dir/../.." && pwd)
fixtures="$tests_dir/fixtures"
cd "$root"

work=$(mktemp -d)
trap 'chmod -R u+rwx "$work" 2>/dev/null || true; rm -rf "$work"' EXIT

# Lance une commande et garde son code dans rc, sa sortie dans out, son erreur dans err.
# Les fonctions testées ne comptent pas sur set -e : les appeler derrière || reflète leur usage réel.
run() {
  rc=0
  "$@" > "$work/.out" 2> "$work/.err" || rc=$?
  out=$(cat "$work/.out")
  err=$(cat "$work/.err")
}

assert_eq() { # $1 attendu, $2 obtenu, $3 libellé
  [[ $1 == "$2" ]] || { printf '%s\n  attendu : %q\n  obtenu  : %q\n' "$3" "$1" "$2" >&2; exit 1; }
}

assert_contains() { # $1 texte attendu, $2 texte où le chercher, $3 libellé
  [[ $2 == *"$1"* ]] || { printf '%s\n  attendu dans le texte : %q\n  texte : %q\n' "$3" "$1" "$2" >&2; exit 1; }
}

# Dépôt git de test dans $work/depot, sans hook ni configuration du poste.
new_repo() {
  mkdir -p "$work/depot"
  git -C "$work/depot" init -q
  git -C "$work/depot" config user.name essai
  git -C "$work/depot" config user.email essai@example.invalid
  git -C "$work/depot" config core.hooksPath /dev/null
  git -C "$work/depot" config commit.gpgsign false
}

commit_all() { # $1 message ; commit de tout le dépôt de test, affiche son SHA
  git -C "$work/depot" add -A
  git -C "$work/depot" commit -q -m "$1"
  git -C "$work/depot" rev-parse HEAD
}

# grep dans un cas de test : 0 trouvé, 1 rien trouvé, 2 et plus = erreur de lecture. « || true »
# confondrait les deux, et un fichier illisible passerait pour un fichier sans correspondance — le
# piège même que docs/procedures/shell-scripts.md décrit (constat de la revue de la PR n° 51).
#
# Le résultat est déposé dans la variable nommée en $1, plutôt que rendu sur la sortie standard :
# appelée dans « $(…) », la fonction ne pourrait pas arrêter le cas, son « exit » ne quittant que le
# sous-shell. L'entrée standard de l'appel est celle de grep, ce qui permet « tests_grep_into x -xF
# -f liste <<< "$texte" ».
tests_grep_into() { # $1 = nom de la variable à remplir, $2… = arguments de grep
  local -n tests_grep_destination=$1
  shift
  local tests_grep_code=0
  tests_grep_destination=$(grep "$@") || tests_grep_code=$?
  ((tests_grep_code <= 1)) \
    || { printf 'recherche impossible (grep, code %s) : %s\n' "$tests_grep_code" "${*: -1}" >&2; exit 1; }
  return 0
}

# Un cas sans objet dans cet environnement sort en code 3 : run.sh le compte comme ignoré et affiche
# sa raison. Il n'échoue pas — et il ne se tait pas non plus, sans quoi la couverture baisserait en
# silence là où la suite tourne autrement (constat de la première exécution en CI, story 3.13).
skip_case() { # $1 raison
  printf 'IGNORÉ : %s\n' "$1"
  exit 3
}

# root lit tout fichier, quelles que soient ses permissions : un cas qui repose sur « chmod 000 » y
# constaterait l'inverse de ce qu'il vérifie. Le contrat lui-même (code 1 de xmllint, de grep ou de
# la lecture d'une liste = anomalie) est vérifié sans permissions par test-checks-lib.sh.
skip_if_root() { # $1 ce que le cas rend illisible
  [[ $(id -u) != 0 ]] || skip_case "root lit ${1:-le fichier} malgré ses permissions"
}

run_case() {
  if [[ ${1:-} == --list ]]; then
    declare -F | awk '{ print $3 }' | grep '^case_' | sed 's/^case_//'
    return 0
  fi
  declare -F "case_${1:-}" > /dev/null || { echo "cas inconnu : ${1:-}" >&2; exit 2; }
  "case_$1"
}
