#!/usr/bin/env bash
# Test de réinstallation de BMAD (story 1, décision 9 du 30/09/2026) : une réinstallation dans le
# dépôt commun ne touche AUCUN fichier des couches projet, et ne salit pas le sous-module.
#
#   bash ci/bmad-reinstall.sh [--reinstall <commande>]
#
# Déroulé, sur un projet fixture (tests/fixtures/bmad-projet) qui porte les couches projet :
#   1. une copie jetable du dépôt commun (fichiers suivis, tels qu'ils sont sur le disque) devient le
#      sous-module du projet fixture ; bin/install y est lancé, et le projet commité ;
#   2. le sous-module est propre (git status vide) : bin/install n'écrit pas à travers ses liens ;
#   3. empreinte de workflow.config, _bmad/config.user.toml, _bmad/custom/ et _bmad-output/ ;
#   4. RÉINSTALLATION de BMAD dans le sous-module : par défaut « bash bmad/update.sh », qui rejoue
#      l'installeur épinglé (réseau) ; --reinstall la remplace par « <commande> <sous-module> <projet> »,
#      pour les cas de test qui injectent une régénération fautive (tests/test-bmad-reinstall.sh) ;
#   5. le sous-module est toujours propre : l'installeur reproduit exactement bmad/method/ ;
#   6. bin/install relancé ; le sous-module reste propre, l'empreinte n'a pas bougé, le projet n'a
#      rien à commiter, et sa configuration BMAD (config.toml, chaque config.yaml, catalogue d'aide)
#      est octet pour octet celle qu'une installation neuve génère depuis le même workflow.config.
#
# Codes de sortie : 0 tout est prouvé ; 1 une preuve échoue (le fichier est nommé) ; 2 test
# impossible (réinstallation en échec — réseau compris —, fixture ou copie impossible). Jamais 0 sur
# une étape qui n'a pas pu conclure.
# Procédure : procedures/bmad.md
set -euo pipefail

