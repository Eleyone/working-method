#!/usr/bin/env bash
# Lecture du suivi de sprint (scripts/lib/sprint.sh) : constat D4 de la rétrospective de l'epic 0.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$root/scripts/lib/sprint.sh"

# Suivi minimal : les sections après development_status réutilisent des clés de story.
suivi() {
  cat > "$work/suivi.yaml" <<'EOF'
generated: 09-13-2026 22:58
development_status:
  epic-0: in-progress
  0-1-premiere-story: done
  0-8-dev-tooling-hardening: review
  0-10-dixieme-story: backlog
  epic-0-retrospective: done
work_order:
  - 0-8-dev-tooling-hardening
blocked_by_open_questions:
  9-9-bloquee-ailleurs: [Q2]
EOF
}

case_cle_presente() {
  suivi
  run sprint_story_key 0.8 < "$work/suivi.yaml"
  assert_eq 0 "$rc" "code de retour"
  assert_eq 0-8-dev-tooling-hardening "$out" "clé trouvée"
}

case_cle_absente() {
  suivi
  run sprint_story_key 0.9 < "$work/suivi.yaml"
  assert_eq 1 "$rc" "code de retour"
  assert_eq "" "$out" "rien sur la sortie standard"
}

case_cle_hors_de_development_status() {
  suivi
  run sprint_story_key 9.9 < "$work/suivi.yaml"
  assert_eq 1 "$rc" "une clé des sections suivantes ne compte pas"
}

case_cle_sans_confusion_de_prefixe() {
  suivi
  run sprint_story_key 0.1 < "$work/suivi.yaml"
  assert_eq 0 "$rc" "code de retour"
  assert_eq 0-1-premiere-story "$out" "0.1 ne trouve pas 0-10-…"
}

case_cle_en_double() {
  printf 'development_status:\n  0-8-premiere: done\n  0-8-seconde: review\n' > "$work/suivi.yaml"
  run sprint_story_key 0.8 < "$work/suivi.yaml"
  assert_eq 2 "$rc" "code de retour"
  assert_eq "" "$out" "rien sur la sortie standard"
}

case_numero_illisible() {
  suivi
  run sprint_story_key 0-8 < "$work/suivi.yaml"
  assert_eq 2 "$rc" "numéro qui n'est pas de la forme n.m"
}

case_statut_simple() {
  suivi
  run sprint_story_status 0-8-dev-tooling-hardening < "$work/suivi.yaml"
  assert_eq 0 "$rc" "code de retour"
  assert_eq review "$out" "statut"
}

case_statut_guillemets_commentaire_indentation() {
  printf 'development_status:\n    0-8-x: "done"   # fini\n' > "$work/suivi.yaml"
  run sprint_story_status 0-8-x < "$work/suivi.yaml"
  assert_eq 0 "$rc" "code de retour"
  assert_eq done "$out" "statut sans guillemets ni commentaire"
}

case_statut_crlf() {
  printf 'development_status:\r\n  0-8-x: done\r\n' > "$work/suivi.yaml"
  run sprint_story_status 0-8-x < "$work/suivi.yaml"
  assert_eq 0 "$rc" "code de retour"
  assert_eq done "$out" "statut sans retour chariot"
}

case_statut_sur_plusieurs_lignes() {
  printf 'development_status:\n  0-8-x: |\n    done\n' > "$work/suivi.yaml"
  run sprint_story_status 0-8-x < "$work/suivi.yaml"
  assert_eq 2 "$rc" "bloc YAML sur plusieurs lignes"
  assert_eq "" "$out" "rien sur la sortie standard"
  printf 'development_status:\n  0-8-x:\n    done\n' > "$work/suivi.yaml"
  run sprint_story_status 0-8-x < "$work/suivi.yaml"
  assert_eq 2 "$rc" "valeur vide sur la ligne de la clé"
}

case_statut_absent() {
  suivi
  run sprint_story_status 0-9-inconnue < "$work/suivi.yaml"
  assert_eq 1 "$rc" "code de retour"
}

case_statut_cle_en_double() {
  printf 'development_status:\n  0-8-x: done\n  0-8-x: review\n' > "$work/suivi.yaml"
  run sprint_story_status 0-8-x < "$work/suivi.yaml"
  assert_eq 2 "$rc" "clé en double"
}

case_numero_de_branche() {
  run story_number_from_branch chore/0-7-verify-and-merge-pr-skill
  assert_eq 0 "$rc" "code de retour"
  assert_eq 0.7 "$out" "numéro simple"
  run story_number_from_branch feat/12-3a-story-suffixee
  assert_eq 12.3a "$out" "numéro suffixé"
  run story_number_from_branch docs/epic-0-retrospective
  assert_eq 1 "$rc" "branche sans numéro"
  run story_number_from_branch main
  assert_eq 1 "$rc" "branche sans préfixe"
}

run_case "$@"
