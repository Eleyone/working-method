#!/usr/bin/env bash
# bin/install, partie BMAD (story 1) : liens vers la méthode du sous-module, configuration générée
# depuis workflow.config et _bmad/config.user.toml, refus d'un écart de version (1) ou d'une
# déclaration illisible (2), modules hors de l'union (1), relance sans effet.
# Hors ligne : le dépôt commun est recopié dans un dépôt git jetable, consommé en sous-module.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

commun_jetable() {
  mkdir -p "$work/commun"
  cp -R "$common/bin" "$common/lib" "$common/skills" "$common/bmad" "$work/commun/"
  git -C "$work/commun" init -q
  git -C "$work/commun" add -A
  git -C "$work/commun" -c user.name=essai -c user.email=essai@example.invalid -c core.hooksPath=/dev/null \
    commit -q -m commun
}

utilisatrice() { # $1 = contenu de _bmad/config.user.toml
  mkdir -p "$work/depot/_bmad"
  printf '%s\n' "$1" > "$work/depot/_bmad/config.user.toml"
}

projet() { # $1… = changements du workflow.config
  commun_jetable
  new_repo
  git -C "$work/depot" -c protocol.file.allow=always submodule add -q "$work/commun" outils/commun 2>/dev/null
  write_workflow_config "$work/depot" "bmad.modules=core bmm tea" "agents.skill-dirs=.claude/skills .agents/skills" "$@"
  utilisatrice '[core]
user_name = "Utilisatrice"
communication_language = "Français"

[modules.bmm]
user_skill_level = "expert"'
  printf '/_bmad/*/config.yaml\n/_bmad/config.user.toml\n' > "$work/depot/.gitignore"
}

installe() { run bash -c 'cd "$1" && sh outils/commun/bin/install' _ "$work/depot"; }

lien() { readlink "$work/depot/$1"; }

# Chaque chemin posé sous .claude, .agents et _bmad : lien et cible, ou fichier, son contenu et sa date.
etat() {
  (cd "$work/depot" && find .claude .agents _bmad -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
    if [[ -L $p ]]; then printf '%s -> %s\n' "$p" "$(readlink "$p")"
    elif [[ -f $p ]]; then printf '%s %s %s\n' "$p" "$(git hash-object "$p")" "$(stat -c %Y "$p")"
    else printf '%s/\n' "$p"; fi
  done)
}

rien_d_ecrit() { # $1 = libellé
  [[ ! -e $work/depot/_bmad/config.toml && ! -e $work/depot/.claude ]] \
    || { echo "$1 : bin/install a écrit malgré le refus" >&2; exit 1; }
}

case_installe_relie_la_methode_des_modules_actives() {
  projet
  installe
  assert_eq 0 "$rc" "installation (messages : $err)"
  assert_eq ../../outils/commun/bmad/method/skills/bmad-help "$(lien .claude/skills/bmad-help)" "skill de core, lien relatif"
  assert_eq ../../outils/commun/bmad/method/skills/bmad-tea "$(lien .agents/skills/bmad-tea)" "skill de tea, dans chaque dossier"
  assert_eq ../../outils/commun/bmad/method/skills/bmad-create-story "$(lien .claude/skills/bmad-create-story)" "shim de bmm"
  [[ -f $work/depot/.claude/skills/bmad-help/SKILL.md ]] || { echo "SKILL.md illisible à travers le lien" >&2; exit 1; }
  [[ ! -e $work/depot/.claude/skills/bmad-agent-builder && ! -e $work/depot/.claude/skills/bmad-cis-storytelling ]] \
    || { echo "un skill d'un module non activé (bmb, cis) est relié" >&2; exit 1; }
  assert_eq ../../outils/commun/bmad/method/modules/core/module-help.csv "$(lien _bmad/core/module-help.csv)" "catalogue du module, fichier par fichier"
  assert_eq ../../outils/commun/bmad/method/modules/bmm/v6-shims "$(lien _bmad/bmm/v6-shims)" "dossier de méthode d'un module"
  assert_eq ../outils/commun/bmad/method/scripts "$(lien _bmad/scripts)" "scripts de BMAD"
  [[ -d $work/depot/_bmad/bmm && ! -L $work/depot/_bmad/bmm ]] || { echo "_bmad/bmm doit être un vrai dossier (décision D)" >&2; exit 1; }
  [[ -f $work/depot/_bmad/tea/config.yaml && ! -L $work/depot/_bmad/tea/config.yaml ]] || { echo "config.yaml généré attendu" >&2; exit 1; }
  [[ ! -e $work/depot/_bmad/cis ]] || { echo "_bmad/cis posé alors que cis n'est pas activé" >&2; exit 1; }
  assert_contains "BMAD 6.12.0" "$out" "la version est dite"
}

