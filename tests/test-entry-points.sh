#!/usr/bin/env bash
# Les points d'entrée (verify-and-merge-pr, create-pull-request, llm-review, sprint-consistency)
# lisent workflow.config AVANT toute action : un fichier refusé, ou une valeur que l'outillage ne sait
# pas encore servir, les arrête en 2 sans appeler la forge ni le relecteur. Aucun réseau : curl et agy
# sont remplacés par des bouchons qui notent leur appel, et ne doivent jamais être appelés ici.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

bouchons() { # PATH avec un curl et un agy qui notent leur appel et échouent
  mkdir -p "$work/bouchons"
  local outil
  for outil in curl agy; do
    printf '#!/bin/sh\necho "%s appelé" >> "%s/appels"\nexit 9\n' "$outil" "$work" > "$work/bouchons/$outil"
    chmod +x "$work/bouchons/$outil"
  done
}

projet() { # $1… = changements du workflow.config
  new_repo
  write_workflow_config "$work/depot" "$@"
  git -C "$work/depot" remote add origin "git@forge.example.invalid:Proprietaire/projet-essai.git"
  git -C "$work/depot" checkout -q -b feat/essai
  bouchons
}

lance() { # $1 script du dépôt commun, $2… arguments
  local script=$1
  shift
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run env PATH="$work/bouchons:$PATH" bash -c 'cd "$1" && shift && bash "$@"' _ "$work/depot" "$common/$script" "$@"
}

aucun_appel() {
  [[ ! -e $work/appels ]] || { echo "appel réseau ou relecteur malgré le refus : $(cat "$work/appels")" >&2; exit 1; }
}

case_config_incomplete_arrete_chaque_point_d_entree() {
  projet -forge.repo
  local entree
  for entree in "gates/verify-and-merge-pr.sh 1" "gitea/create-pull-request.sh --title essai" \
    "review/llm-review.sh 1" "gates/sprint-consistency.sh"; do
    # shellcheck disable=SC2086 # découpage voulu : script et arguments
    lance $entree
    assert_eq 2 "$rc" "$entree : workflow.config incomplet → 2"
    assert_contains "forge.repo : champ absent" "$err" "$entree : le champ est nommé"
  done
  aucun_appel
}

case_convention_keyed_pas_encore_servie() {
  projet sprint.convention=keyed
  lance gates/verify-and-merge-pr.sh 1
  assert_eq 2 "$rc" "verify-and-merge-pr refuse keyed"
  assert_contains "story 5" "$err" "en nommant la story qui l'apportera"
  lance review/llm-review.sh 1
  assert_eq 2 "$rc" "llm-review refuse keyed"
  assert_contains "story 5" "$err" "en nommant la story qui l'apportera"
  aucun_appel
}

case_rapport_en_fichier_pas_encore_servi() {
  projet review.report=file
  lance gates/verify-and-merge-pr.sh 1
  assert_eq 2 "$rc" "verify-and-merge-pr ne sait pas lire un rapport versionné"
  assert_contains "story 8" "$err" "en nommant la story qui l'apportera"
  lance review/llm-review.sh 1
  assert_eq 2 "$rc" "llm-review ne sait pas écrire un rapport versionné"
  assert_contains "story 8" "$err" "en nommant la story qui l'apportera"
  aucun_appel
}

case_revue_de_spec_desactivee() {
  projet sprint.spec-source=none
  printf '## Projet\nessai\n' > "$work/depot/review-layer.md"
  write_workflow_config "$work/depot" sprint.spec-source=none review.project-layer=review-layer.md
  lance review/llm-review.sh --story 1.2
  assert_eq 2 "$rc" "la revue de spec sans source sort en 2"
  assert_contains "revue de spec désactivée (sprint.spec-source = none)" "$err" "et le dit"
  aucun_appel
}

case_couche_projet_absente() {
  projet
  lance review/llm-review.sh 1
  assert_eq 2 "$rc" "sans couche projet, rien n'est envoyé"
  assert_contains "couche projet absente ou vide" "$err" "le message nomme la couche"
  aucun_appel
}

