#!/usr/bin/env bash
# bin/install et bin/check-bash : prérequis bash vérifié avant tout bash (AC 9 de la story
# outillage-14), liens de l'outillage et des skills posés sans rien écraser, et réinstallation sans effet.
# Hors ligne : le dépôt commun est recopié dans un dépôt git jetable, consommé en sous-module par un
# projet fixture.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Le dépôt commun jetable : bin/, lib/ et skills/ suffisent à l'installation.
commun_jetable() {
  mkdir -p "$work/commun"
  cp -R "$common/bin" "$common/lib" "$common/skills" "$work/commun/"
  git -C "$work/commun" init -q
  git -C "$work/commun" add -A
  git -C "$work/commun" -c user.name=essai -c user.email=essai@example.invalid -c core.hooksPath=/dev/null \
    commit -q -m commun
}

# Le projet fixture : le dépôt commun en sous-module sous outils/commun, et un workflow.config.
projet() { # $1… = changements du workflow.config
  commun_jetable
  new_repo
  git -C "$work/depot" -c protocol.file.allow=always submodule add -q "$work/commun" outils/commun 2>/dev/null
  write_workflow_config "$work/depot" "agents.skill-dirs=.claude/skills .agents/skills" "$@"
}

installe() { run bash -c 'cd "$1" && sh outils/commun/bin/install' _ "$work/depot"; }

# État des liens et des dossiers posés, pour comparer deux installations.
etat() {
  (cd "$work/depot" && find .working-method .claude .agents -print 2>/dev/null | LC_ALL=C sort \
    | while IFS= read -r p; do if [[ -L $p ]]; then printf '%s -> %s\n' "$p" "$(readlink "$p")"; else printf '%s\n' "$p"; fi; done)
}

case_install_pose_les_liens() {
  projet
  installe
  assert_eq 0 "$rc" "installation (messages : $err)"
  assert_eq outils/commun "$(readlink "$work/depot/.working-method")" "le point d'entrée désigne le sous-module"
  assert_eq ../../outils/commun/skills/llm-review "$(readlink "$work/depot/.claude/skills/llm-review")" "lien relatif d'un skill"
  local skill dir
  for dir in .claude/skills .agents/skills; do
    for skill in create-pull-request llm-review sprint-consistency verify-and-merge-pr; do
      [[ -f $work/depot/$dir/$skill/SKILL.md ]] || { echo "$dir/$skill/SKILL.md ne se lit pas à travers le lien" >&2; exit 1; }
    done
  done
  [[ -x $work/depot/.working-method/gates/verify-and-merge-pr.sh || -f $work/depot/.working-method/bin/install ]] \
    || { echo "l'outillage ne se lit pas à travers .working-method" >&2; exit 1; }
  assert_contains "réservée à la story 1, rien n’est installé" "$out" "la place de BMAD est dite, rien n'est installé"
}

case_install_relancee_ne_change_rien() {
  projet
  installe
  local avant
  avant=$(etat)
  installe
  assert_eq 0 "$rc" "seconde installation (messages : $err)"
  assert_eq "$avant" "$(etat)" "la seconde installation ne change rien"
  assert_contains "0 lien(s) posé(s), 9 déjà en place" "$out" "et elle le dit"
}

case_install_refuse_d_ecraser() {
  # Un skill homonyme du projet (cas de la story 15) : rien n'est écrasé, et rien d'autre n'est posé.
  projet
  mkdir -p "$work/depot/.claude/skills/llm-review"
  printf 'skill du projet\n' > "$work/depot/.claude/skills/llm-review/SKILL.md"
  installe
  assert_eq 1 "$rc" "un conflit rend 1"
  assert_contains ".claude/skills/llm-review : existe déjà et n'est pas un lien" "$err" "le conflit est nommé"
  assert_eq "skill du projet" "$(cat "$work/depot/.claude/skills/llm-review/SKILL.md")" "le skill du projet est intact"
  [[ ! -e $work/depot/.working-method && ! -L $work/depot/.working-method ]] \
    || { echo "un lien a été posé malgré le conflit" >&2; exit 1; }
}