case_configuration_generee_depuis_workflow_config() {
  projet "bmad.project-name=mon-projet" "bmad.document-output-language=Français" "bmad.output-folder=sorties"
  installe
  assert_eq 0 "$rc" "installation (messages : $err)"
  local toml yaml
  toml=$(cat "$work/depot/_bmad/config.toml")
  assert_contains 'project_name = "mon-projet"' "$toml" "nom du projet"
  assert_contains 'document_output_language = "Français"' "$toml" "langue des documents"
  assert_contains 'planning_artifacts = "{project-root}/sorties/planning-artifacts"' "$toml" "dossier de sortie, et ce qui en dérive"
  assert_contains '[modules.tea]' "$toml" "bloc d'un module activé"
  [[ $toml != *'[modules.bmb]'* && $toml != *'bmad-cis-agent'* ]] || { echo "bloc d'un module non activé" >&2; exit 1; }
  [[ $toml != *'@'*'@'* || $toml != *'@bmad.'* ]] || { echo "champ non rempli" >&2; exit 1; }
  assert_contains "Généré par bin/install" "$toml" "l'en-tête dit d'où vient le fichier"
  yaml=$(cat "$work/depot/_bmad/bmm/config.yaml")
  assert_contains "user_name: Utilisatrice" "$yaml" "valeur de config.user.toml"
  assert_contains "user_skill_level: expert" "$yaml" "valeur de module de config.user.toml"
  assert_contains "project_name: mon-projet" "$yaml" "valeur de workflow.config"
  [[ $yaml != *'# Date:'* ]] || { echo "une date rendrait la génération non reproductible" >&2; exit 1; }
  local aide
  aide=$(cat "$work/depot/_bmad/_config/bmad-help.csv")
  assert_contains $'module,skill,' "$aide" "en-tête du catalogue"
  assert_contains "Test Architecture Enterprise," "$aide" "lignes de tea"
  [[ $aide != *"BMad Builder,"* && $aide != *"Creative Intelligence Suite,"* ]] || { echo "catalogue d'un module non activé" >&2; exit 1; }
}

case_relance_ne_change_rien() {
  projet
  installe
  local avant
  avant=$(etat)
  sleep 1
  installe
  assert_eq 0 "$rc" "seconde installation (messages : $err)"
  assert_eq "$avant" "$(etat)" "la seconde installation ne change rien, dates comprises"
  assert_contains "0 lien(s) posé(s)" "$out" "et elle le dit"
  [[ $err != *ATTENTION* ]] || { echo "rien n'a été édité, rien ne doit être signalé : $err" >&2; exit 1; }
}

case_edition_a_la_main_ecrasee_et_signalee() {
  projet
  installe
  local toml yaml
  toml=$(cat "$work/depot/_bmad/config.toml")
  yaml=$(cat "$work/depot/_bmad/bmm/config.yaml")
  printf '[core]\nproject_name = "édité"\n' >> "$work/depot/_bmad/config.toml"
  sed -i 's/^user_skill_level: .*/user_skill_level: beginner/' "$work/depot/_bmad/bmm/config.yaml"
  installe
  assert_eq 0 "$rc" "l'édition ne bloque pas (messages : $err)"
  assert_eq "$toml" "$(cat "$work/depot/_bmad/config.toml")" "config.toml est réécrit depuis workflow.config"
  assert_eq "$yaml" "$(cat "$work/depot/_bmad/bmm/config.yaml")" "config.yaml aussi"
  assert_contains "ATTENTION" "$err" "l'écrasement est signalé"
  assert_contains "_bmad/config.toml" "$err" "le fichier écrasé est nommé"
  assert_contains "_bmad/bmm/config.yaml" "$err" "chacun"
}

