# shellcheck shell=bash
# Outils communs des fichiers de test, chargés en tête de chaque fichier de test : ceux du dépôt
# commun (tests/test-*.sh) comme ceux d'un projet qui le consomme.
#
# Un fichier de test définit des fonctions case_<nom> et se termine par « run_case "$@" » :
#   bash tests/test-x.sh --list    liste les cas
#   bash tests/test-x.sh <nom>     lance un cas ; code non nul en cas d'échec
# Chaque cas dispose d'un dossier temporaire $work, supprimé à la fin.
set -euo pipefail

# Aucun processus git détaché ne doit survivre à un cas. Chaque commit lance « git maintenance run
# --auto --detach », qui continue après la fin du cas : s'il réécrivait le dépôt d'essai (repack,
# prune-packed) pendant le « rm -rf » de fin de cas (trap ci-dessous), rm échouerait sur un fichier
# disparu ou un dossier recréé, sans rapport avec le code du cas (piège « processus git détaché » de
# procedures/shell-scripts.md). La configuration passe par l'environnement, et non par chaque dépôt :
# elle vaut pour tout dépôt que le cas crée, clone ou fait créer à un script testé, sous-modules
# compris. Elle s'ajoute à celle que l'appelant aurait déjà injectée, sans la remplacer, et elle est
# posée avant le premier appel à git : un compte injecté illisible est nommé ici, et non par l'échec
# du premier git venu.
#   maintenance.auto=false  aucune maintenance automatique après un commit, un fetch ou une fusion ;
#   gc.auto=0               aucun « git gc --auto », par la maintenance ou par une autre commande ;
#   core.fsmonitor=false    aucun démon fsmonitor, même si la configuration du poste l'active.
tests_git_config() {
  local n=${GIT_CONFIG_COUNT:-0} pair
  [[ $n =~ ^[0-9]+$ ]] || { echo "tests: GIT_CONFIG_COUNT illisible : $n" >&2; exit 2; }
  n=$((10#$n)) # « 08 » est un compte valable pour git, pas un octal
  for pair in maintenance.auto=false gc.auto=0 core.fsmonitor=false; do
    export "GIT_CONFIG_KEY_$n=${pair%%=*}" "GIT_CONFIG_VALUE_$n=${pair#*=}"
    n=$((n + 1))
  done
  export GIT_CONFIG_COUNT=$n
}
tests_git_config

# tests_dir est le dossier de cette bibliothèque et common la racine du dépôt commun ; root est la racine du dépôt
# git qui porte le fichier de test, et fixtures le dossier « fixtures » voisin de ce fichier. Un
# projet consommateur qui charge cette bibliothèque depuis ses propres tests garde donc ses chemins,
# et le dépôt commun les siens.
tests_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC2034 # lue par les fichiers de test qui chargent cette bibliothèque
common=$(cd "$tests_dir/.." && pwd)
caller_dir=$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)
root=$(git -C "$caller_dir" rev-parse --show-toplevel 2>/dev/null) \
  || { echo "tests: $caller_dir n'est pas dans un dépôt git." >&2; exit 2; }
# shellcheck disable=SC2034 # lue par les fichiers de test qui chargent cette bibliothèque
fixtures="$caller_dir/fixtures"
cd "$root"

work=$(mktemp -d)
trap 'chmod -R u+rwx "$work" 2>/dev/null || true; rm -rf "$work"' EXIT

# Lance une commande et garde son code dans rc, sa sortie dans out, son erreur dans err.
# Les fonctions testées ne comptent pas sur set -e : les appeler derrière || reflète leur usage réel.
run() {
  rc=0
  # shellcheck disable=SC2034 # lue par les fichiers de test qui chargent cette bibliothèque
  "$@" > "$work/.out" 2> "$work/.err" || rc=$?
  # shellcheck disable=SC2034 # lue par les fichiers de test qui chargent cette bibliothèque
  out=$(cat "$work/.out")
  # shellcheck disable=SC2034 # lue par les fichiers de test qui chargent cette bibliothèque
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

# Un cas de test emploie les enveloppes communes (lib/shell.sh du dépôt commun) : « shell_grep_into
# <variable> <arguments de grep> » distingue « rien trouvé » (1) d'une erreur de lecture, et remplit
# une variable de l'appelant — appelée dans « $(…) », une fonction ne pourrait pas arrêter le cas.
# Ici l'arrêt vaut 1, code d'un cas en échec, et non 2, l'anomalie des scripts.
shell_error_exit=1
# shellcheck source=../lib/shell.sh
. "$tests_dir/../lib/shell.sh"

# Écrit un workflow.config complet et valide dans <dossier>, puis applique les changements donnés :
# « champ=valeur » remplace une valeur, « -champ » retire le champ. L'écriture passe par git config,
# qui cite lui-même ce qui doit l'être. Les valeurs de base décrivent un projet fictif à suivi numéroté.
write_workflow_config() { # $1 = dossier, $2… = changements
  local dir=$1 file change key
  file="$dir/workflow.config"
  shift
  mkdir -p "$dir"
  : > "$file"
  local -a base=(
    workflow.schema=3
    forge.repo=Proprietaire/projet-essai
    forge.base=dev
    forge.release-branch=main
    "forge.branch-prefixes=feat fix chore docs"
    forge.env-file=.env
    sprint.convention=numbered
    sprint.status-file=_bmad-output/implementation-artifacts/sprint-status.yaml
    sprint.stories-dir=_bmad-output/implementation-artifacts
    sprint.spec-source=_bmad-output/planning-artifacts/epics.md
    "review.exempt-paths=^_bmad-output/"
    review.report=pr-comment
    "review.reviewers=claude=gemini-3.1-pro-high gemini=claude-opus-4-6-thinking gpt=claude-opus-4-6-thinking"
    review.timeout=900
    review.project-layer=review/project-layer.md
    "review.private-paths=.env docs/private .pr-body.md"
    review.range-exclude=_bmad-output
    guard.command=scripts/check-private.sh
    guard.patterns-file=docs/private/forbidden-patterns.txt
    ci.workflow=.gitea/workflows/checks.yaml
    ci.status-context=checks
    ci.bootstrap=true
    checks.command=scripts/check.sh
    checks.dir=scripts/checks
    "tests.protected-outputs=public build"
    bmad.version=6.12.0
    "bmad.modules=core bmm"
    bmad.project-name=projet-essai
    bmad.document-output-language=Français
    bmad.output-folder=_bmad-output
    "agents.skill-dirs=.claude/skills .agents/skills"
  )
  for change in "${base[@]}" "$@"; do
    if [[ $change == -* ]]; then
      git config -f "$file" --unset "${change#-}"
    else
      key=${change%%=*}
      git config -f "$file" "$key" "${change#*=}"
    fi
  done
}

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

# Le lanceur place en tête du PATH de chaque cas de faux docker, curl, psql et ssh, qui font échouer le
# cas (tests/run.sh) ; leur dossier, marqué d'un fichier .faux-du-lanceur, est dans TESTS_FORBIDDEN_DIR.
# Un cas qui emploie l'un de ces outils HORS RÉSEAU (curl sur une URL file://, par exemple) demande
# nommément le vrai binaire : le PATH est parcouru sans les dossiers marqués ; une entrée vide du PATH (le dossier courant) n'est jamais retenue. Rend 1
# si l'outil est introuvable. Pour curl, préférer file_only_curl, qui refuse toute autre URL.
real_command() { # $1 outil ; affiche le chemin du vrai binaire
  local dir
  local -a dirs
  IFS=: read -r -a dirs <<< "$PATH"
  for dir in ${dirs[@]+"${dirs[@]}"}; do
    # un dossier de faux porte la marque du lanceur : celui de ce lanceur, et ceux d'un lanceur qui
    # l'a lui-même lancé (tests/test-run.sh lance run.sh dans un cas)
    [[ -n $dir && ! -e $dir/.faux-du-lanceur ]] || continue
    if [[ -f $dir/$1 && -x $dir/$1 ]]; then
      printf '%s\n' "$dir/$1"
      return 0
    fi
  done
  return 1
}

# Un chemin cité pour sh, entre apostrophes, les siennes échappées : pour écrire un faux binaire.
sh_quote() { # $1 chemin ; l'affiche cité
  local q="'"
  printf "'%s'" "${1//$q/$q\\$q$q}"
}

# Un curl réduit aux URL file:// : le vrai, pour un script testé qui « télécharge » un fichier local.
# Une URL d'un autre schéma passe au faux curl du lanceur, qui note l'appel et fait échouer le cas ;
# hors du lanceur, elle est refusée en 2. Une adresse sans schéma (« curl example.com ») ne se
# distingue pas d'un argument ordinaire : curl lui-même la refuse, par --proto =file (et
# --proto-redir =file pour une redirection), placés avant ET après ses arguments. Une option --proto*
# du script testé passe au faux du lanceur, comme une URL : rien ne lève la restriction.
file_only_curl() { # $1 = dossier où écrire curl
  local real refuse
  real=$(real_command curl) || { echo "tests: curl introuvable." >&2; exit 2; }
  if [[ -n ${TESTS_FORBIDDEN_DIR:-} ]]; then
    refuse="exec $(sh_quote "$TESTS_FORBIDDEN_DIR/curl") \"\$@\""
  else
    refuse='echo "tests: curl hors file:// refusé." >&2; exit 2'
  fi
  mkdir -p "$1"
  # shellcheck disable=SC2016 # faux binaire écrit sur le disque : ses « $ » s'y développent à l'exécution
  printf '#!/bin/sh\nfor a in "$@"; do\n  case $a in\n    file://*) ;;\n    *://* | --proto*) %s ;;\n  esac\ndone\nexec %s --proto =file --proto-redir =file "$@" --proto =file --proto-redir =file\n' \
    "$refuse" "$(sh_quote "$real")" > "$1/curl"
  chmod 755 "$1/curl"
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
