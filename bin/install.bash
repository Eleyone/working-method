#!/usr/bin/env bash
# Suite de bin/install, une fois le prérequis bash vérifié. Ne se lance pas seul : passer par bin/install.
#
# Dans le projet qui consomme le dépôt commun en sous-module :
#   1. lit et valide le workflow.config du projet (code 2 sinon) ;
#   2. pose le lien « .working-method » vers le sous-module, point d'entrée stable de l'outillage
#      que citent les stubs de skills, quel que soit le chemin du sous-module ;
#   3. pose, dans chaque dossier de agents.skill-dirs, un lien relatif par skill du dépôt commun ;
#   4. BMAD : place réservée à la story 1, qui l'écrira ; rien n'est installé ici.
#
# ⛔ Rien n'est jamais écrasé : une entrée qui existe déjà et n'est pas le lien attendu est un conflit,
# et aucun lien n'est posé tant qu'il en reste un (code 1). Relancé, le script ne change rien : un lien
# déjà en place est laissé tel quel.
#
# Codes de sortie : 0 installé ou déjà en place ; 1 conflit ; 2 installation impossible (pas dans un
# projet qui consomme ce dépôt en sous-module, workflow.config refusé, option inconnue).
# Procédure : procedures/adoption.md
set -euo pipefail

script_name=install
common=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../lib/config.sh
. "$common/lib/config.sh"
die() { printf '%s: %s\n' "$script_name" "$*" >&2; exit 2; }

readonly entry_link=.working-method

(($# == 0)) || die "aucune option n'est admise. usage : <sous-module>/bin/install"

project=$(git -C "$common" rev-parse --show-superproject-working-tree 2>/dev/null) \
  || die "lecture du dépôt git impossible."
[[ -n $project ]] \
  || die "le dépôt commun n'est pas un sous-module : bin/install se lance depuis un projet qui le consomme."
project=$(cd "$project" && pwd -P) || die "projet introuvable."
[[ $common == "$project"/* ]] || die "le sous-module n'est pas sous la racine du projet."
submodule=${common#"$project"/}
cd "$project"

config_load "$project/workflow.config" || exit 2
config_get skill_dirs agents.skill-dirs
config_get bmad_version bmad.version
config_get bmad_modules bmad.modules
readonly skill_dirs bmad_version bmad_modules

# --- plan : chaque lien attendu, avec sa cible relative -----------------------------------------
links=()   # « chemin<TAB>cible »
up() { # $1 = chemin relatif d'un dossier ; affiche autant de « ../ » qu'il a de composants
  local dir=$1 prefix=""
  while [[ -n $dir && $dir != . ]]; do
    prefix+="../"
    [[ $dir == */* ]] && dir=${dir%/*} || dir=""
  done
  printf '%s' "$prefix"
}
if [[ $submodule != "$entry_link" ]]; then
  links+=("$entry_link"$'\t'"$submodule")
fi
shopt -s nullglob
skills=("$common"/skills/*/SKILL.md)
shopt -u nullglob
((${#skills[@]})) || die "aucun skill dans $submodule/skills : dépôt commun incomplet."
for dir in $skill_dirs; do
  for skill_file in "${skills[@]}"; do
    skill=${skill_file%/SKILL.md}
    skill=${skill##*/}
    links+=("$dir/$skill"$'\t'"$(up "$dir")$submodule/skills/$skill")
  done
done

# --- vérification : aucun conflit avant la première écriture -------------------------------------
conflicts=() todo=() kept=0
for link in "${links[@]}"; do
  path=${link%%$'\t'*}
  target=${link#*$'\t'}
  if [[ -L $path ]]; then
    current=$(readlink -- "$path") || die "lecture du lien $path impossible."
    if [[ $current == "$target" ]]; then
      kept=$((kept + 1))
    else
      conflicts+=("$path : lien vers « $current », « $target » attendu")
    fi
  elif [[ -e $path ]]; then
    conflicts+=("$path : existe déjà et n'est pas un lien")
  else
    todo+=("$link")
  fi
done
if ((${#conflicts[@]})); then
  printf '%s: %s conflit(s), aucun lien posé :\n' "$script_name" "${#conflicts[@]}" >&2
  printf '  - %s\n' "${conflicts[@]}" >&2
  printf "%s: rien n’est écrasé : résoudre chaque conflit (procedures/adoption.md), puis relancer.\n" "$script_name" >&2
  exit 1
fi

# --- écriture ------------------------------------------------------------------------------------
# « ${t[@]+…} » : sous set -u, bash 4.3 tient un tableau vide pour non défini (corrigé en 4.4)
for link in ${todo[@]+"${todo[@]}"}; do
  path=${link%%$'\t'*}
  target=${link#*$'\t'}
  mkdir -p "$(dirname "$path")" || die "dossier de $path impossible à créer."
  ln -s "$target" "$path" || die "lien $path impossible à poser."
  printf '%s: lien posé : %s → %s\n' "$script_name" "$path" "$target"
done
printf '%s: %s lien(s) posé(s), %s déjà en place.\n' "$script_name" "${#todo[@]}" "$kept"

# --- BMAD : place réservée -----------------------------------------------------------------------
# La story 1 relie ici les modules BMAD du dépôt commun, génère la configuration BMAD du projet depuis
# workflow.config et refuse un écart de version. Tant qu'elle n'est pas faite, rien n'est installé —
# et le script le dit plutôt que de laisser croire que BMAD vient du sous-module.
printf "%s: BMAD %s (modules : %s) déclaré dans workflow.config : installation réservée à la story 1, rien n’est installé ni vérifié.\n" \
  "$script_name" "$bmad_version" "$bmad_modules"
