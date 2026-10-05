#!/usr/bin/env bash
# Suite de bin/install, une fois le prérequis bash vérifié. Ne se lance pas seul : passer par bin/install.
#
# Dans le projet qui consomme le dépôt commun en sous-module :
#   1. lit et valide le workflow.config du projet (code 2 sinon) ;
#   2. BMAD (story 1) : vérifie, AVANT toute écriture, que la version de BMAD déclarée par le projet
#      (bmad.version) est celle du sous-module (bmad/bmad.config), que chaque module activé
#      (bmad.modules) est dans l'union que porte le sous-module, et lit _bmad/config.user.toml ;
#   3. pose le lien « .working-method » vers le sous-module, point d'entrée stable de l'outillage
#      que citent les stubs de skills, quel que soit le chemin du sous-module ;
#   4. pose, dans chaque dossier de agents.skill-dirs, un lien relatif par skill du dépôt commun et
#      par skill BMAD des modules activés ;
#   5. pose la méthode BMAD dans _bmad/ par liens : _bmad/scripts, et dans chaque _bmad/<module>/ —
#      un VRAI dossier du projet — un lien par fichier de méthode (décision D du 04/10/2026) ;
#   6. génère la configuration BMAD : _bmad/config.toml depuis workflow.config (versionné),
#      _bmad/<module>/config.yaml depuis workflow.config et _bmad/config.user.toml (non versionnés),
#      _bmad/_config/bmad-help.csv, le catalogue d'aide des modules activés (décision E) ;
#   7. retire ce qu'une installation précédente avait posé pour un module désormais désactivé.
#
# ⛔ Rien n'est jamais écrasé, sauf la configuration générée : une entrée qui existe déjà et n'est pas
# le lien attendu est un conflit, et rien n'est écrit tant qu'il en reste un (code 1). Un fichier
# généré qui diffère de la génération est réécrit, et l'écrasement est SIGNALÉ (« ATTENTION ») : une
# édition à la main n'est jamais conservée en silence. Relancé, le script ne change rien.
#
# Codes de sortie : 0 installé ou déjà en place ; 1 conflit, version de BMAD différente de celle du
# sous-module, ou module hors de l'union ; 2 installation impossible (pas dans un projet qui consomme
# ce dépôt en sous-module, workflow.config ou _bmad/config.user.toml refusés, déclaration ou méthode du
# sous-module illisibles, option inconnue).
# Procédures : procedures/adoption.md, procedures/bmad.md
set -euo pipefail

script_name=install
common=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../lib/bmad.sh
. "$common/lib/bmad.sh"
die() { printf '%s: %s\n' "$script_name" "$*" >&2; exit 2; }
refuse() { printf '%s: %s\n' "$script_name" "$*" >&2; exit 1; }

readonly entry_link=.working-method
readonly generated_mark="# Généré par bin/install du dépôt commun"

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

# --- BMAD : tout ce qui peut refuser, avant la première écriture ---------------------------------
# Le schéma n'est plus vérifié ici : le lecteur ne lit que le schéma 3, qui porte les trois champs
# bmad.* de la configuration générée ; un fichier au schéma 1 ou 2 est refusé par config_load (code 2).
config_get bmad_project_name bmad.project-name
config_get bmad_document_language bmad.document-output-language
config_get bmad_output_folder bmad.output-folder
readonly bmad_project_name bmad_document_language bmad_output_folder

bmad_declared_load "$common/bmad/bmad.config" || die "déclaration de BMAD du sous-module illisible : $submodule/bmad/bmad.config."
[[ $bmad_version == "$bmad_declared_version" ]] \
  || refuse "workflow.config déclare BMAD $bmad_version, le sous-module porte BMAD $bmad_declared_version : monter le sous-module, ou aligner bmad.version (procedures/bmad.md)."
[[ " $bmad_modules " == *" core "* ]] || refuse "bmad.modules : « core » est requis (il porte bmad-help et les scripts de configuration)."
for module in $bmad_modules; do
  [[ " $bmad_declared_modules " == *" $module "* ]] \
    || refuse "bmad.modules : « $module » n'est pas porté par le sous-module (BMAD $bmad_declared_version : $bmad_declared_modules)."