case_version_differente_rend_1() {
  projet bmad.version=6.11.0
  installe
  assert_eq 1 "$rc" "un écart de version rend 1"
  assert_contains "6.11.0" "$err" "la version du projet est nommée"
  assert_contains "6.12.0" "$err" "celle du sous-module aussi"
  rien_d_ecrit "écart de version"
}

case_declaration_du_sous_module_illisible_rend_2() {
  # bin/install lit la déclaration du sous-module tel qu'il est extrait dans le projet
  local sous_module="$work/depot/outils/commun"
  projet
  rm "$sous_module/bmad/bmad.config"
  installe
  assert_eq 2 "$rc" "sans déclaration lisible dans le sous-module, 2"
  assert_contains "bmad.config" "$err" "le fichier est nommé"
  rien_d_ecrit "déclaration absente"
  printf '[bmad]\n\tversion = 6.12.0\n\tinconnu = x\n' > "$sous_module/bmad/bmad.config"
  installe
  assert_eq 2 "$rc" "une déclaration refusée rend 2, jamais 0"
  assert_contains "bmad.inconnu" "$err" "le champ refusé est nommé"
  git -C "$sous_module" checkout -q -- bmad/bmad.config
  local manque
  for manque in skills scripts modules templates/config.toml bmad-help.csv skill-manifest.csv \
    modules/tea templates/tea.config.yaml; do
    rm -rf "${sous_module:?}/bmad/method/$manque"
    installe
    assert_eq 2 "$rc" "méthode incomplète dans le sous-module ($manque absent) : 2"
    assert_contains "méthode BMAD incomplète" "$err" "le défaut est nommé ($manque)"
    rien_d_ecrit "méthode incomplète ($manque)"
    git -C "$sous_module" checkout -q -- bmad/method
  done
  # un dossier de module présent mais vide : la garde propre à ce cas, pas celle de l'absence
  rm -rf "${sous_module:?}/bmad/method/modules/tea"
  mkdir -p "$sous_module/bmad/method/modules/tea"
  installe
  assert_eq 2 "$rc" "dossier de méthode du module vide : 2"
  assert_contains "méthode du module tea vide" "$err" "le module est nommé"
  rien_d_ecrit "module vide"
  git -C "$sous_module" checkout -q -- bmad/method
}

case_module_hors_de_l_union_rend_1() {
  local modules
  for modules in "core bmm wds" "core bmm render"; do
    projet "bmad.modules=$modules"
    installe
    assert_eq 1 "$rc" "module hors de l'union : $modules"
    assert_contains "${modules##* }" "$err" "le module est nommé"
    assert_contains "core bmm bmb cis bmad-loop tea" "$err" "l'union est rappelée"
    rien_d_ecrit "$modules"
    rm -rf "$work/depot" "$work/commun"
  done
  projet "bmad.modules=bmm tea"
  installe
  assert_eq 1 "$rc" "core est requis"
  assert_contains "core" "$err" "et nommé"
}

case_schema_1_ou_2_refuse() {
  projet workflow.schema=1 -bmad.project-name -bmad.document-output-language -bmad.output-folder -review.reviewers \
    review.reviewer-for-claude=gemini-3.1-pro-high review.reviewer-for-gemini=claude-opus-4-6-thinking
  installe
  assert_eq 2 "$rc" "un workflow.config au schéma 1 ne dit pas comment générer la configuration BMAD"
  assert_contains "schéma 1 retiré : le schéma 3 est attendu" "$err" "le schéma requis est nommé, avant toute autre lecture"
  rien_d_ecrit "schéma 1"
  rm -rf "$work/depot" "$work/commun"
  projet workflow.schema=2 -review.reviewers \
    review.reviewer-for-claude=gemini-3.1-pro-high review.reviewer-for-gemini=claude-opus-4-6-thinking
  installe
  assert_eq 2 "$rc" "un workflow.config au schéma 2 porte les anciennes clés de relecteur"
  assert_contains "review.reviewer-for-claude : retiré au schéma 3 : la table review.reviewers le remplace" "$err" "la nouvelle forme est nommée"
  rien_d_ecrit "schéma 2"
}

