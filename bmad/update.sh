#!/usr/bin/env bash
# (Ré)installe BMAD dans le dépôt commun : rejoue l'installeur BMAD épinglé par bmad/bmad.config dans
# un dossier jetable, puis réécrit bmad/method/ avec ce qu'il a produit — la méthode seulement.
#
#   bash bmad/update.sh
#
# ⛔ C'est le SEUL endroit où l'installeur BMAD tourne (décision d'Arnaud du 30/09/2026) : un projet
# reçoit des liens vers bmad/method/ et une configuration générée par bin/install, jamais l'installeur.
#
# Ce que bmad/method/ reçoit, et rien d'autre :
#   skills/<skill>/                 les skills, telles que l'installeur les copie pour Claude Code
#   modules/<module>/               _bmad/<module>/ sans config.yaml (catalogue d'aide, shims…)
#   scripts/                        _bmad/scripts/ (résolution de la configuration, rendu, memlog)
#   bmad-help.csv, skill-manifest.csv   le catalogue d'aide et la table skill → module de l'union
#   templates/config.toml           _bmad/config.toml en modèle : un marqueur « #@module <m> » par bloc
#   templates/<module>.config.yaml  _bmad/<module>/config.yaml en modèle, sans sa ligne de date
#   LICENSES/                       la licence de bmad-method et de chaque module externe
#   SOURCE                          la provenance : version, épinglages, options de l'installeur
# L'installeur reçoit des valeurs sentinelles (nom du projet, langues, dossier de sortie, utilisatrice) :
# dans les modèles, elles deviennent des champs « @bmad.…@ » et « @user:…@ » que bin/install remplit ;
# partout ailleurs, une sentinelle trouvée est une valeur du projet qui a fui dans la méthode → 2.
#
# Réseau : npm (le paquet bmad-method) et GitHub (les modules externes, clonés à leur étiquette).
# HOME et le cache npm sont jetables : aucun cache du poste ne masque un épinglage.
#
# Codes de sortie : 0 bmad/method/ réécrit (git status dit s'il a changé) ; 2 installation impossible
# (outil absent, réseau, installeur en échec, version installée différente de la version déclarée,
# sortie incohérente). bmad/method/ n'est touché qu'après que tout a été vérifié.
# Procédure : procedures/bmad.md
set -euo pipefail

script_name=update
common=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../lib/bmad.sh
. "$common/lib/bmad.sh"
die() { printf '%s: %s\n' "$script_name" "$*" >&2; exit 2; }

