#!/usr/bin/env bash
# Contrôle « aucun secret » du dépôt commun, qui est public (AC 11 de la story outillage-14). Modèle :
# le garde-fou public/privé du projet source, qui refuse des chemins interdits et des motifs dans le
# contenu ET dans l'historique — mais sans liste de motifs privée : ce qui est cherché ici est un secret
# de forme connue, pas une donnée personnelle, et la liste peut donc être publique.
#
#   ci/check-secrets.sh                  arbre de travail, puis historique de toutes les références
#   ci/check-secrets.sh tree             fichiers suivis de l'arbre de travail
#   ci/check-secrets.sh history [<plage>]   lignes ajoutées et messages de chaque commit de la plage
#                                        (toutes les références par défaut), chemins jamais ajoutés
#
# Un signalement donne l'endroit — commit, fichier, ligne — et le numéro du motif, JAMAIS la ligne
# trouvée ni le motif lui-même : afficher le secret dans le journal de la CI publierait ce que le
# contrôle doit empêcher. Un commit poussé reste lisible par son SHA même après réécriture : c'est
# pourquoi tout l'historique est relu, et pas seulement l'arbre.
#
# Codes de sortie : 0 aucun secret ; 1 au moins un signalement ; 2 contrôle impossible (usage, dépôt
# illisible, outil en erreur). Procédure : procedures/secrets.md
set -euo pipefail
export LC_ALL=C

script_name=check-secrets
die() { printf '%s: %s\n' "$script_name" "$*" >&2; exit 2; }

# Chemins interdits, quelle que soit leur place : fichiers d'environnement (sauf les modèles), clés
# privées, magasins d'identifiants.
readonly forbidden_paths='(^|/)(\.env(\.[^/]*)?|id_(rsa|dsa|ecdsa|ed25519)|\.netrc|\.git-credentials|\.pgpass)$|\.(pem|key|p12|pfx|jks|kdbx)$'
readonly allowed_paths='(^|/)\.env\.(example|dist|sample)$'

# Motifs de secrets de forme connue, une expression régulière étendue par ligne. Chacun est écrit pour
# ne pas se trouver lui-même : la classe qui suit son préfixe ne contient pas « [ ».
# shellcheck disable=SC2016 # expressions régulières : « $ », « { » et « } » y sont des caractères littéraux
patterns=(
  '-----BEGIN ([A-Z]+ )*PRIVATE KEY( BLOCK)?-----'
  'gh[pousr]_[A-Za-z0-9]{36}'
  'github_pat_[A-Za-z0-9_]{60,}'
  'glpat-[A-Za-z0-9_-]{20,}'
  'AKIA[0-9A-Z]{16}'
  'xox[abposr]-[0-9A-Za-z-]{10,}'
  'sk-ant-[A-Za-z0-9_-]{20,}'
  'sk-[A-Za-z0-9_-]{40,}'
  'AIza[0-9A-Za-z_-]{35}'
  '[A-Z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|APIKEY|PRIVATE_KEY)[A-Z0-9_]*[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9/+_.~-]{20,}'
  'https?://[^/[:space:]:@<>${}]+:[^/[:space:]@<>${}]+@'
)

# Une référence à une variable d'environnement est un nom, pas une valeur : les exemples de code de la
# méthode BMAD en écrivent (« const SERVICE_API_KEY = process.env.SERVICE_API_KEY; »), et le motif des
# affectations les prendrait pour des secrets. La référence est retirée de la ligne avant de juger ;
# la ligne reste signalée si un motif la trouve encore — une vraie valeur à côté n'échappe pas.
# shellcheck disable=SC2016 # expression régulière : « $ » n'y figure pas, les apostrophes sont littérales
readonly env_reference='[=:][[:space:]]*["'"'"']?process\.env\.[A-Za-z_][A-Za-z0-9_]*["'"'"']?!?'

