#!/usr/bin/env bash
# Lecture du suivi de sprint (lib/sprint.sh) : constat D4 de la rétrospective de l'epic 0 du projet source.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$common/lib/sprint.sh"

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
  assert_eq "done" "$out" "statut sans guillemets ni commentaire"
}

case_statut_crlf() {
  printf 'development_status:\r\n  0-8-x: done\r\n' > "$work/suivi.yaml"
  run sprint_story_status 0-8-x < "$work/suivi.yaml"
  assert_eq 0 "$rc" "code de retour"
  assert_eq "done" "$out" "statut sans retour chariot"
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

case_convention_servie() {
  run sprint_convention_served numbered
  assert_eq 0 "$rc" "numbered est servie"
  run sprint_convention_served none
  assert_eq 1 "$rc" "none désactive le suivi"
  run sprint_convention_served keyed
  assert_eq 0 "$rc" "keyed est servie (calculette#outillage-5)"
  assert_eq "" "$out" "rien à dire d'une convention servie"
  run sprint_convention_served autre
  assert_eq 2 "$rc" "une convention inconnue n'est jamais lue comme numbered"
}

# --- convention keyed (calculette#outillage-5) : clés kebab-case, bloc aliases:, epics non numérotés -----

# Suivi keyed à la forme du suivi d'origine (calculette#outillage-5) : commentaires de fin de ligne, bloc aliases: avant
# development_status, epics nommés.
suivi_keyed() {
  cat > "$work/suivi.yaml" <<'YAML'
# commentaire d'en-tête
aliases:
  i-2-stripe-checkout: i-2-stripe-checkout-forfait-mensuel
  # une ligne de commentaire dans le bloc
  ancien-nom: fix-renomme
development_status:
  epic-a: done
  i-2-stripe-checkout-forfait-mensuel: done  # décision
  fix-plafond-pagination: review
  fix-renomme: in-progress
  outillage-4-trois-codes: done
  epic-a-retrospective: optional
YAML
}

case_bloc_aliases_lu() {
  suivi_keyed
  run sprint_block aliases < "$work/suivi.yaml"
  assert_eq 0 "$rc" "code de retour"
  assert_eq $'i-2-stripe-checkout\ti-2-stripe-checkout-forfait-mensuel\nancien-nom\tfix-renomme' "$out" "deux alias, commentaire ignoré"
}

case_bloc_development_status_comme_sprint_entries() {
  suivi_keyed
  local a b
  a=$(sprint_block development_status < "$work/suivi.yaml")
  b=$(sprint_entries < "$work/suivi.yaml")
  assert_eq "$b" "$a" "sprint_entries est le bloc development_status"
}

keyed_tables() { # remplit entries et aliases depuis le suivi keyed
  suivi_keyed
  entries=$(sprint_entries < "$work/suivi.yaml")
  aliases=$(sprint_block aliases < "$work/suivi.yaml")
}

case_keyed_resolution_directe_et_par_alias() {
  keyed_tables
  run sprint_keyed_resolve fix-plafond-pagination "$entries" "$aliases"
  assert_eq 0 "$rc" "clé directe"
  assert_eq fix-plafond-pagination "$out" "clé directe rendue"
  run sprint_keyed_resolve i-2-stripe-checkout "$entries" "$aliases"
  assert_eq 0 "$rc" "alias"
  assert_eq i-2-stripe-checkout-forfait-mensuel "$out" "cible de l'alias rendue"
  run sprint_keyed_resolve inconnu "$entries" "$aliases"
  assert_eq 1 "$rc" "ni clé ni alias"
  assert_eq "" "$out" "rien sur la sortie standard"
}

case_keyed_resolution_ambigue() {
  keyed_tables
  aliases+=$'\nfix-plafond-pagination\tfix-renomme'
  run sprint_keyed_resolve fix-plafond-pagination "$entries" "$aliases"
  assert_eq 2 "$rc" "clé directe ET alias : rattachement ambigu"
  assert_eq "" "$out" "rien sur la sortie standard"
}

case_keyed_statut_d_en_tete() {
  local texte attendu
  while IFS='|' read -r texte attendu; do
    run sprint_keyed_header_status <<< "$(printf '%b' "$texte")"
    assert_eq 0 "$rc" "en-tête lu : $texte"
    assert_eq "$attendu" "$out" "statut de : $texte"
  done <<'CAS'
# Titre\n\nStatus: review\n|review
Status: done  # clos le 2026-08-05\n|done
status: 'done'\n|done
**Status**: in-progress\n|in-progress
Status: Backlog\nStatus: done\n|done
CAS
  run sprint_keyed_header_status <<< $'# Titre\n\n  Status: done\nPas de statut'
  assert_eq 1 "$rc" "une ligne indentée n'est pas un en-tête"
  assert_eq "" "$out" "rien sur la sortie standard"
}

case_keyed_fichiers_qui_ne_sont_pas_des_stories() {
  local nom
  for nom in deferred-work spec-securiser epic-e-retro-2026-07-21 ae-1b-t2-t3-prompt; do
    run sprint_is_non_story "$nom" "deferred-work spec-* spike-* *retro* *-prompt"
    assert_eq 0 "$rc" "$nom n'est pas une story"
  done
  for nom in fix-plafond deferred-work-2 prompt-x; do
    run sprint_is_non_story "$nom" "deferred-work spec-* spike-* *retro* *-prompt"
    assert_eq 1 "$rc" "$nom est une story"
  done
  run sprint_is_non_story deferred-work none
  assert_eq 1 "$rc" "none : tout fichier est une story"
}

case_keyed_story_de_la_branche() {
  suivi_keyed
  run sprint_keyed_story_from_branch fix/plafond-pagination < "$work/suivi.yaml"
  assert_eq 0 "$rc" "préfixe recollé : fix/plafond-pagination → fix-plafond-pagination"
  assert_eq $'fix-plafond-pagination\tfix-plafond-pagination' "$out" "clé et nom du fichier"
  run sprint_keyed_story_from_branch feat/outillage-4-trois-codes < "$work/suivi.yaml"
  assert_eq 0 "$rc" "préfixe retiré : feat/outillage-4-trois-codes → outillage-4-trois-codes"
  assert_eq $'outillage-4-trois-codes\toutillage-4-trois-codes' "$out" "clé et nom du fichier"
  run sprint_keyed_story_from_branch feat/i-2-stripe-checkout < "$work/suivi.yaml"
  assert_eq 0 "$rc" "par alias"
  assert_eq $'i-2-stripe-checkout-forfait-mensuel\ti-2-stripe-checkout' "$out" "la clé, et le fichier qui porte l'alias"
  run sprint_keyed_story_from_branch chore/renovate-x < "$work/suivi.yaml"
  assert_eq 1 "$rc" "aucune story pour cette branche"
  assert_eq "" "$out" "rien sur la sortie standard"
  run sprint_keyed_story_from_branch dev < "$work/suivi.yaml"
  assert_eq 1 "$rc" "branche sans préfixe"
  run sprint_keyed_story_from_branch fix/Majuscules < "$work/suivi.yaml"
  assert_eq 1 "$rc" "nom de branche hors kebab-case"
}

case_keyed_motifs_jamais_etendus_aux_fichiers_du_dossier_courant() {
  # Un « spec-* » découpé par le shell s'étendrait à « spec-autre » s'il existe dans le dossier courant,
  # et « spec-securiser » ne serait plus exclu.
  mkdir -p "$work/ici"
  : > "$work/ici/spec-autre"
  : > "$work/ici/deferred-work.md"
  (cd "$work/ici" && sprint_is_non_story spec-securiser "deferred-work spec-*") \
    || { echo "spec-securiser n'est plus exclu quand le dossier courant contient spec-autre" >&2; exit 1; }
  (cd "$work/ici" && sprint_is_non_story deferred-work "deferred-* spec-*") \
    || { echo "deferred-work n'est plus exclu quand le dossier courant contient deferred-work.md" >&2; exit 1; }
}

case_keyed_branche_d_epic_sans_story() {
  suivi_keyed
  run sprint_keyed_story_from_branch chore/epic-a < "$work/suivi.yaml"
  assert_eq 1 "$rc" "une clé d'epic n'est pas une story : contrôle global"
  assert_eq "" "$out" "rien sur la sortie standard"
  run sprint_keyed_story_from_branch docs/epic-a-retrospective < "$work/suivi.yaml"
  assert_eq 1 "$rc" "une rétrospective n'est pas une story"
}

case_keyed_story_de_la_branche_ambigue() {
  suivi_keyed
  printf '  fix-x: review\n  x: review\n' >> "$work/suivi.yaml"
  run sprint_keyed_story_from_branch fix/x < "$work/suivi.yaml"
  assert_eq 2 "$rc" "fix-x et x sont deux stories : ambigu"
  assert_eq "" "$out" "rien sur la sortie standard"
}

run_case "$@"