(($# == 0)) || die "aucune option n'est admise. usage : bash bmad/update.sh"
for tool in npx node git awk sed grep find cp; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool introuvable : l'installeur BMAD demande node (20.12 ou plus), npx et git."
done

bmad_declared_load "$common/bmad/bmad.config" || exit 2

readonly s_project=bmad-sentinel-project s_user=bmad-sentinel-user \
  s_communication=bmad-sentinel-communication s_document=bmad-sentinel-document s_output=bmad-sentinel-output

tmp=$(mktemp -d) || die "dossier temporaire impossible."
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/npm-cache" "$tmp/$s_project" "$tmp/method"
project="$tmp/$s_project"
git -C "$project" init -q || die "dépôt jetable impossible."

modules_csv=${bmad_declared_modules// /,}
args=(install --yes --directory "$project" --modules "$modules_csv" --tools claude-code
  --user-name "$s_user" --communication-language "$s_communication"
  --document-output-language "$s_document" --output-folder "$s_output")
for module in $bmad_declared_modules; do
  bmad_is_builtin "$module" || args+=(--pin "$module=${bmad_declared_pins[$module]}")
done
if [[ $bmad_declared_shims == true ]]; then args+=(--shims); else args+=(--no-shims); fi

printf '%s: installeur bmad-method@%s, modules %s…\n' "$script_name" "$bmad_declared_version" "$bmad_declared_modules"
install_code=0
(
  cd "$project"
  HOME="$tmp/home" npm_config_cache="$tmp/npm-cache" npm_config_update_notifier=false \
    npm_config_fund=false npm_config_audit=false \
    npx --yes "bmad-method@$bmad_declared_version" "${args[@]}"
) > "$tmp/install.log" 2>&1 || install_code=$?
if ((install_code != 0)); then
  tail -n 20 "$tmp/install.log" >&2 || true
  die "l'installeur a échoué (code $install_code) : réseau, npm ou GitHub injoignable, ou épinglage introuvable. bmad/method/ est intact."
fi

bmad_dir="$project/_bmad"
manifest="$bmad_dir/_config/manifest.yaml"
[[ -f $manifest ]] || die "l'installeur n'a pas écrit $manifest : sortie incohérente."

# --- les versions installées sont celles déclarées ----------------------------------------------
# manifest.yaml : « installation: version: X », puis « - name: <m> » suivi de « version: <v> ».
installed=$(awk '
  /^installation:/ { section = "installation"; next }
  /^modules:/ { section = "modules"; next }
  /^[^ ]/ { section = "" }
  section == "installation" && $1 == "version:" { print "bmad " $2 }
  section == "modules" && $1 == "-" && $2 == "name:" { name = $3 }
  section == "modules" && $1 == "version:" && name != "" { print name " " $2; name = "" }
' "$manifest") || die "lecture de $manifest impossible."
declare -A installed_version=()
while read -r name version; do installed_version[$name]=$version; done <<< "$installed"
[[ ${installed_version[bmad]:-} == "$bmad_declared_version" ]] \
  || die "l'installeur a installé BMAD « ${installed_version[bmad]:-?} », « $bmad_declared_version » est déclaré."
for module in $bmad_declared_modules; do
  if bmad_is_builtin "$module"; then expected=$bmad_declared_version; else expected=${bmad_declared_pins[$module]}; fi
  [[ ${installed_version[$module]:-} == "$expected" ]] \
    || die "module $module installé en « ${installed_version[$module]:-absent} », « $expected » est déclaré."
done
for name in "${!installed_version[@]}"; do
  [[ $name == bmad || " $bmad_declared_modules " == *" $name "* ]] \
    || die "l'installeur a installé le module « $name », absent de bmad.modules."
done

# --- la méthode -----------------------------------------------------------------------------------
out="$tmp/method"
cp -R "$project/.claude/skills" "$out/skills" || die "copie des skills impossible."
cp -R "$bmad_dir/scripts" "$out/scripts" || die "copie des scripts impossible."
cp "$bmad_dir/_config/bmad-help.csv" "$bmad_dir/_config/skill-manifest.csv" "$out/" || die "copie des catalogues impossible."
mkdir -p "$out/modules" "$out/templates" "$out/LICENSES"
for module in $bmad_declared_modules; do
  [[ -f $bmad_dir/$module/config.yaml ]] || die "_bmad/$module/config.yaml absent : sortie incohérente."
  mkdir -p "$out/modules/$module"
  (cd "$bmad_dir/$module" && find . -mindepth 1 -maxdepth 1 ! -name config.yaml -exec cp -R {} "$out/modules/$module/" \;) \
    || die "copie du module $module impossible."
done

# skill → module : chaque dossier de skills a sa ligne, chaque ligne a son dossier, et son module est déclaré
bmad_skill_manifest_load "$out/skill-manifest.csv" || die "skill-manifest.csv de l'installeur illisible."
for skill_dir in "$out"/skills/*/; do
  skill=${skill_dir%/}
  skill=${skill##*/}
  [[ -n ${bmad_skill_module[$skill]:-} ]] || die "skill $skill sans ligne dans skill-manifest.csv."
done
for skill in "${!bmad_skill_module[@]}"; do
  [[ -d $out/skills/$skill ]] || die "skill-manifest.csv nomme $skill, absent des skills installées."
  [[ " $bmad_declared_modules " == *" ${bmad_skill_module[$skill]} "* ]] \
    || die "skill $skill d'un module non déclaré : ${bmad_skill_module[$skill]}."
done

# --- les modèles ----------------------------------------------------------------------------------
# config.toml : l'en-tête de l'installeur (« Installer-managed… ») tombe, chaque bloc reçoit son module.
awk -v out="$out/templates/config.toml" '
  function flush() { if (block != "") { if (module == "") { bad = 1 } else { printf "#@module %s\n%s", module, block > out } } block = ""; module = "" }
  /^\[/ {
    flush()
    started = 1
    if ($0 == "[core]") module = "core"
    else if (match($0, /^\[modules\.[a-z0-9-]+\]$/)) module = substr($0, 10, length($0) - 10)
    else if ($0 !~ /^\[agents\.[A-Za-z0-9_.-]+\]$/) bad = 1
  }
  !started { next }
  /^module = "[a-z0-9-]+"$/ && module == "" { module = substr($0, 11, length($0) - 11) }
  { block = block $0 "\n" }
  END { flush(); if (bad || !started) exit 1 }
' "$bmad_dir/config.toml" || die "_bmad/config.toml : un bloc sans module identifiable."

# Les clés de la couche utilisatrice : celles que l'installeur range dans config.user.toml.
user_keys=$(awk '
  /^\[/ { section = substr($0, 2, length($0) - 2); next }
  /^[a-z0-9_-]+ = / && section != "" { print section "." $1 }
' "$bmad_dir/config.user.toml") || die "lecture de config.user.toml impossible."
[[ -n $user_keys ]] || die "config.user.toml ne porte aucune clé : sortie incohérente."
grep -q "$s_user" "$bmad_dir/config.user.toml" || die "config.user.toml ne porte pas la sentinelle de l'utilisatrice."

for module in $bmad_declared_modules; do
  template="$out/templates/$module.config.yaml"
  # la ligne de date change à chaque installation : un modèle reproductible ne la garde pas
  grep -v '^# Date: ' "$bmad_dir/$module/config.yaml" > "$template" || die "modèle de $module impossible."
  while IFS= read -r user_key; do
    section=${user_key%.*}
    key=${user_key##*.}
    # une clé de [core] vaut pour chaque module ; une clé de [modules.<m>] pour <m> seul
    [[ $section == core || $section == "modules.$module" ]] || continue
    sed -i "s|^$key: .*\$|$key: @user:$section.$key@|" "$template" || die "modèle de $module impossible."
  done <<< "$user_keys"
done

for template in "$out"/templates/*; do
  sed -i -e "s|$s_project|@bmad.project-name@|g" -e "s|$s_document|@bmad.document-output-language@|g" \
    -e "s|$s_output|@bmad.output-folder@|g" "$template" || die "modèle $template impossible."
done
# Une sentinelle restante est une valeur que ce script ne sait pas mettre en champ ; une sentinelle
# hors des modèles est une valeur du projet qui a fui dans la méthode.
leak_code=0
leaks=$(grep -rl 'bmad-sentinel' "$out") || leak_code=$?
((leak_code <= 1)) || die "recherche des sentinelles impossible (grep, code $leak_code)."
[[ -z $leaks ]] || die "valeur sentinelle restée dans : ${leaks//$'\n'/, }"


# --- licences et provenance ---------------------------------------------------------------------
# des globs plutôt que « find -quit », que le find de BusyBox (runner de la forge) ne connaît pas
shopt -s nullglob
licenses=("$tmp"/npm-cache/_npx/*/node_modules/bmad-method/LICENSE)
((${#licenses[@]} == 1)) || die "licence de bmad-method : ${#licenses[@]} trouvée(s) dans le cache npm, une attendue."
cp "${licenses[0]}" "$out/LICENSES/bmad-method.txt"
for module in $bmad_declared_modules; do
  bmad_is_builtin "$module" && continue
  licenses=("$tmp/home/.bmad/cache/external-modules/$module"/[Ll][Ii][Cc][Ee][Nn][Ss][Ee]*)
  ((${#licenses[@]} == 1)) || die "licence du module $module : ${#licenses[@]} trouvée(s) dans son dépôt, une attendue."
  cp "${licenses[0]}" "$out/LICENSES/$module.txt"
done
shopt -u nullglob
{
  printf '# Généré par bmad/update.sh — ne pas éditer : relancer le script (procedures/bmad.md).\n'
  printf 'bmad-method %s\n' "$bmad_declared_version"
  for module in $bmad_declared_modules; do
    bmad_is_builtin "$module" && continue
    printf '%s %s\n' "$module" "${bmad_declared_pins[$module]}"
  done
  printf 'installeur : npx bmad-method@%s install --tools claude-code --modules %s, shims %s\n' \
    "$bmad_declared_version" "$modules_csv" "$bmad_declared_shims"
} > "$out/SOURCE"

# --- remplacement, une fois tout vérifié ---------------------------------------------------------
rm -rf "$common/bmad/method"
cp -R "$out" "$common/bmad/method" || die "écriture de bmad/method impossible."
changes=$(git -C "$common" status --porcelain -- bmad/method) || die "git status impossible."
if [[ -z $changes ]]; then
  printf '%s: bmad/method réécrit, identique à la version suivie par git.\n' "$script_name"
else
  printf '%s: bmad/method réécrit ; %s chemin(s) diffèrent de la version suivie par git (git status -- bmad/method).\n' \
    "$script_name" "$(wc -l <<< "$changes")"
fi
