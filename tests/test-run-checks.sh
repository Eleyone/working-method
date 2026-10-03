#!/usr/bin/env bash
# Mécanisme des contrôles (checks/run-checks.sh, extrait du point d'entrée de la story 3.2 du projet
# source) : découverte, cumul, codes de sortie. Hors ligne : run-checks.sh et le lecteur de
# workflow.config sont copiés dans un faux dépôt git, avec des contrôles d'essai.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

faux_depot() { # $1… = changements du workflow.config ; prépare $work/faux : dossier de contrôles vide
  mkdir -p "$work/faux/scripts/checks" "$work/faux/checks" "$work/faux/lib"
  cp "$common/checks/run-checks.sh" "$work/faux/checks/"
  cp "$common/lib/config.sh" "$work/faux/lib/"
  # un lib.sh de contrôles, comme en porte le projet source : il n'est pas un contrôle
  printf '# bibliothèque des contrôles\nexit 1\n' > "$work/faux/scripts/checks/lib.sh"
  git -C "$work/faux" init -q
  write_workflow_config "$work/faux" "$@"
}

controle() { # $1 = nom, $2 = code de sortie ; écrit un signalement au format commun
  printf '#!/usr/bin/env bash\necho "contenu/%s.md: écart de %s" >&2\necho "niveau=${CHECK_LEVEL:-absent} enveloppe=${ENVELOPPE:-non} %s" >> "%s/faux/controles.log"\nexit %s\n' \
    "$1" "$1" "$1" "$work" "$2" > "$work/faux/scripts/checks/$1.sh"
}

lance() { run bash -c 'cd "$1" && shift && bash checks/run-checks.sh "$@"' _ "$work/faux" "$@"; }

case_check_cumule_les_echecs() {
  faux_depot
  controle a 1
  controle b 1
  controle c 0
  lance
  assert_eq 1 "$rc" "un écart rend 1"
  assert_contains "contenu/a.md: écart de a" "$err" "le premier écart est affiché"
  assert_contains "contenu/b.md: écart de b" "$err" "le contrôle suivant tourne quand même"
  assert_contains "2 contrôle(s) en échec sur 3 : a b" "$err" "le résumé nomme les contrôles en échec"
}

case_check_anomalie_rend_2() {
  faux_depot
  controle a 2
  lance
  assert_eq 2 "$rc" "une anomalie rend 2"
  assert_contains "a (code 2)" "$err" "le résumé nomme le code"
}

case_check_ignore_lib_et_trie() {
  faux_depot
  controle b 0
  controle a 0
  lance
  assert_eq 0 "$rc" "lib.sh n'est pas un contrôle (messages : $err)"
  assert_eq "niveau=absent enveloppe=non a
niveau=absent enveloppe=non b" "$(cat "$work/faux/controles.log")" "les contrôles tournent triés, sans lib.sh"
  assert_contains "2 contrôle(s) passés." "$out" "le résumé compte les contrôles"
}

case_check_option_inconnue() {
  faux_depot
  controle a 0
  lance --inconnue
  assert_eq 2 "$rc" "une option inconnue est une anomalie"
  assert_contains "option inconnue" "$err" "le message nomme l'option"
  [[ ! -e $work/faux/controles.log ]] || { echo "un contrôle a tourné malgré l'option inconnue" >&2; exit 1; }
}

case_check_niveau_et_enveloppe_transmis() {
  # Le niveau et le chargeur de valeurs appartiennent au projet : le mécanisme les transmet sans les connaître.
  faux_depot
  controle a 0
  run bash -c 'cd "$1" && CHECK_LEVEL=release bash checks/run-checks.sh -- env ENVELOPPE=oui' _ "$work/faux"
  assert_eq 0 "$rc" "le préfixe est accepté (messages : $err)"
  assert_eq "niveau=release enveloppe=oui a" "$(cat "$work/faux/controles.log")" "le contrôle tourne sous le préfixe, au niveau posé"
  assert_contains "niveau release" "$out" "le résumé nomme le niveau"
}

case_check_dossier_lu_dans_workflow_config() {
  faux_depot checks.dir=controles
  mkdir -p "$work/faux/controles"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$work/faux/controles/x.sh"
  controle a 0
  lance
  assert_eq 1 "$rc" "les contrôles du dossier déclaré tournent, pas ceux d'un autre"
  assert_contains "1 contrôle(s) en échec sur 1 : x" "$err" "seul le dossier déclaré est lu"
}

case_check_desactive_le_dit() {
  faux_depot checks.dir=none
  controle a 1
  lance
  assert_eq 0 "$rc" "checks.dir = none : aucun contrôle (messages : $err)"
  assert_contains "aucun dossier de contrôles (checks.dir = none)" "$out" "et le script le dit"
}

case_check_dossier_introuvable() {
  faux_depot checks.dir=absent
  lance
  assert_eq 2 "$rc" "un dossier déclaré mais absent est une anomalie, pas une conformité"
  assert_contains "introuvable" "$err" "le message le dit"
}

case_check_workflow_config_refuse() {
  faux_depot -checks.dir
  controle a 0
  lance
  assert_eq 2 "$rc" "sans checks.dir, aucun contrôle n'est lancé"
  assert_contains "checks.dir : champ absent" "$err" "le champ manquant est nommé"
}

run_case "$@"
