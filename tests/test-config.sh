#!/usr/bin/env bash
# Lecteur de workflow.config (lib/config.sh). Chaque refus est éprouvé sur l'entrée qu'il doit
# refuser, et chaque comportement de git config que le lecteur suppose est rejoué ici plutôt que cru.
# Chaque garde a été lancée une fois retirée, pour voir son cas échouer (story outillage-14, phase B).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=../lib/config.sh
. "$common/lib/config.sh"

# Charge $work/projet/workflow.config ; rc, out, err comme run.
load() { run config_load "$work/projet/workflow.config"; }

# Écrit un fichier à la main, pour les formes que git config n'écrirait pas lui-même.
raw_config() { # $1 = texte ajouté après un fichier complet valide
  write_workflow_config "$work/projet"
  printf '%s\n' "$1" >> "$work/projet/workflow.config"
}

case_config_valide_est_lu() {
  write_workflow_config "$work/projet"
  load
  assert_eq 0 "$rc" "un fichier complet est accepté (messages : $err)"
  config_load "$work/projet/workflow.config"
  local repo prefixes
  config_get repo forge.repo
  assert_eq Proprietaire/projet-essai "$repo" "la valeur est rendue telle quelle, casse comprise"
  config_get prefixes forge.branch-prefixes
  assert_eq "feat fix chore docs" "$prefixes" "une liste garde ses espaces"
}

case_config_fichier_absent() {
  run config_load "$work/absent/workflow.config"
  assert_eq 2 "$rc" "un fichier absent sort en 2"
  assert_contains "absent ou illisible" "$err" "le message dit pourquoi"
}

case_config_fichier_vide_refuse_tous_les_champs() {
  mkdir -p "$work/projet"
  : > "$work/projet/workflow.config"
  load
  assert_eq 2 "$rc" "un fichier vide n'est pas une configuration par défaut"
  assert_contains "forge.repo : champ absent" "$err" "chaque champ manquant est nommé"
  assert_contains "workflow.schema : champ absent" "$err" "y compris la version du schéma"
}

case_config_syntaxe_refusee_sans_sortie_partielle() {
  # git écrit les clés qui précèdent une erreur de syntaxe, puis sort en 128 : rien n'en est gardé.
  write_workflow_config "$work/projet"
  printf '[review]\n\texempt-paths = \\.md$\n' >> "$work/projet/workflow.config"
  local partial=0
  git config -f "$work/projet/workflow.config" --list > "$work/partielle" 2>/dev/null || partial=$?
  assert_eq 128 "$partial" "constat : git refuse la syntaxe en 128"
  [[ -s $work/partielle ]] || { echo "constat attendu : git écrit une sortie partielle avant l'erreur" >&2; exit 1; }
  load
  assert_eq 2 "$rc" "une erreur de syntaxe sort en 2"
  assert_contains "syntaxe refusée par git config (code 128)" "$err" "le message nomme git et son code"
  run config_get valeur forge.repo
  assert_eq 2 "$rc" "rien de la sortie partielle n'est gardé"
}

case_config_doublon_refuse() {
  # git config --get rendrait la dernière valeur, en silence.
  raw_config $'[forge]\n\trepo = Autre/depot'
  local last
  last=$(git config -f "$work/projet/workflow.config" --get forge.repo || true)
  assert_eq Autre/depot "$last" "constat : --get rend la dernière valeur sans rien dire"
  load
  assert_eq 2 "$rc" "un champ écrit deux fois sort en 2"
  assert_contains "forge.repo : écrit 2 fois" "$err" "le message nomme le champ et le compte"
}

case_config_doublon_dans_deux_sections_homonymes() {
  raw_config $'[FORGE]\n\tRepo = Autre/depot'
  load
  assert_eq 2 "$rc" "la casse des noms ne cache pas un doublon"
  assert_contains "forge.repo : écrit 2 fois" "$err" "git rend les noms en minuscules"
}

case_config_champ_absent() {
  write_workflow_config "$work/projet" -review.timeout
  load
  assert_eq 2 "$rc" "un champ absent sort en 2"
  assert_contains "review.timeout : champ absent" "$err" "le champ est nommé"
}

case_config_champ_inconnu() {
  write_workflow_config "$work/projet" review.delai=900
  load
  assert_eq 2 "$rc" "une clé hors schéma dans une section connue sort en 2"
  assert_contains "review.delai : champ inconnu" "$err" "la clé est nommée"
}

case_config_section_inconnue() {
  write_workflow_config "$work/projet" divers.option=1
  load
  assert_eq 2 "$rc" "une section hors schéma sort en 2"
  assert_contains "divers.option : champ inconnu" "$err" "la section est nommée"
}

case_config_sous_section_refusee() {
  raw_config $'[forge "secours"]\n\trepo = Autre/depot'
  load
  assert_eq 2 "$rc" "une sous-section n'est pas au schéma"
  assert_contains "forge.secours.repo : champ inconnu" "$err" "la sous-section est nommée"
}

