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
  for change in workflow.schema=6 forge.repo=sans-barre "forge.base=a..b" "forge.base=-dev" \
    "forge.branch-prefixes=feat/ fix" "forge.env-file=/etc/env" "forge.env-file=../.env" \
    "forge.env-file=a/./b" "sprint.convention=libre" review.report=courriel review.report=file review.timeout=15m \
    review.timeout=0 "review.exempt-paths=(" ci.bootstrap=yes bmad.version=6.12 \
    "review.private-paths=.env  docs" "review.reviewers=claude=Gemini Pro" "ci.status-context= checks" \
    "bmad.project-name=a: b" "bmad.project-name=x\"y" "bmad.document-output-language=[fr]" \
    "bmad.project-name=a#b" "bmad.output-folder=../sortie" "bmad.modules=core bmm core" \
    "agents.skill-dirs=.claude/skills .agents/skills .claude/skills" "forge.branch-prefixes=feat fix feat"; do
    write_workflow_config "$work/projet" "$change"
    load
    assert_eq 2 "$rc" "type invalide refusé : $change"
    assert_contains "${change%%=*} :" "$err" "le champ est nommé : $change"
  done
}

case_config_types_valides() {
  local change
  for change in "bmad.project-name=site.example" "bmad.document-output-language=Français" \
    "bmad.project-name=Outil de calcul" "ci.status-context=CI Tests & Quality" "review.exempt-paths=[.]md$" \
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

case_config_schemas_1_et_2_refuses_avec_la_nouvelle_forme() {
  # « Changer de schéma » (procedures/workflow-config.md) : les schémas 1 et 2 portent les deux
  # relecteurs nommés, que plus aucun outil ne lit ; les lire, ce serait les ignorer en silence.
  write_workflow_config "$work/projet" workflow.schema=2 -review.reviewers \
    review.reviewer-for-claude=gemini-3.1-pro-high review.reviewer-for-gemini=claude-opus-4-6-thinking
  load
  assert_eq 2 "$rc" "un fichier au schéma 2, complet pour ce schéma, est refusé"
  assert_contains "workflow.schema : schéma 2 retiré : le schéma 3 est attendu" "$err" "le schéma attendu est nommé"
  assert_contains "remplacés par la table review.reviewers" "$err" "et la nouvelle forme"
  assert_contains "review.reviewer-for-claude : retiré au schéma 3 : la table review.reviewers le remplace" "$err" "chaque ancienne clé est nommée"
  assert_contains "review.reviewer-for-gemini : retiré au schéma 3" "$err" "les deux"
  run config_get valeur forge.repo
  assert_eq 2 "$rc" "rien n'est lu d'un fichier refusé"
  write_workflow_config "$work/projet" workflow.schema=1 -bmad.project-name -bmad.document-output-language \
    -bmad.output-folder -review.reviewers review.reviewer-for-claude=gemini-3.1-pro-high \
    review.reviewer-for-gemini=claude-opus-4-6-thinking
  load
  assert_eq 2 "$rc" "un fichier au schéma 1 est refusé"
  assert_contains "schéma 1 retiré : le schéma 3 est attendu" "$err" "le schéma attendu est nommé"
  assert_contains "bmad.output-folder s'ajoutent" "$err" "avec les champs à ajouter depuis le schéma 1"
}

case_config_anciennes_cles_refusees_au_schema_3() {
  # présentes à côté de la table, elles seraient ignorées en silence : refusées, avec la nouvelle forme
  local cle
  for cle in review.reviewer-for-claude review.reviewer-for-gemini; do
    write_workflow_config "$work/projet" "$cle=gemini-3.1-pro-high"
    load
    assert_eq 2 "$rc" "$cle refusée au schéma 3"
    assert_contains "$cle : retiré au schéma 3 : la table review.reviewers le remplace" "$err" "le message nomme la nouvelle forme"
    assert_contains "reviewers = claude=" "$err" "et en donne un exemple"
  done
}

case_config_reviewers_table_ouverte() {
  # un fournisseur s'ajoute par une entrée, jamais par du code
  local valeur
  for valeur in "claude=gemini-3.1-pro-high" \
    "claude=gemini-3.1-pro-high gemini=claude-opus-4-6-thinking gpt=claude-opus-5-5-high" \
    "mistral=gemini-3.1-pro-high claude=gpt-oss-120b-medium"; do
    write_workflow_config "$work/projet" "review.reviewers=$valeur"
    load
    assert_eq 0 "$rc" "table admise : $valeur (messages : $err)"
  done
  config_load "$work/projet/workflow.config"
  config_get valeur review.reviewers
  assert_eq "mistral=gemini-3.1-pro-high claude=gpt-oss-120b-medium" "$valeur" "la table est rendue telle quelle"
}

case_config_reviewers_meme_fournisseur_refuse() {
  local valeur
  for valeur in "claude=claude-opus-5-5-high" "claude=gemini-3.1-pro-high gemini=gemini-3.8-flash-high" \
    "gpt=gpt-oss-120b-medium"; do
    write_workflow_config "$work/projet" "review.reviewers=$valeur"
    load
    assert_eq 2 "$rc" "relecteur du même fournisseur refusé : $valeur"
    assert_contains "le relecteur est du même fournisseur que l'auteur" "$err" "la règle est nommée : $valeur"
  done
}

case_config_reviewers_formes_invalides() {
  local valeur
  for valeur in "claude:gemini-3.1-pro-high" "claude=" "=gemini-3.1-pro-high" "Claude=gemini-3.1-pro-high" \
    "claude=Gemini-3" "claude=gemini-3.1-pro-high  gemini=claude-opus-4-6-thinking" \
    "claude=gemini-3.1-pro-high claude=gpt-oss-120b-medium" "claude=gemini=x" "2claude=gemini-x"; do
    write_workflow_config "$work/projet" "review.reviewers=$valeur"
    load
    assert_eq 2 "$rc" "forme refusée : $valeur"
    assert_contains "review.reviewers :" "$err" "le champ est nommé : $valeur"
  done
}

case_config_champ_du_schema_2_dans_un_fichier_au_schema_1() {
  write_workflow_config "$work/projet" workflow.schema=1 -bmad.document-output-language -bmad.output-folder
  load
  assert_eq 2 "$rc" "un champ du schéma 2 est inconnu du schéma 1"
  assert_contains "bmad.project-name : champ du schéma 2, inconnu du schéma 1" "$err" "le champ et les schémas sont nommés"
}

case_config_schema_3_exige_ses_champs() {
  local champ
  for champ in bmad.project-name bmad.document-output-language bmad.output-folder review.reviewers; do
    write_workflow_config "$work/projet" "-$champ"
    load
    assert_eq 2 "$rc" "$champ est requis au schéma 3"
    assert_contains "$champ : champ absent" "$err" "le champ est nommé"
  done
}

case_config_doublon_nomme() {
  write_workflow_config "$work/projet" "bmad.modules=core bmm core"
  load
  assert_eq 2 "$rc" "un module écrit deux fois est refusé"
  assert_contains "bmad.modules : « core » écrit deux fois dans la liste" "$err" "le champ et le mot fautif sont nommés"
}

# --- surcharges des modules BMAD : « [module "<nom>"] <clé> = <valeur> », optionnelles ------------

case_config_surcharges_de_module_admises() {
  write_workflow_config "$work/projet" "bmad.modules=core bmm tea" module.tea.test-framework=playwright \
    module.tea.tea-pact-mcp=none "module.tea.test-artifacts={project-root}/_bmad-output/test-artifacts" \
    module.tea.tea-use-playwright-utils=false module.bmm.project-knowledge=documentation
  load
  assert_eq 0 "$rc" "des surcharges de clés littérales des modèles sont admises (messages : $err)"
  config_load "$work/projet/workflow.config"
  run config_module_overrides tea
  assert_eq $'tea_pact_mcp\tnone\ntea_use_playwright_utils\tfalse\ntest_artifacts\t{project-root}/_bmad-output/test-artifacts\ntest_framework\tplaywright' \
    "$out" "chaque surcharge est rendue sous le nom de clé du modèle"
  run config_module_overrides cis
  assert_eq "" "$out" "un module sans surcharge n'en rend aucune"
}

case_config_surcharges_absentes_ne_changent_rien() {
  # optionnelles : un fichier sans elles reste valide, au même schéma
  write_workflow_config "$work/projet" "bmad.modules=core bmm tea"
  load
  assert_eq 0 "$rc" "sans surcharge, le fichier est valide (messages : $err)"
  config_load "$work/projet/workflow.config"
  run config_module_overrides tea
  assert_eq "" "$out" "aucune surcharge"
}

case_config_surcharge_cle_inconnue_refusee() {
  write_workflow_config "$work/projet" "bmad.modules=core bmm tea" module.tea.inconnue=x
  load
  assert_eq 2 "$rc" "une clé absente du modèle est refusée"
  assert_contains "module.tea.inconnue : clé inconnue du modèle de tea (clés surchargeables :" "$err" "le message nomme le module"
  assert_contains "test-framework" "$err" "et liste les clés admises"
}

case_config_surcharge_refusee_hors_des_cas_admis() {
  local change
  for change in module.tea.test-framework=playwright "module.wds.x=y" module.bmm.planning-artifacts=ailleurs \
    module.core.user-name=Autre module.tea.tea-use-playwright-utils=yes "module.tea.test-framework=a\"b" \
    module.tea.test-framework=a@b "module.tea.test-framework= espace" module.tea.test-framework=; do
    write_workflow_config "$work/projet" "$change"
    [[ $change == module.tea.test-framework=playwright || $change == module.wds.x=y ]] \
      || git config -f "$work/projet/workflow.config" bmad.modules "core bmm tea"
    load
    assert_eq 2 "$rc" "surcharge refusée : $change"
    assert_contains "${change%%=*} :" "$err" "la clé est nommée : $change"
  done
  write_workflow_config "$work/projet" module.tea.test-framework=playwright
  load
  assert_contains "module « tea » absent de bmad.modules" "$err" "module non activé : la raison est dite"
  write_workflow_config "$work/projet" module.bmm.planning-artifacts=ailleurs
  load
  assert_contains "valeur dérivée d'un champ" "$err" "valeur dérivée : la raison est dite"
}

case_config_surcharge_module_sans_modele_refusee() {
  # un module déclaré mais sans modèle dans le dépôt commun : la raison est dite, pas « clé inconnue »
  write_workflow_config "$work/projet" "bmad.modules=core bmm wds" module.wds.x=y
  load
  assert_eq 2 "$rc" "surcharge d'un module sans modèle refusée"
  assert_contains "module.wds.x : module « wds » sans modèle de configuration dans le dépôt commun" "$err" "la raison est dite"
}

case_config_surcharge_valeurs_mal_formees_refusees() {
  # chaque garde de la valeur, sur l'entrée qu'elle doit refuser (constat de la revue 1 de la PR n° 8)
  local valeur
  for valeur in $'a\tb' $'a\x01b' "fin " " tete" 'a\b' 'a`b' 'a"b' 'a@b'; do
    write_workflow_config "$work/projet" "bmad.modules=core bmm tea" "module.tea.test-framework=$valeur"
    load
    assert_eq 2 "$rc" "valeur refusée : $(printf %q "$valeur")"
    assert_contains "module.tea.test-framework :" "$err" "la clé est nommée : $(printf %q "$valeur")"
  done
}

case_config_surcharge_nom_de_module_a_souligne_refuse() {
  # git config refuse « _ » dans un nom de clé, mais l'accepte dans un nom de sous-section
  raw_config $'[module "te_a"]\n\ttest-framework = playwright'
  load
  assert_eq 2 "$rc" "un nom de module à souligné est refusé"
  assert_contains "module.te_a.test-framework : forme « [module" "$err" "la forme attendue est donnée"
}

case_config_surcharges_avant_chargement_refusees() {
  run config_module_overrides tea
  assert_eq 2 "$rc" "rien n'est lu avant un chargement réussi"
  assert_contains "aucun workflow.config chargé" "$err" "et le message le dit"
}

case_config_surcharge_forme_et_doublon_refuses() {
  raw_config $'[module "tea.x"]\n\ttest-framework = playwright'
  git config -f "$work/projet/workflow.config" bmad.modules "core bmm tea"
  load
  assert_eq 2 "$rc" "un nom de module à point est refusé"
  assert_contains "forme « [module" "$err" "la forme attendue est donnée"
  raw_config $'[module "tea"]\n\ttest-framework = playwright\n[module "tea"]\n\ttest-framework = auto'
  git config -f "$work/projet/workflow.config" bmad.modules "core bmm tea"
  load
  assert_eq 2 "$rc" "une surcharge écrite deux fois est refusée"
  assert_contains "module.tea.test-framework : écrit 2 fois" "$err" "le doublon est nommé"
}

# --- schéma 4 : la convention keyed et ses fichiers qui ne sont pas des stories (calculette#outillage-5)

# Un projet keyed au schéma 4 : $@ = changements de plus.
keyed_config() {
  write_workflow_config "$work/projet" workflow.schema=4 sprint.convention=keyed \
    "sprint.non-story-files=deferred-work spec-* *retro*" "$@"
}

case_config_schema_4_keyed_est_lu() {
  keyed_config
  load
  assert_eq 0 "$rc" "schéma 4, keyed et sa liste (messages : $err)"
  config_load "$work/projet/workflow.config"
  local motifs
  config_get motifs sprint.non-story-files
  assert_eq "deferred-work spec-* *retro*" "$motifs" "la liste est rendue telle quelle, jokers compris"
}

case_config_schema_3_reste_lu() {
  # Le schéma 4 ajoute un champ : le 3 reste lu, sans migration pour les projets numbered.
  write_workflow_config "$work/projet"
  load
  assert_eq 0 "$rc" "un fichier au schéma 3 reste valide (messages : $err)"
  config_load "$work/projet/workflow.config"
  run config_get motifs sprint.non-story-files
  assert_eq 2 "$rc" "le champ du schéma 4 ne se lit pas dans un fichier au schéma 3"
  assert_contains "champ « sprint.non-story-files » du schéma 4" "$err" "le schéma du champ est nommé"
}

case_config_schema_4_exige_non_story_files() {
  write_workflow_config "$work/projet" workflow.schema=4
  load
  assert_eq 2 "$rc" "le champ est requis au schéma 4"
  assert_contains "sprint.non-story-files : champ absent" "$err" "le champ est nommé"
}

case_config_non_story_files_inconnu_du_schema_3() {
  write_workflow_config "$work/projet" sprint.non-story-files=none
  load
  assert_eq 2 "$rc" "un champ du schéma 4 est inconnu du schéma 3"
  assert_contains "sprint.non-story-files : champ du schéma 4, inconnu du schéma 3" "$err" "le champ et les schémas sont nommés"
}

case_config_keyed_exige_le_schema_4() {
  write_workflow_config "$work/projet" sprint.convention=keyed
  load
  assert_eq 2 "$rc" "keyed au schéma 3 est refusé"
  assert_contains "sprint.convention : « keyed » exige le schéma 4" "$err" "le schéma et le champ manquant sont nommés"
}

case_config_non_story_files_seulement_avec_keyed() {
  local convention
  for convention in numbered none; do
    if [[ $convention == none ]]; then
      write_workflow_config "$work/projet" workflow.schema=4 sprint.convention=none sprint.status-file=none \
        sprint.stories-dir=none sprint.spec-source=none "sprint.non-story-files=spec-*"
    else
      write_workflow_config "$work/projet" workflow.schema=4 "sprint.non-story-files=spec-*"
    fi
    load
    assert_eq 2 "$rc" "une liste sans keyed est refusée ($convention)"
    assert_contains "sprint.non-story-files : doit valoir « none » quand sprint.convention ne vaut pas « keyed »" "$err" "la règle est nommée ($convention)"
  done
  write_workflow_config "$work/projet" workflow.schema=4 sprint.non-story-files=none
  load
  assert_eq 0 "$rc" "numbered au schéma 4 avec none (messages : $err)"
  keyed_config sprint.non-story-files=none
  load
  assert_eq 0 "$rc" "keyed avec none : tout fichier .md est une story (messages : $err)"
}

case_config_non_story_files_jamais_etendus_aux_fichiers_du_dossier_courant() {
  # Lu depuis un dossier qui contient « spec-a+b » : « spec-* » ne doit pas devenir ce nom (refusé, « + »).
  keyed_config "sprint.non-story-files=deferred-work spec-*"
  mkdir -p "$work/ici"
  : > "$work/ici/spec-a+b"
  rc=0
  (cd "$work/ici" && config_load "$work/projet/workflow.config") > "$work/.out" 2> "$work/.err" || rc=$?
  assert_eq 0 "$rc" "les motifs sont lus tels quels (messages : $(cat "$work/.err"))"
}

case_config_non_story_files_formes_invalides() {
  local valeur
  local raison
  while IFS='|' read -r valeur raison; do
    keyed_config "sprint.non-story-files=$valeur"
    load
    assert_eq 2 "$rc" "forme refusée : $valeur"
    assert_contains "sprint.non-story-files : $raison" "$err" "le champ et la raison sont nommés : $valeur"
  done <<'CAS'
spec-* spec-*|« spec-* » écrit deux fois
a/b|« a/b » : motif de nom attendu
spec-[x]|« spec-[x] » : motif de nom attendu
x.md|« x.md » : motif de nom attendu
x  y|liste de motifs attendue
.cache|« .cache » : motif de nom attendu
CAS
}

# --- schéma 5 : l'attente et l'étendue du verrou CI (calculette#outillage-8, V12) -------------------

# Un projet au schéma 5 : $@ = changements de plus.
schema_5_config() {
  write_workflow_config "$work/projet" workflow.schema=5 sprint.non-story-files=none ci.statuses=context \
    ci.wait=0 "$@"
}

case_config_schema_5_est_lu() {
  local valeur
  for valeur in "ci.statuses=context ci.wait=0" "ci.statuses=all ci.wait=1200" "ci.statuses=context ci.wait=99999"; do
    # shellcheck disable=SC2086 # découpage voulu : deux changements
    schema_5_config $valeur
    load
    assert_eq 0 "$rc" "schéma 5 admis : $valeur (messages : $err)"
  done
  config_load "$work/projet/workflow.config"
  local statuts attente
  config_get statuts ci.statuses
  config_get attente ci.wait
  assert_eq "context 99999" "$statuts $attente" "les deux champs sont rendus tels quels"
}

case_config_schema_5_exige_ses_champs() {
  local champ
  for champ in ci.statuses ci.wait; do
    schema_5_config "-$champ"
    load
    assert_eq 2 "$rc" "$champ est requis au schéma 5 : aucune valeur par défaut"
    assert_contains "$champ : champ absent" "$err" "le champ est nommé"
  done
}

case_config_champs_du_schema_5_inconnus_du_schema_4() {
  local champ
  for champ in ci.statuses=context ci.wait=0; do
    write_workflow_config "$work/projet" workflow.schema=4 sprint.non-story-files=none "$champ"
    load
    assert_eq 2 "$rc" "${champ%%=*} est inconnu du schéma 4"
    assert_contains "${champ%%=*} : champ du schéma 5, inconnu du schéma 4" "$err" "le champ et les schémas sont nommés"
  done
  write_workflow_config "$work/projet" workflow.schema=4 sprint.non-story-files=none
  load
  assert_eq 0 "$rc" "le schéma 4 reste lu (messages : $err)"
  config_load "$work/projet/workflow.config"
  run config_get valeur ci.wait
  assert_eq 2 "$rc" "ci.wait ne se lit pas dans un fichier au schéma 4"
  assert_contains "champ « ci.wait » du schéma 5" "$err" "le schéma du champ est nommé"
}

case_config_schema_5_types_invalides() {
  local change
  for change in ci.statuses=tous ci.statuses=Context ci.wait=-1 ci.wait=01 ci.wait=1e3 ci.wait=20m \
    ci.wait=100000 "ci.wait= 5"; do
    schema_5_config "$change"
    load
    assert_eq 2 "$rc" "type invalide refusé : $change"
    assert_contains "${change%%=*} :" "$err" "le champ est nommé : $change"
    [[ $err != *inconnu* ]] || { echo "refusé pour une autre raison que le type ($change) : $err" >&2; exit 1; }
  done
}

case_config_schema_5_ci_desactivee_ensemble() {
  schema_5_config ci.workflow=none ci.status-context=none ci.statuses=none ci.wait=none
  load
  assert_eq 0 "$rc" "une CI désactivée désactive l'étendue et l'attente (messages : $err)"
  local champ
  for champ in ci.statuses ci.wait; do
    schema_5_config ci.workflow=none ci.status-context=none ci.statuses=none ci.wait=none "$champ=$([[ $champ == ci.wait ]] && echo 0 || echo all)"
    load
    assert_eq 2 "$rc" "$champ porte une valeur alors que la CI est désactivée"
    assert_contains "$champ : doit valoir « none » quand ci.workflow vaut « none »" "$err" "la règle est nommée"
    schema_5_config "$champ=none"
    load
    assert_eq 2 "$rc" "$champ désactivé alors que la CI est active"
    assert_contains "$champ : « none » refusé tant que ci.workflow porte une valeur" "$err" "la règle est nommée"
  done
}

case_config_rapport_en_fichier_retire() {
  # calculette#outillage-8 : le rapport de revue est un commentaire de PR ; « file » n'est plus servi
  # par aucun outil, il n'est plus une valeur du schéma.
  write_workflow_config "$work/projet" review.report=file
  load
  assert_eq 2 "$rc" "review.report = file est refusé"
  assert_contains "review.report : « pr-comment » attendu" "$err" "la seule valeur servie est nommée"
}

run_case "$@"
