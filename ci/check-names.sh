#!/usr/bin/env bash
# Contrôle « aucun nom de projet consommateur » dans l'arbre du dépôt commun (AC 3 de la story
# outillage-14) : tout ce qui est propre à un projet se lit dans son workflow.config, jamais ici.
#
#   CHECK_NAMES_PATTERNS=<liste> ci/check-names.sh
#   ci/check-names.sh --patterns-file <fichier>
#
# ⛔ La liste des noms n'est PAS dans l'arbre : écrite ici, elle serait elle-même un nom de projet dans
# le dépôt commun (constat bloquant de la première revue de ce dépôt). Comme le garde-fou public/privé
# du projet source, qui lit ses motifs hors du dépôt, ce contrôle reçoit sa liste de l'extérieur : en
# CI, la variable d'Actions du dépôt CHECK_NAMES_PATTERNS ; sur le poste, un fichier. Une expression
# régulière étendue par ligne, insensible à la casse ; lignes vides et « # … » ignorées.
# Sans liste, ou avec une liste vide, le contrôle sort en 2 : un contrôle sans liste ne contrôle rien,
# et ne passe jamais pour vert.
#
# Le contrôle porte sur l'ARBRE, pas sur l'historique (précision d'Arnaud du 03/10/2026) : l'historique
# importé du projet source garde ses références, ses renvois de PR compris.
#
# Codes de sortie : 0 aucun nom ; 1 au moins un nom trouvé (fichier et ligne, jamais le nom) ;
# 2 contrôle impossible. Procédure : procedures/secrets.md
set -euo pipefail
export LC_ALL=C

script_name=check-names
die() { printf '%s: %s\n' "$script_name" "$*" >&2; exit 2; }

patterns_file=""
case $# in
  0) ;;
  2) [[ $1 == --patterns-file ]] || die "usage : check-names.sh [--patterns-file <fichier>]"; patterns_file=$2 ;;
  *) die "usage : check-names.sh [--patterns-file <fichier>]" ;;
esac
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "à lancer dans un dépôt git."
tmp=$(mktemp -d) || die "dossier temporaire impossible."
trap 'rm -rf "$tmp"' EXIT
if [[ -n $patterns_file ]]; then
  [[ -r $patterns_file ]] || die "liste des noms illisible : $patterns_file."
  cp "$patterns_file" "$tmp/brut" || die "liste des noms illisible : $patterns_file."
else
  [[ -n ${CHECK_NAMES_PATTERNS:-} ]] \
    || die "liste des noms absente (CHECK_NAMES_PATTERNS, ou --patterns-file) : aucun contrôle sans liste."
  printf '%s\n' "$CHECK_NAMES_PATTERNS" > "$tmp/brut"
fi
rc=0
grep -vE '^[[:space:]]*(#|$)' "$tmp/brut" > "$tmp/noms" || rc=$?
((rc <= 1)) || die "lecture de la liste des noms impossible."
[[ -s $tmp/noms ]] || die "liste des noms vide : aucun contrôle sans liste."
# chaque expression est validée par bash : le grep de BusyBox rendrait « aucune correspondance » sur
# une expression invalide (procedures/shell-scripts.md)
while IFS= read -r name; do
  rc=0
  # shellcheck disable=SC2319 # le code voulu est celui du test [[ =~ ]] : 2 dit une expression invalide
  [[ x =~ $name ]] 2>/dev/null || rc=$?
  ((rc <= 1)) || die "expression invalide dans la liste des noms (ligne non affichée)."
done < "$tmp/noms"
cd "$root"

findings=0
rc=0
# --text et non -I : un fichier « -diff » (.gitattributes : skills BMAD) passerait pour binaire et
# serait sauté en silence
git grep --text -n -i -E -f "$tmp/noms" -- . > "$tmp/trouves" 2>"$tmp/err" || rc=$?
((rc <= 1)) && [[ ! -s $tmp/err ]] || die "recherche impossible (git grep, code $rc)."
if ((rc == 0)); then
  while IFS=: read -r file line _; do
    printf '%s: nom de projet dans %s, ligne %s\n' "$script_name" "$file" "$line"
    findings=$((findings + 1))
  done < "$tmp/trouves"
fi
paths=$(git ls-files) || die "liste des fichiers suivis illisible."
rc=0
grep -i -E -f "$tmp/noms" <<< "$paths" > "$tmp/chemins" || rc=$?
((rc <= 1)) || die "recherche dans les chemins impossible (grep, code $rc)."
if ((rc == 0)); then
  while IFS= read -r path; do
    printf '%s: nom de projet dans le chemin %s\n' "$script_name" "$path"
    findings=$((findings + 1))
  done < "$tmp/chemins"
fi

if ((findings)); then
  printf "%s: %s nom(s) de projet dans l’arbre : le lire dans workflow.config, ou le décrire sans le nommer.\n" \
    "$script_name" "$findings" >&2
  exit 1
fi
printf "%s: aucun nom de projet consommateur dans l’arbre.\n" "$script_name"