case_config_user_absente_ou_illisible_rend_2() {
  projet
  rm "$work/depot/_bmad/config.user.toml"
  installe
  assert_eq 2 "$rc" "config.user.toml absent : 2"
  assert_contains "_bmad/config.user.toml" "$err" "le fichier est nommé"
  assert_contains "user_name" "$err" "les clés attendues sont données"
  rien_d_ecrit "config.user.toml absent"
  utilisatrice $'[core]\nuser_name = Utilisatrice'
  installe
  assert_eq 2 "$rc" "forme non lue : 2"
  assert_contains "ligne 2" "$err" "la ligne est nommée"
  utilisatrice $'[core]\nuser_name = "a: b"\ncommunication_language = "Français"\n[modules.bmm]\nuser_skill_level = "expert"'
  installe
  assert_eq 2 "$rc" "valeur qui changerait le sens du YAML généré : 2"
  utilisatrice $'[core]\nuser_name = "Utilisatrice"\n[modules.bmm]\nuser_skill_level = "expert"'
  installe
  assert_eq 2 "$rc" "clé attendue absente : 2"
  assert_contains "core.communication_language" "$err" "la clé manquante est nommée"
  rien_d_ecrit "clé absente"
}

case_config_user_sans_aucune_cle_rend_2() {
  # Un fichier lisible mais vide de clés : un tableau associatif vide, que bash 4.3 tient pour non
  # défini sous « set -u ». Le refus doit rester un 2 nommé, jamais une erreur du shell.
  projet
  utilisatrice $'# rien encore\n[core]'
  installe
  assert_eq 2 "$rc" "aucune clé : 2"
  assert_contains "clé(s) absente(s)" "$err" "les clés manquantes sont nommées"
  [[ $err != *"unbound variable"* ]] || { echo "erreur du shell au lieu d'un refus : $err" >&2; exit 1; }
}

case_libelle_de_workflow_config_refuse() {
  projet "bmad.project-name=a: b"
  installe
  assert_eq 2 "$rc" "un libellé qui changerait le sens du YAML généré est refusé"
  assert_contains "bmad.project-name" "$err" "le champ est nommé"
}

case_config_yaml_versionne_rend_1() {
  projet
  installe
  git -C "$work/depot" add -f _bmad/bmm/config.yaml
  installe
  assert_eq 1 "$rc" "un config.yaml suivi par git rend 1 : il n'est pas versionné (décision E)"
  assert_contains "_bmad/bmm/config.yaml" "$err" "le fichier est nommé"
}

case_skill_bmad_existant_est_un_conflit() {
  projet
  mkdir -p "$work/depot/.claude/skills/bmad-help"
  printf 'copie locale\n' > "$work/depot/.claude/skills/bmad-help/SKILL.md"
  installe
  assert_eq 1 "$rc" "une copie locale de BMAD n'est jamais écrasée"
  assert_contains ".claude/skills/bmad-help : existe déjà et n'est pas un lien" "$err" "le conflit est nommé"
  assert_eq "copie locale" "$(cat "$work/depot/.claude/skills/bmad-help/SKILL.md")" "la copie est intacte"
  [[ ! -e $work/depot/_bmad/config.toml ]] || { echo "configuration écrite malgré le conflit" >&2; exit 1; }
}

