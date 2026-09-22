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

# Un cas de test emploie les enveloppes communes du dépôt (scripts/lib/shell.sh) : « shell_grep_into
# <variable> <arguments de grep> » distingue « rien trouvé » (1) d'une erreur de lecture, et remplit
# une variable de l'appelant — appelée dans « $(…) », une fonction ne pourrait pas arrêter le cas.
# Ici l'arrêt vaut 1, code d'un cas en échec, et non 2, l'anomalie des scripts.
shell_error_exit=1
# shellcheck source=../lib/shell.sh
. "$tests_dir/../lib/shell.sh"

# Un cas sans objet dans cet environnement sort en code 3 : run.sh le compte comme ignoré et affiche
# sa raison. Il n'échoue pas — et il ne se tait pas non plus, sans quoi la couverture baisserait en
# silence là où la suite tourne autrement (constat de la première exécution en CI, story 3.13).
# Un PDF minimal, **fabriqué octet par octet** : aucun PDF n'entre dans le dépôt, aucun générateur
# n'est ajouté, et chaque cas écrit exactement le défaut qu'il veut prouver. Un PDF minimal est du
# texte, et poppler reconstruit la table des références croisées : il n'y a rien à calculer.
#
# **Une seule écriture.** Trois stories en avaient fabriqué chacune la sienne — deux homonymes
# « pdf() » aux signatures incompatibles et un « ecrire_pdf() » —, la même structure recopiée trois
# fois (constat A3, rétrospective de l'epic 7). Les paramètres réunissent ce dont les trois avaient
# besoin, et aucun n'est obligatoire.
tests_pdf() { # $1 = chemin, $2 = texte de la page, $3 = auteur (métadonnée), $4 = XMP, $5 = octets de bourrage
  local chemin=$1 texte=${2:-Bonjour} auteur=${3:-} xmp=${4:-} bourrage=${5:-0} flux info="" objets=""
  mkdir -p "$(dirname "$chemin")"
  flux="BT /F1 12 Tf 20 150 Td ($texte) Tj ET"
  objets+="1 0 obj<</Type/Catalog/Pages 2 0 R"
  [[ -z $xmp ]] || objets+="/Metadata 97 0 R"
  objets+=">>endobj"$'\n'
  objets+="2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj"$'\n'
  objets+="3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 300]/Contents 4 0 R/Resources<</Font<</F1 99 0 R>>>>>>endobj"$'\n'
  objets+="4 0 obj<</Length ${#flux}>>stream"$'\n'"$flux"$'\n'"endstream endobj"$'\n'
  objets+="99 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj"$'\n'
  if [[ -n $auteur ]]; then
    objets+="98 0 obj<</Author ($auteur)>>endobj"$'\n'
    info="/Info 98 0 R"
  fi
  if [[ -n $xmp ]]; then
    local paquet="<?xpacket begin=\"\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?><x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description dc:description=\"$xmp\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"/></rdf:RDF></x:xmpmeta><?xpacket end=\"w\"?>"
    objets+="97 0 obj<</Type/Metadata/Subtype/XML/Length ${#paquet}>>stream"$'\n'"$paquet"$'\n'"endstream endobj"$'\n'
  fi
  {
    printf '%%PDF-1.4\n%s\n' "$objets"
    # Le bourrage pèse le fichier, pour les cas qui vérifient un poids annoncé ou un seuil.
    ((bourrage == 0)) || { printf '%%'; head -c "$bourrage" /dev/zero | tr '\0' 'A'; printf '\n'; }
    printf 'trailer<</Root 1 0 R%s/Size 100>>\n%%%%EOF\n' "$info"
  } > "$chemin"
}

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