case_install_lien_etranger_est_un_conflit() {
  projet
  mkdir -p "$work/depot/.agents/skills"
  ln -s ailleurs "$work/depot/.agents/skills/sprint-consistency"
  installe
  assert_eq 1 "$rc" "un lien vers une autre cible n'est pas « déjà en place »"
  assert_contains "lien vers « ailleurs »" "$err" "le message nomme la cible trouvée"
}

case_install_sous_module_au_point_d_entree() {
  # Le sous-module placé directement à .working-method : aucun lien de plus n'est nécessaire.
  commun_jetable
  new_repo
  git -C "$work/depot" -c protocol.file.allow=always submodule add -q "$work/commun" .working-method 2>/dev/null
  write_workflow_config "$work/depot" "agents.skill-dirs=.claude/skills"
  run bash -c 'cd "$1" && sh .working-method/bin/install' _ "$work/depot"
  assert_eq 0 "$rc" "installation (messages : $err)"
  assert_eq ../../.working-method/skills/llm-review "$(readlink "$work/depot/.claude/skills/llm-review")" "lien relatif d'un skill"
}

case_install_workflow_config_refuse() {
  projet -agents.skill-dirs
  installe
  assert_eq 2 "$rc" "un workflow.config incomplet empêche l'installation"
  assert_contains "agents.skill-dirs : champ absent" "$err" "le champ est nommé"
  [[ ! -L $work/depot/.working-method ]] || { echo "un lien a été posé malgré le refus" >&2; exit 1; }
}

case_install_hors_sous_module() {
  commun_jetable
  run bash -c 'cd "$1" && sh bin/install' _ "$work/commun"
  assert_eq 2 "$rc" "le dépôt commun seul n'est pas un projet"
  assert_contains "n'est pas un sous-module" "$err" "le message le dit"
}

case_install_option_refusee() {
  projet
  run bash -c 'cd "$1" && sh outils/commun/bin/install --force' _ "$work/depot"
  assert_eq 2 "$rc" "aucune option n'est admise"
}

# PATH réduit : seuls les outils que le prélude POSIX emploie, et le bash voulu (ou aucun).
path_sans_bash() { # $1 = dossier à remplir
  mkdir -p "$1"
  ln -s "$(command -v dirname)" "$1/dirname"
}

case_check_bash_absent() {
  path_sans_bash "$work/bin"
  run env PATH="$work/bin" /bin/sh "$common/bin/check-bash"
  assert_eq 2 "$rc" "sans bash, le prérequis sort en 2"
  assert_contains "bash est introuvable" "$err" "le message est explicite"
  run env PATH="$work/bin" /bin/sh "$common/bin/install"
  assert_eq 2 "$rc" "bin/install aussi, avant toute ligne de bash"
  assert_contains "bash est introuvable" "$err" "avec le même message"
}

case_check_bash_trop_ancien() {
  path_sans_bash "$work/bin"
  printf '#!/bin/sh\nprintf "4 2"\n' > "$work/bin/bash"
  chmod +x "$work/bin/bash"
  run env PATH="$work/bin" /bin/sh "$common/bin/check-bash"
  assert_eq 2 "$rc" "bash 4.2 est refusé"
  assert_contains "bash 4.2 trouvé" "$err" "le message nomme la version trouvée"
  assert_contains "4.3 ou plus est requis" "$err" "et la version requise"
  run env PATH="$work/bin" /bin/sh "$common/bin/install"
  assert_eq 2 "$rc" "bin/install refuse aussi bash 4.2"
}

case_check_bash_versions_admises() {
  path_sans_bash "$work/bin"
  local version
  for version in "4 3" "4 4" "5 0" "10 0"; do
    printf '#!/bin/sh\nprintf "%s"\n' "$version" > "$work/bin/bash"
    chmod +x "$work/bin/bash"
    run env PATH="$work/bin" /bin/sh -c '. "$1/lib/require-bash.sh"; require_bash' _ "$common"
    assert_eq 0 "$rc" "bash $version est admis (messages : $err)"
  done
  for version in "3 2" "4 0" "" "x y" "5"; do
    printf '#!/bin/sh\nprintf "%s"\n' "$version" > "$work/bin/bash"
    chmod +x "$work/bin/bash"
    run env PATH="$work/bin" /bin/sh -c '. "$1/lib/require-bash.sh"; require_bash' _ "$common"
    assert_eq 2 "$rc" "réponse « $version » refusée"
  done
}

run_case "$@"