case_parents_et_fichiers_generes_en_conflit() {
  # Chaque garde du plan, avant toute écriture : rien n'est écrit, et le conflit est nommé.
  local sous_module="$work/depot/outils/commun" cas
  for cas in module-lien bmad-lien parent-fichier config-dossier config-lien; do
    projet
    case $cas in
      module-lien) mkdir -p "$work/ailleurs"; ln -s "$work/ailleurs" "$work/depot/_bmad/bmm" ;;
      bmad-lien)
        mv "$work/depot/_bmad" "$work/bmad-reel"
        ln -s "$work/bmad-reel" "$work/depot/_bmad"
        ;;
      parent-fichier) printf 'x\n' > "$work/depot/.agents" ;;
      config-dossier) mkdir -p "$work/depot/_bmad/config.toml" ;;
      config-lien) ln -s "$sous_module/README.md" "$work/depot/_bmad/config.toml" 2>/dev/null || ln -s ailleurs "$work/depot/_bmad/config.toml" ;;
    esac
    installe
    assert_eq 1 "$rc" "conflit $cas : 1 (messages : $err)"
    case $cas in
      module-lien) assert_contains "_bmad/bmm : un lien" "$err" "le dossier du module est nommé" ;;
      bmad-lien) assert_contains "_bmad : un lien" "$err" "_bmad est nommé" ;;
      parent-fichier) assert_contains ".agents : existe et n'est pas un dossier" "$err" "le parent est nommé" ;;
      config-dossier) assert_contains "_bmad/config.toml : existe et n'est pas un fichier" "$err" "le fichier généré est nommé" ;;
      config-lien) assert_contains "_bmad/config.toml : existe et n'est pas un fichier" "$err" "le lien est nommé" ;;
    esac
    [[ ! -e $work/depot/.claude && ! -e $work/depot/.working-method ]] || { echo "$cas : écriture malgré le conflit" >&2; exit 1; }
    assert_eq "" "$(git -C "$sous_module" status --porcelain)" "$cas : le sous-module est intact"
    rm -rf "$work/depot" "$work/commun" "$work/ailleurs" "$work/bmad-reel"
  done
}

case_valeur_vide_de_config_user_refusee() {
  projet
  utilisatrice $'[core]\nuser_name = ""\ncommunication_language = "Français"\n[modules.bmm]\nuser_skill_level = "expert"'
  installe
  assert_eq 2 "$rc" "une valeur vide n'est jamais une valeur (messages : $err)"
  assert_contains "core.user_name » : valeur vide" "$err" "la clé est nommée"
  rien_d_ecrit "valeur vide"
}

case_module_desactive_est_retire() {
  projet
  installe
  write_workflow_config "$work/depot" "bmad.modules=core bmm" "agents.skill-dirs=.claude/skills .agents/skills"
  installe
  assert_eq 0 "$rc" "réinstallation avec un module de moins (messages : $err)"
  [[ ! -e $work/depot/.claude/skills/bmad-tea && ! -L $work/depot/.claude/skills/bmad-tea ]] \
    || { echo "le lien d'un skill de tea est resté" >&2; exit 1; }
  [[ ! -e $work/depot/_bmad/tea ]] || { echo "_bmad/tea est resté" >&2; exit 1; }
  assert_contains "lien retiré" "$out" "le retrait est dit"
}

case_sous_module_propre_apres_installation() {
  # AC 5 : bin/install n'écrit jamais à travers ses liens.
  projet
  installe
  assert_eq 0 "$rc" "installation (messages : $err)"
  assert_eq "" "$(git -C "$work/depot/outils/commun" status --porcelain --ignored)" "le sous-module est propre"
}

# --- surcharges des modules : « [module "<nom>"] » de workflow.config ---------------------------

surcharges_tea=(module.tea.test-framework=playwright module.tea.tea-pact-mcp=none
  "module.tea.test-artifacts={project-root}/_bmad-output/test-artifacts"
  "module.tea.test-design-output=_bmad-output/test-artifacts/test-design"
  module.tea.tea-use-playwright-utils=false)

case_surcharges_appliquees_au_yaml_et_au_toml() {
  projet "${surcharges_tea[@]}"
  installe
  assert_eq 0 "$rc" "installation avec surcharges (messages : $err)"
  local yaml toml
  yaml=$(cat "$work/depot/_bmad/tea/config.yaml")
  toml=$(cat "$work/depot/_bmad/config.toml")
  assert_contains $'\ntest_framework: "playwright"\n' "$yaml" "valeur surchargée, citée"
  assert_contains $'\ntea_pact_mcp: "none"\n' "$yaml" "une chaîne « none » reste une valeur"
  assert_contains $'\ntest_artifacts: "{project-root}/_bmad-output/test-artifacts"\n' "$yaml" "chemin surchargé"
  assert_contains $'\ntest_design_output: "_bmad-output/test-artifacts/test-design"\n' "$yaml" "chemin non cité au modèle, cité ici"
  assert_contains $'\ntea_use_playwright_utils: false\n' "$yaml" "un booléen reste nu"
  assert_contains 'test_framework = "playwright"' "$toml" "config.toml suit"
  assert_contains 'tea_pact_mcp = "none"' "$toml" "config.toml suit"
  assert_contains 'tea_use_playwright_utils = false' "$toml" "booléen nu dans config.toml"
  # les valeurs non surchargées gardent celles du modèle
  assert_contains $'\nrisk_threshold: p1\n' "$yaml" "valeur du modèle intacte"
  assert_contains $'\ntest_review_output: skills/test-artifacts/test-reviews\n' "$yaml" "valeur du modèle intacte, même voisine d'une surcharge"
  assert_contains 'risk_threshold = "p1"' "$toml" "valeur du modèle intacte dans config.toml"
  local modele
  modele=$(grep -c . "$work/commun/bmad/method/templates/tea.config.yaml")
  assert_eq "$modele" "$(grep -c . "$work/depot/_bmad/tea/config.yaml" | awk '{print $1 - 2}')" "aucune ligne ajoutée ni perdue (en-tête de deux lignes excepté)"
}