case_config_include_ni_suivi_ni_admis() {
  # Le fichier inclus porterait le champ manquant : s'il était suivi, le fichier passerait.
  write_workflow_config "$work/projet" -review.timeout
  printf '[review]\n\ttimeout = 900\n' > "$work/projet/inclus.config"
  printf '[include]\n\tpath = inclus.config\n' >> "$work/projet/workflow.config"
  load
  assert_eq 2 "$rc" "un include sort en 2"
  assert_contains "include.path : champ inconnu" "$err" "l'include est nommé comme section inconnue"
  assert_contains "review.timeout : champ absent" "$err" "le fichier inclus n'a pas été lu"
}

case_config_cle_sans_egal() {
  # « timeout » seul vaut « vrai » pour git : ce n'est pas une valeur.
  write_workflow_config "$work/projet" -review.timeout
  printf '[review]\n\ttimeout\n' >> "$work/projet/workflow.config"
  load
  assert_eq 2 "$rc" "une clé sans « = » sort en 2"
  assert_contains "review.timeout : écrit sans « = »" "$err" "le message dit ce qui manque"
}

case_config_valeur_vide() {
  write_workflow_config "$work/projet" -review.timeout
  printf '[review]\n\ttimeout =\n' >> "$work/projet/workflow.config"
  load
  assert_eq 2 "$rc" "une valeur vide sort en 2"
  assert_contains "review.timeout : valeur vide" "$err" "le champ est nommé"
}

case_config_none_sur_champ_non_desactivable() {
  write_workflow_config "$work/projet" forge.repo=none
  load
  assert_eq 2 "$rc" "none n'est pas une valeur de forge.repo"
  assert_contains "forge.repo : « none » refusé" "$err" "le message le dit"
}

case_config_none_desactive_et_se_lit() {
  write_workflow_config "$work/projet" review.exempt-paths=none checks.dir=none
  load
  assert_eq 0 "$rc" "none est admis sur un champ désactivable (messages : $err)"
  config_load "$work/projet/workflow.config"
  run config_enabled review.exempt-paths
  assert_eq 1 "$rc" "le champ se lit désactivé"
  run config_enabled forge.repo
  assert_eq 0 "$rc" "un champ renseigné se lit actif"
}

case_config_types_invalides() {
  local change
  for change in workflow.schema=2 forge.repo=sans-barre "forge.base=a..b" "forge.base=-dev" \
    "forge.branch-prefixes=feat/ fix" "forge.env-file=/etc/env" "forge.env-file=../.env" \
    "forge.env-file=a/./b" "sprint.convention=libre" review.report=courriel review.timeout=15m \
    review.timeout=0 "review.exempt-paths=(" ci.bootstrap=yes bmad.version=6.12 \
    "review.private-paths=.env  docs" "review.reviewer-for-claude=Gemini Pro" "ci.status-context= checks"; do
    write_workflow_config "$work/projet" "$change"
    load
    assert_eq 2 "$rc" "type invalide refusé : $change"
    assert_contains "${change%%=*} :" "$err" "le champ est nommé : $change"
  done
}

case_config_types_valides() {
  local change
  for change in "ci.status-context=CI Tests & Quality" "review.exempt-paths=[.]md$" \
    "checks.command=make test-ci" forge.release-branch=master "forge.branch-prefixes=feat fix refactor"; do
    write_workflow_config "$work/projet" "$change"
    load
    assert_eq 0 "$rc" "valeur admise : $change (messages : $err)"
  done
}

case_config_valeur_citee_et_commentaire() {
  raw_config ''
  git config -f "$work/projet/workflow.config" --unset ci.status-context
  printf '[ci]\n\tstatus-context = "a # b" ; commentaire\n' >> "$work/projet/workflow.config"
  config_load "$work/projet/workflow.config"
  local context
  config_get context ci.status-context
  assert_eq "a # b" "$context" "une valeur citée garde son « # », le commentaire est retiré"
}

case_config_variables_git_sans_effet() {
  # GIT_CONFIG_COUNT et GIT_CONFIG_PARAMETERS injectent des clés dans la configuration de git :
  # avec « -f », elles n'entrent pas dans la lecture du fichier.
  write_workflow_config "$work/projet" -review.timeout
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=review.timeout GIT_CONFIG_VALUE_0=900 \
    GIT_CONFIG_PARAMETERS="'review.timeout'='900'" \
    bash -c '. "$1/lib/config.sh"; config_load "$2"' _ "$common" "$work/projet/workflow.config"
  assert_eq 2 "$rc" "un champ absent du fichier reste absent"
  write_workflow_config "$work/projet"
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=forge.repo GIT_CONFIG_VALUE_0=Autre/depot \
    bash -c '. "$1/lib/config.sh"; config_load "$2" && config_get v forge.repo && echo "$v"' _ "$common" "$work/projet/workflow.config"
  assert_eq Proprietaire/projet-essai "$out" "une valeur du fichier n'est pas remplacée"
}

