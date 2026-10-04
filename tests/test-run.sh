#!/usr/bin/env bash
# Lanceur des tests (rétrospective de l'epic 2 du projet source, F1) : la suite ne touche jamais les
# sorties que le projet protège (tests.protected-outputs).
# Hors ligne : run.sh, lib.sh et les bibliothèques sont copiés dans un faux dépôt git, avec un fichier
# de test d'essai et un workflow.config.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

faux_depot() { # $1 = corps du cas d'essai, $2… = changements du workflow.config ; prépare $work/faux avec un public/ témoin
  local corps=$1
  shift
  mkdir -p "$work/faux/tests" "$work/faux/lib" "$work/faux/public"
  cp "$common/tests/run.sh" "$common/tests/lib.sh" "$work/faux/tests/"
  # lib.sh charge les enveloppes communes, run.sh le lecteur de workflow.config : le faux dépôt les emporte
  cp "$common/lib/shell.sh" "$common/lib/config.sh" "$work/faux/lib/"
  : > "$work/faux/public/index.html"
  # shellcheck disable=SC2016 # fichier de test factice écrit sur le disque : ses « $ » s'y développent à l'exécution
  printf '#!/usr/bin/env bash\n. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"\ncase_essai() {\n  %s\n}\nrun_case "$@"\n' "$corps" \
    > "$work/faux/tests/test-essai.sh"
  git -C "$work/faux" init -q
  write_workflow_config "$work/faux" "$@"
}

case_run_accepte_une_suite_qui_ne_touche_pas_les_sorties() {
  faux_depot 'true'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "suite sans effet sur public/ (messages : $err)"
  assert_contains "1 cas réussis" "$out" "le cas est compté"
}

case_run_refuse_une_suite_qui_efface_public() {
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'rm -rf "$root/public"'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "une suite qui efface public/ échoue"
  assert_contains "a modifié une sortie protégée du projet (public build)" "$err" "le message nomme les sorties protégées"
}

case_run_refuse_une_suite_qui_cree_build() {
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'mkdir -p "$root/build/work"'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "une suite qui crée build/ échoue"
}

case_run_sorties_lues_dans_workflow_config() {
  # Les sorties ne sont plus écrites dans le lanceur : un autre nom est protégé, public/ ne l'est plus.
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'mkdir -p "$root/dist"' "tests.protected-outputs=dist"
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "la sortie déclarée est protégée"
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'rm -rf "$root/public"' "tests.protected-outputs=dist"
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "une sortie non déclarée n'est pas relevée (messages : $err)"
}

case_run_none_le_dit() {
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'rm -rf "$root/public"' "tests.protected-outputs=none"
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "aucune sortie protégée : la suite passe (messages : $err)"
  assert_contains "aucune sortie protégée (tests.protected-outputs = none)" "$err" "et le lanceur le dit"
}

case_run_workflow_config_refuse() {
  faux_depot 'true' -tests.protected-outputs
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 2 "$rc" "un workflow.config incomplet empêche les tests de tourner"
  assert_contains "tests.protected-outputs : champ absent" "$err" "le champ manquant est nommé"
}

run_case "$@"
