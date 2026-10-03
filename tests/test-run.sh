#!/usr/bin/env bash
# Lanceur des tests (rétrospective de l'epic 2, F1) : la suite ne touche jamais public/ ni build/ du dépôt.
# Hors ligne : run.sh et lib.sh sont copiés dans un faux dépôt, avec un fichier de test d'essai.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

faux_depot() { # $1 = corps du cas d'essai ; prépare $work/faux avec un public/ témoin
  mkdir -p "$work/faux/scripts/tests" "$work/faux/scripts/lib" "$work/faux/public"
  cp "$root/scripts/tests/run.sh" "$root/scripts/tests/lib.sh" "$work/faux/scripts/tests/"
  # lib.sh charge les enveloppes communes du dépôt : le faux dépôt les emporte aussi
  cp "$root/scripts/lib/shell.sh" "$work/faux/scripts/lib/"
  : > "$work/faux/public/index.html"
  printf '#!/usr/bin/env bash\n. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"\ncase_essai() {\n  %s\n}\nrun_case "$@"\n' "$1" \
    > "$work/faux/scripts/tests/test-essai.sh"
}

case_run_accepte_une_suite_qui_ne_touche_pas_les_sorties() {
  faux_depot 'true'
  run bash "$work/faux/scripts/tests/run.sh"
  assert_eq 0 "$rc" "suite sans effet sur public/ (messages : $err)"
  assert_contains "1 cas réussis" "$out" "le cas est compté"
}

case_run_refuse_une_suite_qui_efface_public() {
  faux_depot 'rm -rf "$root/public"'
  run bash "$work/faux/scripts/tests/run.sh"
  assert_eq 1 "$rc" "une suite qui efface public/ échoue"
  assert_contains "a modifié public/ ou build/" "$err" "le message nomme les sorties touchées"
}

case_run_refuse_une_suite_qui_cree_build() {
  faux_depot 'mkdir -p "$root/build/work"'
  run bash "$work/faux/scripts/tests/run.sh"
  assert_eq 1 "$rc" "une suite qui crée build/ échoue"
}

run_case "$@"