case_config_regles_entre_champs() {
  write_workflow_config "$work/projet" sprint.convention=none
  load
  assert_eq 2 "$rc" "un suivi désactivé exige des chemins désactivés"
  assert_contains "sprint.status-file : doit valoir « none »" "$err" "le champ fautif est nommé"
  write_workflow_config "$work/projet" sprint.status-file=none
  load
  assert_eq 2 "$rc" "un suivi actif exige ses chemins"
  write_workflow_config "$work/projet" guard.patterns-file=none
  load
  assert_eq 2 "$rc" "un garde-fou sans motif ne garde rien"
  write_workflow_config "$work/projet" ci.workflow=none
  load
  assert_eq 2 "$rc" "un workflow désactivé exige un contexte désactivé"
  write_workflow_config "$work/projet" forge.release-branch=dev
  load
  assert_eq 2 "$rc" "la branche de publication n'est pas la base"
  write_workflow_config "$work/projet" sprint.convention=none sprint.status-file=none \
    sprint.stories-dir=none sprint.spec-source=none guard.command=none guard.patterns-file=none \
    ci.workflow=none ci.status-context=none forge.release-branch=none
  load
  assert_eq 0 "$rc" "tout désactivé ensemble est cohérent (messages : $err)"
}

case_config_get_hors_schema_et_avant_chargement() {
  run config_get valeur forge.repo
  assert_eq 2 "$rc" "rien n'est lu avant un chargement réussi"
  write_workflow_config "$work/projet"
  config_load "$work/projet/workflow.config"
  run config_get valeur forge.inconnu
  assert_eq 2 "$rc" "un champ hors schéma est une erreur de programmation"
}

case_config_un_refus_efface_le_chargement_precedent() {
  write_workflow_config "$work/projet"
  config_load "$work/projet/workflow.config"
  write_workflow_config "$work/projet" -forge.repo
  config_load "$work/projet/workflow.config" 2>/dev/null || true
  run config_get valeur forge.base
  assert_eq 2 "$rc" "les valeurs d'un fichier valide lu avant ne survivent pas à un refus"
}

case_config_exemple_et_configuration_du_depot_valides() {
  run config_load "$common/workflow.config.example"
  assert_eq 0 "$rc" "workflow.config.example est valide (messages : $err)"
  run config_load "$common/workflow.config"
  assert_eq 0 "$rc" "le workflow.config du dépôt commun est valide (messages : $err)"
}

case_config_chaque_champ_est_documente() {
  local field missing="" doc example
  doc=$(cat "$common/procedures/workflow-config.md")
  example=$(cat "$common/workflow.config.example")
  while IFS= read -r field; do
    [[ $doc == *"\`$field\`"* ]] || missing+=" doc:$field"
    # l'exemple écrit chaque champ sous sa section : la clé seule suffit à le retrouver
    [[ $example == *"${field#*.} = "* ]] || missing+=" exemple:$field"
  done < <(config_fields)
  assert_eq "" "$missing" "chaque champ du schéma est dans la procédure et dans l'exemple"
}

case_config_racine_du_projet() {
  # Le dépôt commun, consommé en sous-module : lancé depuis le sous-module, l'outil agit sur le projet.
  mkdir -p "$work/commun/lib"
  cp "$common/lib/config.sh" "$work/commun/lib/"
  git -C "$work/commun" init -q
  git -C "$work/commun" -c user.name=essai -c user.email=essai@example.invalid add -A
  git -C "$work/commun" -c user.name=essai -c user.email=essai@example.invalid -c core.hooksPath=/dev/null commit -q -m commun
  new_repo
  git -C "$work/depot" -c protocol.file.allow=always submodule add -q "$work/commun" outillage 2>/dev/null
  local expected
  expected=$(cd "$work/depot" && pwd -P)
  run bash -c 'cd "$1/outillage" && . lib/config.sh && config_project_root r && echo "$r"' _ "$work/depot"
  assert_eq "$expected" "$out" "depuis le sous-module, la racine est le projet (messages : $err)"
  run bash -c 'cd "$1" && . outillage/lib/config.sh && config_project_root r && echo "$r"' _ "$work/depot"
  assert_eq "$expected" "$out" "depuis le projet, la racine est le projet"
  run bash -c 'cd "$1" && . lib/config.sh && config_project_root r && echo "$r"' _ "$work/commun"
  assert_eq "$(cd "$work/commun" && pwd -P)" "$out" "le dépôt commun seul est sa propre racine"
  mkdir -p "$work/hors"
  run bash -c 'cd "$1" && . "$2/lib/config.sh" && config_project_root r' _ "$work/hors" "$common"
  assert_eq 2 "$rc" "hors d'un dépôt git, la racine est introuvable"
}

run_case "$@"
