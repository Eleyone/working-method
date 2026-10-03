#!/usr/bin/env bash
# Point d'entrée des contrôles (story 3.2) : ordre des builds, découverte, cumul, codes de sortie.
# Hors ligne : check.sh est copié dans un faux dépôt, avec un build.sh bouchonné et des contrôles
# d'essai. Le vrai build est exercé par les essais de la story, pas ici.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

faux_depot() { # prépare $work/faux : check.sh réel, build.sh bouchonné, dossier de contrôles vide
  mkdir -p "$work/faux/scripts/checks" "$work/faux/scripts/lib"
  cp "$root/scripts/check.sh" "$work/faux/scripts/"
  cp "$root/scripts/checks/lib.sh" "$work/faux/scripts/checks/"
  cp "$root/scripts/lib/shell.sh" "$root/scripts/lib/text.sh" "$work/faux/scripts/lib/"
  # Le chargeur unique et sa bibliothèque : check.sh lance chaque contrôle par lui depuis la story
  # 9.1, sans quoi aucun contrôle ne verrait un HUGO_LEGAL_* (AD-9). Une fixture qui ne le porte pas
  # ne ressemble plus au dépôt qu'elle imite (point 16 d'AGENTS.md).
  cp "$root/scripts/env.sh" "$work/faux/scripts/"
  cp "$root/scripts/lib/dotenv.sh" "$work/faux/scripts/lib/"
  mkdir -p "$work/faux/ci"
  cp "$root/ci/legal-placeholder.env" "$work/faux/ci/"
  : > "$work/faux/build.log"
  printf '#!/usr/bin/env bash\necho "$1" >> "%s/faux/build.log"\n[ "${BUILD_FAIL:-}" != "$1" ] || { echo "hugo: avertissement" >&2; exit 1; }\n' "$work" \
    > "$work/faux/scripts/build.sh"
  chmod +x "$work/faux/scripts/build.sh"
}

controle() { # $1 = nom, $2 = code de sortie ; écrit un signalement au format commun
  printf '#!/usr/bin/env bash\necho "contenu/%s.md: écart de %s" >&2\necho "niveau=${CHECK_LEVEL:-absent} %s" >> "%s/faux/controles.log"\nexit %s\n' \
    "$1" "$1" "$1" "$work" "$2" > "$work/faux/scripts/checks/$1.sh"
}

case_check_cumule_les_echecs() {
  faux_depot
  controle a 1
  controle b 1
  controle c 0
  run bash "$work/faux/scripts/check.sh"
  assert_eq 1 "$rc" "un écart rend 1"
  assert_contains "contenu/a.md: écart de a" "$err" "le premier écart est affiché"
  assert_contains "contenu/b.md: écart de b" "$err" "le contrôle suivant tourne quand même"
  assert_contains "2 contrôle(s) en échec sur 3 : a b" "$err" "le résumé nomme les contrôles en échec"
}

case_check_anomalie_rend_2() {
  faux_depot
  controle a 2
  run bash "$work/faux/scripts/check.sh"
  assert_eq 2 "$rc" "une anomalie rend 2"
  assert_contains "a (code 2)" "$err" "le résumé nomme le code"
}

case_check_ignore_lib_et_trie() {
  faux_depot
  controle b 0
  controle a 0
  run bash "$work/faux/scripts/check.sh"
  assert_eq 0 "$rc" "lib.sh n'est pas un contrôle (messages : $err)"
  assert_eq "niveau=standard a
niveau=standard b" "$(cat "$work/faux/controles.log")" "les contrôles tournent triés, sans lib.sh"
}

case_check_option_inconnue() {
  faux_depot
  run bash "$work/faux/scripts/check.sh" --inconnue
  assert_eq 2 "$rc" "une option inconnue est une anomalie"
  assert_contains "option inconnue" "$err" "le message nomme l'option"
  [[ ! -s $work/faux/build.log ]] || { echo "un build a été lancé malgré l'option inconnue" >&2; exit 1; }
}

run_case "$@"