case_surcharges_relance_ne_change_rien() {
  projet "${surcharges_tea[@]}"
  installe
  local avant
  avant=$(etat)
  sleep 1
  installe
  assert_eq 0 "$rc" "seconde installation (messages : $err)"
  assert_eq "$avant" "$(etat)" "la seconde installation ne change rien, dates comprises"
  [[ $err != *ATTENTION* ]] || { echo "une surcharge n'est pas une édition à la main : $err" >&2; exit 1; }
}

case_surcharge_sans_cle_au_rendu_rend_2() {
  # le modèle de config.toml et celui du config.yaml ne concordent plus : rien n'est écrit
  projet "${surcharges_tea[@]}"
  sed -i '/^test_framework = /d' "$work/depot/outils/commun/bmad/method/templates/config.toml"
  installe
  assert_eq 2 "$rc" "une clé surchargée absente de [modules.tea] arrête l'installation"
  assert_contains "clé « test_framework » trouvée 0 fois dans [modules.tea]" "$err" "la clé et le bloc sont nommés"
  rien_d_ecrit "clé absente du toml"
}

case_surcharge_cle_en_double_au_rendu_rend_2() {
  projet "${surcharges_tea[@]}"
  printf 'test_framework: auto\n' >> "$work/depot/outils/commun/bmad/method/templates/tea.config.yaml"
  installe
  assert_eq 2 "$rc" "une clé surchargée en double dans le modèle arrête l'installation"
  assert_contains "clé « test_framework » trouvée 2 fois" "$err" "le compte est dit"
  rien_d_ecrit "clé en double"
}

case_surcharge_ecriture_impossible_rend_2() {
  # l'écriture passe par « <fichier>.surcharge » : un dossier à ce nom la fait échouer, même en root
  write_workflow_config "$work/projet" "bmad.modules=core bmm tea" module.tea.test-framework=playwright
  printf 'test_framework: auto\n' > "$work/rendu.yaml"
  printf '[modules.tea]\ntest_framework = "auto"\n' > "$work/rendu.toml"
  local fichier
  for fichier in rendu.yaml rendu.toml; do
    rm -rf "$work"/rendu.*.surcharge
    mkdir "$work/$fichier.surcharge"
    # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
    run bash -c '. "$1/lib/bmad.sh" && config_load "$2" && bmad_apply_overrides "$3/rendu.yaml" "$3/rendu.toml" tea' \
      _ "$common" "$work/projet/workflow.config" "$work"
    assert_eq 2 "$rc" "écriture impossible de $fichier : 2"
    assert_contains "$work/$fichier : écriture impossible" "$err" "le fichier est nommé"
  done
  assert_eq 'test_framework = "auto"' "$(sed -n 2p "$work/rendu.toml")" "un échec laisse le fichier rendu tel qu'il était"
}

case_surcharge_invalide_refusee_sans_rien_ecrire() {
  projet module.tea.inconnue=x
  installe
  assert_eq 2 "$rc" "une surcharge inconnue est refusée par la lecture de workflow.config"
  assert_contains "module.tea.inconnue : clé inconnue du modèle de tea" "$err" "la clé est nommée"
  rien_d_ecrit "surcharge inconnue"
}

run_case "$@"