script_name=bmad-reinstall
common=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
die() { printf '%s: %s\n' "$script_name" "$*" >&2; exit 2; }
fail() { printf '%s: ÉCHEC : %s\n' "$script_name" "$1" >&2; shift; (($# == 0)) || printf '  - %s\n' "$@" >&2; exit 1; }
step() { printf '%s: %s\n' "$script_name" "$*"; }

reinstall=""
while (($#)); do
  case $1 in
    --reinstall) (($# >= 2)) && [[ -z $reinstall && -n $2 ]] || die "usage : bash ci/bmad-reinstall.sh [--reinstall <commande>]"; reinstall=$2; shift 2 ;;
    *) die "option inconnue : $1. usage : bash ci/bmad-reinstall.sh [--reinstall <commande>]" ;;
  esac
done

fixture="$common/tests/fixtures/bmad-projet"
[[ -f $fixture/workflow.config ]] || die "projet fixture introuvable : $fixture."
tmp=$(mktemp -d) || die "dossier temporaire impossible."
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
gitq() { git -c user.name=essai -c user.email=essai@example.invalid -c core.hooksPath=/dev/null -c commit.gpgsign=false "$@"; }

# --- 1. le dépôt commun jetable : les fichiers suivis, tels qu'ils sont sur le disque ----------------
step "copie du dépôt commun…"
mkdir -p "$tmp/commun"
git -C "$common" ls-files -z > "$tmp/suivis" || die "liste des fichiers suivis illisible."
while IFS= read -r -d '' path; do
  [[ -e $common/$path || -L $common/$path ]] || die "fichier suivi absent du disque : $path."
  mkdir -p "$tmp/commun/$(dirname "$path")"
  cp -P "$common/$path" "$tmp/commun/$path" || die "copie impossible : $path."
done < "$tmp/suivis"
if ! { git -C "$tmp/commun" init -q && gitq -C "$tmp/commun" add -A && gitq -C "$tmp/commun" commit -q -m commun; }; then
  die "dépôt commun jetable impossible."
fi

# Un projet fixture, le dépôt commun en sous-module sous outils/commun, commité.
new_project() { # $1 = dossier
  mkdir -p "$1"
  cp -R "$fixture/." "$1/" || die "copie du projet fixture impossible."
  # « gitignore » dans le dépôt commun, pour qu'il n'y ignore pas les fichiers de la fixture
  mv "$1/gitignore" "$1/.gitignore" || die "gitignore du projet fixture absent."
  git -C "$1" init -q || die "dépôt du projet impossible."
  gitq -C "$1" -c protocol.file.allow=always submodule add -q "$tmp/commun" outils/commun >/dev/null 2>&1 \
    || die "sous-module impossible à ajouter."
}
install_in() { # $1 = projet ; sortie dans $tmp/install.log
  local code=0
  (cd "$1" && sh outils/commun/bin/install) > "$tmp/install.log" 2>&1 || code=$?
  ((code == 0)) || { cat "$tmp/install.log" >&2; fail "bin/install a rendu $code dans $1."; }
}
clean_submodule() { # $1 = projet, $2 = moment
  local changes
  changes=$(git -C "$1/outils/commun" status --porcelain --ignored) || die "git status du sous-module impossible."
  [[ -z $changes ]] || fail "le sous-module n'est plus propre $2 :" "${changes//$'\n'/$'\n'  - }"
}
fingerprint() { # $1 = projet, $2 = fichier de sortie
  ( cd "$1"
    find workflow.config _bmad/config.user.toml _bmad/custom _bmad-output \( -type f -o -type l \) -print \
      | LC_ALL=C sort | while IFS= read -r path; do printf '%s %s\n' "$(git hash-object -- "$path")" "$path"; done
  ) > "$2" || die "empreinte des couches projet impossible."
  [[ -s $2 ]] || die "empreinte vide : le projet fixture ne porte pas ses couches projet."
}

project="$tmp/projet"
new_project "$project"
step "installation dans le projet fixture…"
install_in "$project"
if ! { gitq -C "$project" add -A && gitq -C "$project" commit -q -m "projet installé"; }; then
  die "commit du projet impossible."
fi

# --- 2 et 3. sous-module propre, empreinte -------------------------------------------------------
clean_submodule "$project" "après bin/install (AC 5)"
fingerprint "$project" "$tmp/avant"

# --- 4. la réinstallation ------------------------------------------------------------------------
submodule="$project/outils/commun"
code=0
if [[ -z $reinstall ]]; then
  step "réinstallation de BMAD dans le dépôt commun (bmad/update.sh, réseau)…"
  (cd "$submodule" && bash bmad/update.sh) || code=$?
else
  step "réinstallation remplacée par : $reinstall"
  bash -c "$reinstall \"\$1\" \"\$2\"" _ "$submodule" "$project" || code=$?
fi
((code == 0)) || die "la réinstallation a rendu $code : rien n'est prouvé (réseau, npm ou GitHub compris)."

# --- 5 et 6. ce qui ne doit pas avoir bougé ------------------------------------------------------
clean_submodule "$project" "après la réinstallation : l'installeur ne reproduit pas bmad/method/"
step "bin/install relancé…"
install_in "$project"
clean_submodule "$project" "après bin/install relancé"
fingerprint "$project" "$tmp/apres"
if ! cmp -s "$tmp/avant" "$tmp/apres"; then
  # comparaison par chemin, sans « diff » : celui de BusyBox (runner de la forge) n'écrit que le
  # format unifié, et une lecture du format normal y trouverait zéro chemin
  declare -A before=() after=()
  while read -r hash path; do before[$path]=$hash; done < "$tmp/avant"
  while read -r hash path; do after[$path]=$hash; done < "$tmp/apres"
  changed=()
  for path in "${!before[@]}"; do
    if [[ -z ${after[$path]+x} ]]; then
      changed+=("$path (supprimé)")
    elif [[ ${after[$path]} != "${before[$path]}" ]]; then
      changed+=("$path (modifié)")
    fi
  done
  for path in "${!after[@]}"; do
    [[ -n ${before[$path]+x} ]] || changed+=("$path (ajouté)")
  done
  ((${#changed[@]})) || die "empreintes différentes sans chemin différent : comparaison incohérente."
  fail "la réinstallation a modifié des fichiers des couches projet :" "${changed[@]}"
fi
changes=$(git -C "$project" status --porcelain) || die "git status du projet impossible."
[[ -z $changes ]] || fail "le projet a des changements à commiter après la réinstallation :" "${changes//$'\n'/$'\n'  - }"

step "comparaison avec une installation neuve…"
fresh="$tmp/neuf"
new_project "$fresh"
install_in "$fresh"
generated=(_bmad/config.toml _bmad/_config/bmad-help.csv)
for file in "$fresh"/_bmad/*/config.yaml "$project"/_bmad/*/config.yaml; do
  [[ -e $file ]] || continue
  path=${file#"$fresh"/}
  path=${path#"$project"/}
  [[ " ${generated[*]} " == *" $path "* ]] || generated+=("$path")
done
compared=0 differ=()
for path in "${generated[@]}"; do
  [[ -f $fresh/$path ]] || { differ+=("$path : absent de l'installation neuve"); continue; }
  [[ -f $project/$path ]] || { differ+=("$path : absent du projet réinstallé"); continue; }
  compared=$((compared + 1))
  cmp -s "$project/$path" "$fresh/$path" || differ+=("$path")
done
((${#differ[@]} == 0)) || fail "configuration BMAD différente de ce que workflow.config génère :" "${differ[@]}"
# config.toml, le catalogue d'aide et au moins un config.yaml : sinon, rien n'a été comparé
((compared >= 3)) || fail "configuration générée introuvable ($compared fichier(s) comparé(s))."

step "prouvé : sous-module propre, $(wc -l < "$tmp/avant") fichier(s) des couches projet intacts, $compared fichier(s) de configuration identiques à la génération."
