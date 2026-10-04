#!/usr/bin/env bash
# Adaptateur de la forge (gitea/gitea.sh) : ce que le paramétrage par workflow.config y a fait entrer —
# le dépôt canonique lu dans forge.repo, et la base d'une PR déduite de forge.base, de
# forge.release-branch et de forge.branch-prefixes. Aucun appel réseau.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Chaque appel tourne dans son propre bash : die quitte, ce qui terminerait le cas.
adaptateur() { # $1 = dossier de travail, $2 = corps à exécuter après le chargement
  run bash -c 'set -euo pipefail; script_name=essai; cd "$1"; . "$2/lib/config.sh"; . "$2/gitea/gitea.sh"; eval "$3"' \
    _ "$1" "$common" "$2"
}

case_depot_canonique_lu_dans_workflow_config() {
  new_repo
  write_workflow_config "$work/depot"
  git -C "$work/depot" remote add origin "git@forge.example.invalid:Proprietaire/projet-essai.git"
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  adaptateur "$work/depot" 'config_load workflow.config; gitea_configure; check_origin; echo "ok $gitea_canonical_repo"'
  assert_eq 0 "$rc" "origin est le dépôt déclaré (messages : $err)"
  assert_eq "ok Proprietaire/projet-essai" "$out" "le dépôt canonique vient de forge.repo"
  git -C "$work/depot" remote set-url origin "https://forge.example.invalid/Proprietaire/autre.git"
  adaptateur "$work/depot" 'config_load workflow.config; gitea_configure; check_origin; echo atteint'
  assert_eq 1 "$rc" "un autre dépôt distant est refusé"
  assert_contains "n'est pas Proprietaire/projet-essai" "$err" "le message nomme le dépôt attendu"
  [[ $err != *forge.example.invalid* ]] || { echo "le message affiche l'adresse de la forge" >&2; exit 1; }
}

case_check_origin_sans_configuration() {
  # Plus aucun nom de dépôt n'est écrit dans l'adaptateur : sans workflow.config lu, il refuse.
  new_repo
  git -C "$work/depot" remote add origin "git@forge.example.invalid:Proprietaire/projet-essai.git"
  adaptateur "$work/depot" 'check_origin; echo atteint'
  assert_eq 1 "$rc" "check_origin refuse sans dépôt canonique"
  assert_contains "gitea_configure n'a pas été appelé" "$err" "le message dit pourquoi"
  adaptateur "$work/depot" 'gitea_configure; echo atteint'
  assert_eq 1 "$rc" "gitea_configure refuse sans workflow.config chargé"
}

case_base_d_une_pr() {
  . "$common/gitea/gitea.sh"
  run branch_base feat/12-3-essai dev main "feat fix chore docs"
  assert_eq 0 "$rc" "préfixe admis"
  assert_eq dev "$out" "la base est forge.base"
  run branch_base refactor/x dev master "feat fix chore refactor perf test docs"
  assert_eq dev "$out" "les préfixes viennent de forge.branch-prefixes"
  run branch_base refactor/x dev main "feat fix chore docs"
  assert_eq 1 "$rc" "un préfixe non déclaré est refusé"
  assert_contains "Préfixes admis : feat/, fix/, chore/, docs/" "$out" "le refus liste les préfixes admis"
  run branch_base hotfix/x dev main "feat fix chore docs"
  assert_eq 1 "$rc" "hotfix/ n'est pas un préfixe déclaré"
  run branch_base feat/ dev main "feat"
  assert_eq 1 "$rc" "un préfixe sans nom de branche est refusé"
  run branch_base dev dev main "feat"
  assert_eq 1 "$rc" "aucune PR depuis la base"
  run branch_base main dev main "feat"
  assert_eq 1 "$rc" "aucune PR depuis la branche de publication"
  run branch_base release/v2 dev release/v2 "feat release"
  assert_eq 1 "$rc" "aucune PR depuis la branche de publication, même quand son nom porte un préfixe admis"
  assert_contains "branche de publication" "$out" "le refus le dit"
  run branch_base featx/y dev main "feat"
  assert_eq 1 "$rc" "un préfixe se lit jusqu'à « / », pas comme un début de mot"
  run branch_base feat/x main none "feat"
  assert_eq main "$out" "sans branche de publication, la base unique"
}

case_env_file_nomme_dans_le_message() {
  new_repo
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  adaptateur "$work/depot" 'load_gitea_env "$PWD/secrets.env"'
  assert_eq 1 "$rc" "un fichier d'environnement absent arrête"
  assert_contains "secrets.env absent (forge.env-file)" "$err" "le message nomme le fichier déclaré"
}

run_case "$@"