case_garde_fou_declare_mais_absent() {
  projet
  printf '## Projet\nessai\n' > "$work/depot/review/project-layer.md" 2>/dev/null \
    || { mkdir -p "$work/depot/review"; printf '## Projet\nessai\n' > "$work/depot/review/project-layer.md"; }
  lance gates/verify-and-merge-pr.sh 1
  assert_eq 2 "$rc" "un garde-fou déclaré mais absent arrête l'audit"
  assert_contains "scripts/check-private.sh absent ou non exécutable (guard.command)" "$err" "le message nomme le champ"
  aucun_appel
}

case_depot_distant_autre_que_forge_repo() {
  projet guard.command=none guard.patterns-file=none
  git -C "$work/depot" remote set-url origin "git@forge.example.invalid:Proprietaire/autre.git"
  lance gates/verify-and-merge-pr.sh 1
  assert_eq 2 "$rc" "un dépôt distant qui n'est pas forge.repo arrête l'audit"
  assert_contains "n'est pas Proprietaire/projet-essai" "$err" "le message nomme le dépôt attendu"
  aucun_appel
}

case_fichier_d_environnement_lu_jusqu_au_bout() {
  # Les scripts déclarent leurs valeurs de workflow.config en lecture seule : une variable locale du même
  # nom dans une bibliothèque échouerait (« readonly variable ») au lieu de lire le fichier — constaté
  # à la première revue du dépôt commun. Chaque point d'entrée doit atteindre la lecture de
  # forge.env-file et dire qu'il manque.
  projet guard.command=none guard.patterns-file=none forge.env-file=secrets.env
  mkdir -p "$work/depot/review"
  printf '## Projet\nessai\n' > "$work/depot/review/project-layer.md"
  local entree
  for entree in "gates/verify-and-merge-pr.sh 1" "review/llm-review.sh 1"; do
    # shellcheck disable=SC2086 # découpage voulu : script et arguments
    lance $entree
    assert_contains "secrets.env absent (forge.env-file)" "$err" "$entree : le fichier déclaré est cherché (messages : $err)"
    [[ $err != *"readonly variable"* ]] || { echo "$entree : collision de variable en lecture seule" >&2; exit 1; }
  done
  aucun_appel
}

# --- create-pull-request : 1 = la branche ou l'arbre ne permet pas d'ouvrir la PR (écart constaté) ;
# 2 = l'ouverture n'a pas pu être tentée (usage, prérequis, forge illisible)

projet_pr() { # un projet sans garde-fou, commité, avec un corps de PR
  projet guard.command=none guard.patterns-file=none
  commit_all "le projet" > /dev/null
  printf 'corps\n' > "$work/corps.md"
}

case_ouverture_branche_sans_prefixe_admis_rend_1() {
  projet_pr
  git -C "$work/depot" checkout -q -b essai/x
  lance gitea/create-pull-request.sh --title essai --body-file "$work/corps.md"
  assert_eq 1 "$rc" "une branche au préfixe non déclaré : écart constaté"
  assert_contains "préfixe de branche refusé : essai/x" "$err" "le refus le dit"
  aucun_appel
}

case_ouverture_avec_modifications_non_commitees_rend_1() {
  projet_pr
  printf 'brouillon\n' > "$work/depot/brouillon.txt"
  lance gitea/create-pull-request.sh --title essai --body-file "$work/corps.md"
  assert_eq 1 "$rc" "un arbre modifié : écart constaté"
  assert_contains "modifications non commitées" "$err" "le refus le dit"
  aucun_appel
}

case_ouverture_sans_titre_rend_2() {
  projet_pr
  lance gitea/create-pull-request.sh --body-file "$work/corps.md"
  assert_eq 2 "$rc" "sans titre, rien n'est tenté"
  assert_contains "titre manquant" "$err" "le refus le dit"
  aucun_appel
}

case_ouverture_base_illisible_sur_la_forge_rend_2() {
  projet_pr
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run env PATH="$work/bouchons:$PATH" GIT_SSH_COMMAND=false bash -c 'cd "$1" && shift && bash "$@"' _ "$work/depot" \
    "$common/gitea/create-pull-request.sh" --title essai --body-file "$work/corps.md"
  assert_eq 2 "$rc" "la base illisible sur la forge : l'ouverture n'a pas pu être tentée ($err)"
  assert_contains "lecture de la branche dev sur la forge impossible" "$err" "le message nomme l'étape"
  aucun_appel
}

run_case "$@"