# 0 si un motif ne trouve la ligne qu'à cause d'une référence à une variable d'environnement ; 1 sinon,
# y compris quand une expression est illisible (le signalement est alors gardé).
reference_only() { # $1 = contenu de la ligne
  local line=$1 pattern code
  [[ $line =~ $env_reference ]] || return 1
  while [[ $line =~ $env_reference ]]; do line=${line//"${BASH_REMATCH[0]}"/=}; done
  for pattern in "${patterns[@]}"; do
    code=0
    # shellcheck disable=SC2319 # le code voulu est celui du test [[ =~ ]] : 2 dit une expression invalide
    [[ $line =~ $pattern ]] || code=$?
    ((code == 1)) || return 1
  done
  return 0
}

mode=all range=()
case ${1:-} in
  '') ;;
  tree) mode=tree; (($# == 1)) || die "usage : check-secrets.sh [tree | history [<plage>]]" ;;
  history) mode=history; shift; (($# <= 1)) || die "usage : check-secrets.sh [tree | history [<plage>]]"; range=("$@") ;;
  *) die "usage : check-secrets.sh [tree | history [<plage>]]" ;;
esac
((${#range[@]})) || range=(--all)

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "à lancer dans un dépôt git."
cd "$root"
tmp=$(mktemp -d) || die "dossier temporaire impossible."
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' "${patterns[@]}" > "$tmp/motifs"

findings=0
signal() { printf '%s: %s\n' "$script_name" "$1"; findings=$((findings + 1)); }

# Numéro (1, 2…) du premier motif qui trouve la ligne <n> du fichier <f> : jamais le motif lui-même.
pattern_number() { # $1 fichier, $2 numéro de ligne
  local i rc line
  line=$(sed -n "$2p" "$1") || return 2
  for i in "${!patterns[@]}"; do
    rc=0
    grep -qE -e "${patterns[$i]}" <<< "$line" || rc=$?
    ((rc != 0)) || { printf '%s' "$((i + 1))"; return 0; }
    ((rc == 1)) || return 2
  done
  printf '?'
}

# --- arbre de travail ----------------------------------------------------------------------------
scan_tree() {
  local paths path rc=0
  paths=$(git ls-files) || die "liste des fichiers suivis illisible."
  while IFS= read -r path; do
    [[ -n $path ]] || continue
    if [[ $path =~ $forbidden_paths && ! $path =~ $allowed_paths ]]; then
      signal "chemin interdit dans l'arbre : $path"
    fi
  done <<< "$paths"
  # git grep, aucune dépendance au grep du système pour le parcours. ⛔ --text et non -I : les fichiers
  # marqués « -diff » (.gitattributes : skills BMAD) passent pour binaires, et -I les sauterait en
  # silence. Le dépôt ne suit aucun vrai binaire ; s'il en suivait un, il serait lu comme du texte.
  git grep --text -n -E -f "$tmp/motifs" -- . > "$tmp/arbre" 2>"$tmp/arbre.err" || rc=$?
  ((rc <= 1)) && [[ ! -s $tmp/arbre.err ]] || die "recherche dans l'arbre impossible (git grep, code $rc)."
  ((rc == 0)) || return 0
  # « chemin:ligne:contenu » : le contenu n'est lu que pour écarter une référence à une variable
  # d'environnement ; il n'est jamais affiché
  local hit file line content
  while IFS= read -r hit; do
    [[ -n $hit ]] || continue
    file=${hit%%:*}
    hit=${hit#*:}
    line=${hit%%:*}
    content=${hit#*:}
    reference_only "$content" && continue
    signal "secret possible : fichier $file, ligne $line (motif $(pattern_number "$file" "$line"))"
  done < "$tmp/arbre"
}

# --- historique ----------------------------------------------------------------------------------
# Les lignes ajoutées par chaque commit sont écrites dans un fichier, une par ligne, et leur origine
# (commit, chemin, ligne) dans un index parallèle ; grep cherche dans le premier, l'index nomme l'endroit.
scan_history() {
  local rc=0 numbers number where content
  # --text : sans lui, un fichier « -diff » s'écrit « Binary files differ » et ses lignes échappent
  git log "${range[@]}" --no-color --no-renames --no-ext-diff --text -p -U0 --format='commit %H' > "$tmp/log" \
    || die "lecture de l'historique impossible."
  awk -v content="$tmp/ajouts" -v index_file="$tmp/index" '
    /^commit [0-9a-f]+$/ && length($2) == 40 { sha = substr($2, 1, 12); header = 0; next }
    /^diff --git / { header = 1; path = ""; next }
    header && /^\+\+\+ / {
      path = substr($0, 5); sub(/^"?b\//, "", path); sub(/"$/, "", path); next
    }
    header && /^@@ / { header = 0 }
    /^@@ / {
      plus = $3; sub(/^\+/, "", plus); sub(/,.*/, "", plus); line = plus + 0; next
    }
    !header && /^\+/ {
      print substr($0, 2) > content
      print sha "\t" path "\t" line > index_file
      line++
    }
  ' "$tmp/log" || die "lecture des différences impossible."
  touch "$tmp/ajouts" "$tmp/index"
  grep -nE -f "$tmp/motifs" "$tmp/ajouts" > "$tmp/trouves" 2>/dev/null || rc=$?
  ((rc <= 1)) || die "recherche dans l'historique impossible (grep, code $rc)."
  if ((rc == 0)); then
    numbers=$(cut -d: -f1 "$tmp/trouves") || die "lecture des correspondances impossible."
    while IFS= read -r number; do
      content=$(sed -n "${number}p" "$tmp/ajouts") || die "lignes ajoutées illisibles."
      reference_only "$content" && continue
      where=$(sed -n "${number}p" "$tmp/index") || die "index illisible."
      IFS=$'\t' read -r sha path line <<< "$where"
      signal "secret possible dans l'historique : commit $sha, fichier $path, ligne $line (motif $(pattern_number "$tmp/ajouts" "$number"))"
    done <<< "$numbers"
  fi
  # messages de commit
  git log "${range[@]}" --no-color --format='commit %H%n%B' > "$tmp/messages" || die "lecture des messages impossible."
  awk -v content="$tmp/msg" -v index_file="$tmp/msg-index" '
    /^commit [0-9a-f]+$/ && length($2) == 40 { sha = substr($2, 1, 12); n = 0; next }
    { n++; print > content; print sha "\t" n > index_file }
  ' "$tmp/messages" || die "lecture des messages impossible."
  touch "$tmp/msg" "$tmp/msg-index"
  rc=0
  grep -nE -f "$tmp/motifs" "$tmp/msg" > "$tmp/msg-trouves" 2>/dev/null || rc=$?
  ((rc <= 1)) || die "recherche dans les messages impossible (grep, code $rc)."
  if ((rc == 0)); then
    numbers=$(cut -d: -f1 "$tmp/msg-trouves") || die "lecture des correspondances impossible."
    while IFS= read -r number; do
      where=$(sed -n "${number}p" "$tmp/msg-index") || die "index illisible."
      IFS=$'\t' read -r sha line <<< "$where"
      signal "secret possible dans un message : commit $sha, ligne $line du message (motif $(pattern_number "$tmp/msg" "$number"))"
    done <<< "$numbers"
  fi
  # chemins jamais ajoutés, même supprimés depuis
  git log "${range[@]}" --no-color --no-renames --diff-filter=A --name-only --format='commit %H' > "$tmp/chemins" \
    || die "lecture des chemins de l'historique impossible."
  local current="" entry
  while IFS= read -r entry; do
    if [[ $entry =~ ^commit\ ([0-9a-f]{40})$ ]]; then current=${BASH_REMATCH[1]:0:12}; continue; fi
    [[ -n $entry ]] || continue
    if [[ $entry =~ $forbidden_paths && ! $entry =~ $allowed_paths ]]; then
      signal "chemin interdit dans l'historique : commit $current, $entry"
    fi
  done < "$tmp/chemins"
}

case $mode in
  tree) scan_tree ;;
  history) scan_history ;;
  all) scan_tree; scan_history ;;
esac

if ((findings)); then
  printf "%s: %s signalement(s) : retirer le secret, le révoquer s’il a été poussé, et réécrire l’historique avant tout push.\n" \
    "$script_name" "$findings" >&2
  exit 1
fi
printf '%s: aucun secret ni chemin interdit (%s).\n' "$script_name" "$mode"