done

method="$common/bmad/method"
for required in skills scripts modules templates/config.toml bmad-help.csv skill-manifest.csv; do
  [[ -e $method/$required ]] || die "méthode BMAD incomplète dans le sous-module : $submodule/bmad/method/$required absent (relancer bmad/update.sh dans le dépôt commun)."
done
for module in $bmad_modules; do
  [[ -d $method/modules/$module && -f $method/templates/$module.config.yaml ]] \
    || die "méthode BMAD incomplète dans le sous-module : module $module (relancer bmad/update.sh dans le dépôt commun)."
  compgen -G "$method/modules/$module/*" > /dev/null \
    || die "méthode du module $module vide dans le sous-module (relancer bmad/update.sh dans le dépôt commun)."
done
bmad_skill_manifest_load "$method/skill-manifest.csv" || die "table des skills BMAD du sous-module illisible."

# Les clés de la couche utilisatrice que demandent les modèles des modules activés.
user_keys=()
for module in $bmad_modules; do
  template_text=$(<"$method/templates/$module.config.yaml") || die "modèle de $module illisible."
  while [[ $template_text =~ @user:([a-z0-9_.-]+)@ ]]; do
    key=${BASH_REMATCH[1]}
    [[ " ${user_keys[*]-} " == *" $key "* ]] || user_keys+=("$key")
    template_text=${template_text//"@user:$key@"/}
  done
done
user_file="_bmad/config.user.toml"
if ! bmad_user_load "$project/$user_file"; then
  printf '%s: %s est la couche utilisatrice de BMAD : jamais écrit par bin/install, il doit porter, en « clé = "valeur" » : %s (procedures/bmad.md).\n' \
    "$script_name" "$user_file" "${user_keys[*]-}" >&2
  exit 2
fi
missing=()
for key in ${user_keys[@]+"${user_keys[@]}"}; do
  [[ -n ${bmad_user_values[$key]+x} ]] || missing+=("$key")
done
((${#missing[@]} == 0)) || die "$user_file : clé(s) absente(s) : ${missing[*]} (aucune valeur par défaut)."

bmad_placeholders=(
  [bmad.project-name]=$bmad_project_name
  [bmad.document-output-language]=$bmad_document_language
  [bmad.output-folder]=$bmad_output_folder
)
# « ${t[@]+…} » : sous set -u, bash 4.3 tient un tableau vide pour non défini (corrigé en 4.4)
for key in ${bmad_user_values[@]+"${!bmad_user_values[@]}"}; do bmad_placeholders[user:$key]=${bmad_user_values[$key]}; done

# --- la configuration générée, préparée hors du projet -------------------------------------------
staging=$(mktemp -d) || die "dossier temporaire impossible."
trap 'rm -rf "$staging"' EXIT
generated=()   # chemins relatifs au projet ; leur contenu est sous $staging/<chemin>
mkdir -p "$staging/_bmad/_config"
bmad_config_toml "$method/templates/config.toml" "$staging/config.toml.modele" "$bmad_modules" || exit 2
bmad_render "$staging/config.toml.modele" "$staging/config.toml.rendu" || exit 2
# Chaque écriture a sa garde : un bloc « { …; } > f || die » suspendrait set -e à l'intérieur, et une
# écriture en échec suivie d'une écriture réussie passerait en silence.
toml="$staging/_bmad/config.toml"
printf '%s depuis workflow.config (BMAD %s, modules : %s) — ne pas éditer.\n' "$generated_mark" "$bmad_version" "$bmad_modules" > "$toml" \
  || die "génération de _bmad/config.toml impossible."
printf '# Une édition à la main est écrasée au prochain bin/install, et signalée. Réglage durable : workflow.config,\n# ou _bmad/custom/config.toml (équipe) et _bmad/custom/config.user.toml (personnel), que BMAD lit par-dessus.\n\n' >> "$toml" \
  || die "génération de _bmad/config.toml impossible."
cat "$staging/config.toml.rendu" >> "$toml" || die "génération de _bmad/config.toml impossible."
generated+=(_bmad/config.toml)
for module in $bmad_modules; do
  mkdir -p "$staging/_bmad/$module"
  bmad_render "$method/templates/$module.config.yaml" "$staging/$module.rendu" || exit 2
  yaml="$staging/_bmad/$module/config.yaml"
  printf '%s depuis workflow.config et %s — ne pas éditer.\n# Non versionné. Une édition à la main est écrasée au prochain bin/install, et signalée.\n' \
    "$generated_mark" "$user_file" > "$yaml" || die "génération de _bmad/$module/config.yaml impossible."
  cat "$staging/$module.rendu" >> "$yaml" || die "génération de _bmad/$module/config.yaml impossible."
  generated+=("_bmad/$module/config.yaml")
done
bmad_help_catalog "$method/bmad-help.csv" "$method/modules" "$staging/_bmad/_config/bmad-help.csv" "$bmad_modules" || exit 2
generated+=(_bmad/_config/bmad-help.csv)

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
bmad_skills=()
for skill in "${!bmad_skill_module[@]}"; do
  [[ " $bmad_modules " == *" ${bmad_skill_module[$skill]} "* ]] || continue
  [[ -f $method/skills/$skill/SKILL.md ]] || die "skill BMAD $skill absente du sous-module."
  bmad_skills+=("$skill")
done
((${#bmad_skills[@]})) || die "aucune skill BMAD pour les modules $bmad_modules : méthode du sous-module incohérente."
mapfile -t bmad_skills < <(printf '%s\n' "${bmad_skills[@]}" | LC_ALL=C sort)
for dir in $skill_dirs; do
  for skill_file in "${skills[@]}"; do
    skill=${skill_file%/SKILL.md}
    skill=${skill##*/}
    links+=("$dir/$skill"$'\t'"$(up "$dir")$submodule/skills/$skill")
  done
  for skill in "${bmad_skills[@]}"; do
    links+=("$dir/$skill"$'\t'"$(up "$dir")$submodule/bmad/method/skills/$skill")
  done
done
links+=("_bmad/scripts"$'\t'"../$submodule/bmad/method/scripts")
for module in $bmad_modules; do
  for entry in "$method/modules/$module"/*; do
    entry=${entry##*/}
    links+=("_bmad/$module/$entry"$'\t'"../../$submodule/bmad/method/modules/$module/$entry")
  done
done

# --- vérification : aucun conflit avant la première écriture -------------------------------------
conflicts=() todo=() kept=0
declare -A planned=()
for link in "${links[@]}"; do
  path=${link%%$'\t'*}
  target=${link#*$'\t'}
  planned[$path]=1
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
# Les dossiers parents : un parent qui existe sans être un dossier ferait échouer l'écriture à mi-chemin
# (mkdir -p), après d'autres écritures ; et sous _bmad/, un parent qui est un lien ferait écrire la
# configuration du projet ailleurs — dans le sous-module, par exemple. Les deux sont des conflits.
declare -A parent_seen=()
for path in "${links[@]%%$'\t'*}" "${generated[@]}"; do
  parent=$(dirname "$path")
  while [[ $parent != . && -z ${parent_seen[$parent]+x} ]]; do
    parent_seen[$parent]=1
    if [[ -L $parent && ( $parent == _bmad || $parent == _bmad/* ) ]]; then
      conflicts+=("$parent : un lien ; un vrai dossier du projet est attendu (procedures/bmad.md)")
    elif [[ -e $parent && ! -d $parent ]]; then
      conflicts+=("$parent : existe et n'est pas un dossier")
    fi
    parent=$(dirname "$parent")
  done
done
for path in "${generated[@]}"; do
  if [[ -L $path || (-e $path && ! -f $path) ]]; then
    conflicts+=("$path : existe et n'est pas un fichier ; la configuration générée y est attendue")
  fi
done
tracked=$(git -C "$project" ls-files -- '_bmad/*/config.yaml') || die "lecture de l'index du projet impossible."
while IFS= read -r path; do
  [[ -n $path ]] || continue
  conflicts+=("$path : suivi par git, alors qu'il dépend de $user_file : le retirer de l'index (git rm --cached) et l'ignorer")
done <<< "$tracked"
if ((${#conflicts[@]})); then
  printf "%s: %s conflit(s), rien n’est écrit :\n" "$script_name" "${#conflicts[@]}" >&2
  printf '  - %s\n' "${conflicts[@]}" >&2
  printf "%s: rien n’est écrasé : résoudre chaque conflit (procedures/adoption.md), puis relancer.\n" "$script_name" >&2
  exit 1
fi

# --- écriture : liens ------------------------------------------------------------------------------
# « ${t[@]+…} » : sous set -u, bash 4.3 tient un tableau vide pour non défini (corrigé en 4.4)
for link in ${todo[@]+"${todo[@]}"}; do
  path=${link%%$'\t'*}
  target=${link#*$'\t'}
  mkdir -p "$(dirname "$path")" || die "dossier de $path impossible à créer."
  ln -s "$target" "$path" || die "lien $path impossible à poser."
  printf '%s: lien posé : %s → %s\n' "$script_name" "$path" "$target"
done
printf '%s: %s lien(s) posé(s), %s déjà en place.\n' "$script_name" "${#todo[@]}" "$kept"

# --- retrait de ce qui visait un module désactivé, ou une méthode disparue -----------------------
# Seuls les liens qui pointent dans la méthode BMAD du sous-module sont candidats : un lien du projet,
# ou de l'outillage, n'est jamais retiré.
removed=0
shopt -s nullglob
for dir in $skill_dirs _bmad _bmad/*/; do
  dir=${dir%/}
  [[ -d $dir && ! -L $dir ]] || continue
  for path in "$dir"/*; do
    [[ -L $path && -z ${planned[$path]+x} ]] || continue
    current=$(readlink -- "$path") || die "lecture du lien $path impossible."
    [[ $current == *"$submodule/bmad/method/"* ]] || continue
    rm -- "$path" || die "retrait du lien $path impossible."
    printf '%s: lien retiré : %s (module désactivé ou absent de la méthode)\n' "$script_name" "$path"
    removed=$((removed + 1))
  done
done
for dir in _bmad/*/; do
  module=${dir%/}
  module=${module#_bmad/}
  [[ " $bmad_declared_modules " == *" $module "* && " $bmad_modules " != *" $module "* ]] || continue
  if [[ -f _bmad/$module/config.yaml ]] && IFS= read -r first < "_bmad/$module/config.yaml" \
    && [[ $first == "$generated_mark"* ]]; then
    rm -- "_bmad/$module/config.yaml" || die "retrait de _bmad/$module/config.yaml impossible."
    printf '%s: configuration retirée : _bmad/%s/config.yaml (module désactivé)\n' "$script_name" "$module"
  fi
  # un dossier qui garde un fichier du projet reste : seul un dossier vidé par ce qui précède part
  rmdir -- "_bmad/$module" 2>/dev/null || true
done
shopt -u nullglob

# --- écriture : configuration générée ------------------------------------------------------------
written=0 unchanged=0 replaced=0
for path in "${generated[@]}"; do
  if [[ -f $path ]] && cmp -s "$staging/$path" "$path"; then
    unchanged=$((unchanged + 1))
    continue
  fi
  if [[ -f $path ]]; then
    printf '%s: ATTENTION : %s différait de ce que génèrent workflow.config et %s : remplacé, une édition à la main est perdue. Réglage durable : workflow.config, %s ou _bmad/custom/ (procedures/bmad.md).\n' \
      "$script_name" "$path" "$user_file" "$user_file" >&2
    replaced=$((replaced + 1))
  else
    written=$((written + 1))
  fi
  mkdir -p "$(dirname "$path")" || die "dossier de $path impossible à créer."
  cp "$staging/$path" "$path" || die "écriture de $path impossible."
done
printf '%s: BMAD %s (modules : %s) : %s skill(s) BMAD reliée(s) par dossier ; configuration : %s écrite(s), %s inchangée(s), %s remplacée(s) ; %s lien(s) retiré(s).\n' \
  "$script_name" "$bmad_version" "$bmad_modules" "${#bmad_skills[@]}" "$written" "$unchanged" "$replaced" "$removed"
