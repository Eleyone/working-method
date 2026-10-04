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
  # shellcheck disable=SC2016 # contrôle factice écrit dans un fichier : ses « $ » s'y développent à l'exécution
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

case_check_dossier_vide_le_dit() {
  # aucun contrôle et aucun préfixe : deux tableaux vides, que bash 4.3 sous set -u tenait pour non
  # définis (constaté en rejouant la suite sous bash 4.3.48, phase C de la story outillage-14)
  faux_depot
  lance
  assert_eq 0 "$rc" "un dossier sans contrôle n'est pas une anomalie (messages : $err)"
  assert_contains "aucun script de contrôle" "$out" "et le mécanisme le dit"
}

case_check_racine_donnee_hors_d_un_depot_git() {
  # Un projet peut lancer ses contrôles dans le contexte de build d'une image, sans .git : la racine
  # est alors donnée par l'appelant, jamais devinée.
  faux_depot
  rm -rf "$work/faux/.git"
  controle a 0
  mkdir -p "$work/ailleurs"
  run bash -c 'cd "$1" && bash "$2/checks/run-checks.sh" --root "$2" -- env ENVELOPPE=oui' _ "$work/ailleurs" "$work/faux"
  assert_eq 0 "$rc" "les contrôles tournent sans dépôt git (messages : $err)"
  assert_eq "niveau=absent enveloppe=oui a" "$(cat "$work/faux/controles.log")" "le contrôle tourne, sous le préfixe"
}

case_check_racine_dont_le_nom_commence_par_un_tiret() {
  # un nom de dossier qui commence par « - » est un dossier, jamais une option de cd
  faux_depot
  controle a 0
  ln -s "$work/faux" "$work/-faux"
  run bash -c 'cd "$1" && bash "$2/checks/run-checks.sh" --root -faux' _ "$work" "$work/faux"
  assert_eq 0 "$rc" "la racine « -faux » est lue comme un dossier (messages : $err)"
  assert_eq "niveau=absent enveloppe=non a" "$(cat "$work/faux/controles.log")" "le contrôle tourne"
  # « - » seul : « cd -- - » mènerait à $OLDPWD ; c'est ici un dossier comme un autre
  rm "$work/faux/controles.log"
  ln -s "$work/faux" "$work/-"
  run bash -c 'cd "$1" && bash "$2/checks/run-checks.sh" --root -' _ "$work" "$work/faux"
  assert_eq 0 "$rc" "la racine « - » est lue comme un dossier (messages : $err)"
  assert_eq "niveau=absent enveloppe=non a" "$(cat "$work/faux/controles.log")" "le contrôle tourne dans « - »"
}

case_check_sans_git_ni_racine_rend_2() {
  faux_depot
  rm -rf "$work/faux/.git"
  controle a 0
  lance
  assert_eq 2 "$rc" "hors d'un dépôt git et sans --root : aucune racine n'est devinée"
  assert_contains "ou avec --root" "$err" "le message dit comment donner la racine"
  [[ ! -e $work/faux/controles.log ]] || { echo "un contrôle a tourné sans racine" >&2; exit 1; }
}

case_check_racine_invalide_rend_2() {
  faux_depot
  controle a 0
  lance --root "$work/absent"
  assert_eq 2 "$rc" "racine introuvable : code 2"
  assert_contains "racine du projet introuvable" "$err" "le message nomme la racine"
  lance --root
  assert_eq 2 "$rc" "--root sans dossier : code 2"
  lance --root ""
  assert_eq 2 "$rc" "--root vide : code 2, jamais le dossier courant"
  lance --root "$work/faux" --root "$work/faux"
  assert_eq 2 "$rc" "--root deux fois : code 2"
  [[ ! -e $work/faux/controles.log ]] || { echo "un contrôle a tourné malgré une racine refusée" >&2; exit 1; }
  # « cd -- » seul mène au dossier personnel : « --root -- » ne doit jamais y conduire, même quand ce
  # dossier est un projet valide (ici le faux dépôt lui-même, où le contrôle a tournerait)
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run env HOME="$work/faux" bash -c 'cd "$1" && shift && bash checks/run-checks.sh "$@"' _ "$work/faux" --root --
  assert_eq 2 "$rc" "--root -- : code 2, jamais le dossier personnel"
  assert_contains "racine du projet introuvable : --" "$err" "le message nomme la racine refusée"
  [[ ! -e $work/faux/controles.log ]] || { echo "un contrôle a tourné malgré une racine refusée" >&2; exit 1; }
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
