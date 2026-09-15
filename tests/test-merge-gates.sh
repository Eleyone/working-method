#!/usr/bin/env bash
# Décisions des verrous de fusion (scripts/lib/merge-gates.sh) : constats D1, D5 et S5 de la rétrospective
# de l'epic 0, rapport retenu et règle du commit de statut.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$root/scripts/lib/merge-gates.sh"

readonly user=compte-essai

# Page <n> du scénario : le fichier de fixture s'il existe, sinon null, comme la forge au-delà de la fin.
# Chaque page demandée est notée dans $work/pages.
fetch_fixture() { # $1 numéro de page, $2 fichier de réponse
  local page_file="$fixtures/timeline/$scenario-$1.json"
  printf '%s\n' "$1" >> "$work/pages"
  if [[ -f $page_file ]]; then cp "$page_file" "$2"; else printf 'null\n' > "$2"; fi
}
fetch_always_full() { printf '%s\n' "$1" >> "$work/pages"; cp "$fixtures/timeline/pleine-1.json" "$2"; }
fetch_failing() { return 1; }

case_timeline_pages_pleines_puis_null() {
  scenario=pleine
  run read_timeline_reports fetch_fixture "$user" 2 100 "$work/rapports"
  assert_eq 0 "$rc" "code de retour"
  assert_eq "1 2 3" "$(tr '\n' ' ' < "$work/pages" | sed 's/ $//')" "pages lues, la troisième répondant null"
  assert_eq "llm-review sha=aaaaaaaa base=dev model=modele-essai verdict=block
llm-review sha=aaaaaaaa base=dev model=modele-essai verdict=pass" "$(cat "$work/rapports")" "rapports du compte seulement, dans l'ordre"
}

case_timeline_page_incomplete() {
  cp "$fixtures/timeline/pleine-1.json" "$work/incomplete-1.json"
  scenario=incomplete
  fetch_incomplete() { # page 1 pleine, page 2 d'un seul élément
    printf '%s\n' "$1" >> "$work/pages"
    if [[ $1 == 1 ]]; then cp "$work/incomplete-1.json" "$2"; else cp "$fixtures/timeline/incomplete-2.json" "$2"; fi
  }
  run read_timeline_reports fetch_incomplete "$user" 2 100 "$work/rapports"
  assert_eq 0 "$rc" "code de retour"
  assert_eq "1 2" "$(tr '\n' ' ' < "$work/pages" | sed 's/ $//')" "aucune page demandée après la page incomplète"
  assert_eq 1 "$(grep -c . "$work/rapports")" "un seul rapport"
}

case_timeline_plafond_de_pages() {
  run read_timeline_reports fetch_always_full "$user" 2 3 "$work/rapports"
  assert_eq 3 "$rc" "plafond atteint"
  assert_eq 3 "$(grep -c . "$work/pages")" "trois pages lues, pas une de plus"
}

case_timeline_page_illisible() {
  scenario=illisible
  run read_timeline_reports fetch_fixture "$user" 2 100 "$work/rapports"
  assert_eq 2 "$rc" "une page qui n'est ni une liste ni null"
}

case_timeline_lecture_impossible() {
  run read_timeline_reports fetch_failing "$user" 2 100 "$work/rapports"
  assert_eq 2 "$rc" "la fonction de lecture échoue"
}

case_rapport_retenu() {
  cat > "$work/rapports" <<'EOF'
llm-review sha=aaa base=dev model=m verdict=pass
llm-review sha=aaa base=dev model=m verdict=block
llm-review sha=aaa base=main model=m verdict=pass
llm-review sha=bbb base=dev model=m verdict=block
llm-review sha=bbb base=dev model=m verdict=pass
llm-review sha=aaa base=dev model= verdict=pass
llm-review sha=aaa base=dev model=m verdict=pass en trop
llm-review sha=aaa base=dev model=m verdict=peut-etre
EOF
  run last_report "$work/rapports" aaa dev
  assert_eq "llm-review sha=aaa base=dev model=m verdict=block" "$out" "un block plus récent qu'un pass l'emporte ; lignes mal formées ignorées"
  run last_report "$work/rapports" bbb dev
  assert_eq "llm-review sha=bbb base=dev model=m verdict=pass" "$out" "un pass plus récent qu'un block l'emporte"
  run last_report "$work/rapports" aaa feat/autre
  assert_eq "" "$out" "autre base"
  run last_report "$work/rapports" ccc dev
  assert_eq "" "$out" "autre SHA"
}

ci_case() { # $1 état, $2 nombre de statuts, $3 workflow sur la base, $4 décision attendue, $5 libellé
  printf '{"state": "%s", "total_count": %s}\n' "$1" "$2" > "$work/ci.json"
  run ci_gate "$work/ci.json" "$3" .gitea/workflows/checks.yaml
  assert_eq 0 "$rc" "$5 : code de retour"
  assert_eq "$4" "${out%%$'\t'*}" "$5"
}

case_verrou_ci() {
  ci_case success 2 0 passe "CI verte"
  ci_case pending 2 0 bloque "CI en cours pendant l'amorçage (S5)"
  ci_case pending 2 1 bloque "CI en cours, workflow sur la base"
  ci_case failure 1 0 bloque "CI en échec"
  ci_case error 1 1 bloque "CI en erreur"
  ci_case pending 0 0 amorçage "aucun statut, workflow absent de la base"
  ci_case pending 0 1 bloque "aucun statut, workflow sur la base (story 3.16)"
  printf '[]\n' > "$work/ci.json"
  run ci_gate "$work/ci.json" 0 .gitea/workflows/checks.yaml
  assert_eq 2 "$rc" "réponse illisible"
}

case_titre_de_fusion() {
  run merge_title "$fixtures/pr/titre-special.json" 12 "$work/titre.txt"
  assert_eq 0 "$rc" "code de retour"
  jq -j '.title + " (#12)\n"' "$fixtures/pr/titre-special.json" > "$work/attendu.txt"
  cmp -s "$work/attendu.txt" "$work/titre.txt" || { echo "titre différent de celui de la PR (D5)" >&2; exit 1; }
  assert_eq true "$(jq -n --rawfile t "$work/titre.txt" --slurpfile p "$fixtures/pr/titre-special.json" \
    '($t | rtrimstr("\n")) == ($p[0].title + " (#12)")')" "titre envoyé à la forge identique octet pour octet"
  printf '{"title": null}\n' > "$work/pr.json"
  run merge_title "$work/pr.json" 12 "$work/titre.txt"
  assert_eq 2 "$rc" "PR sans titre lisible"
}

# Dépôt de test : un commit relu, puis un commit de tête écrit par la fonction donnée.
readonly stories=_bmad-output/implementation-artifacts
status_repo() {
  new_repo
  mkdir -p "$work/depot/$stories"
  printf 'last_updated: 2026-09-14\ndevelopment_status:\n  epic-0: in-progress\n  0-8-essai: review\n  0-9-autre: backlog\n' \
    > "$work/depot/$stories/sprint-status.yaml"
  printf '# Story 0.8\n\nStatus: review\n\n## Revue du code\n\nrapport\n' > "$work/depot/$stories/0-8-essai.md"
  printf '# Travail reporté\n' > "$work/depot/$stories/deferred-work.md"
  printf 'code\n' > "$work/depot/script.sh"
  reviewed=$(commit_all "revue")
}

done_commit() { # changements admis par la règle du commit de statut
  printf 'last_updated: 2026-09-15\ndevelopment_status:\n  epic-0: in-progress\n  0-8-essai: done\n  0-9-autre: backlog\n' \
    > "$work/depot/$stories/sprint-status.yaml"
  printf '# Story 0.8\n\nStatus: done\n\n## Revue du code\n\nrapport\n\nDécision de l’auteur.\n' > "$work/depot/$stories/0-8-essai.md"
  printf -- '- entrée reportée\n' >> "$work/depot/$stories/deferred-work.md"
}

check_rule() { # lance la règle sur le dépôt de test
  cd "$work/depot"
  run status_commit_ok "$reviewed" "$(git rev-parse HEAD)" 0-8-essai "$stories/sprint-status.yaml" "$stories"
  cd "$root"
}

case_commit_de_statut_admis() {
  status_repo
  done_commit
  commit_all "done" > /dev/null
  check_rule
  assert_eq 0 "$rc" "commit de statut conforme (raison : $out)"
}

case_commit_de_statut_variables_readonly_du_script() {
  status_repo
  done_commit
  commit_all "done" > /dev/null
  # verify-and-merge-pr.sh déclare ces noms en readonly : la règle doit utiliser ses arguments, sans erreur
  readonly status_file=ailleurs/sprint-status.yaml stories_dir=ailleurs
  check_rule
  assert_eq 0 "$rc" "commit de statut conforme malgré les readonly du script (raison : $out)"
  assert_eq "" "$err" "aucune erreur sur la sortie d'erreur"
}

case_commit_de_statut_ligne_supprimee() {
  status_repo
  done_commit
  printf '# Story 0.8\n\nStatus: done\n\n## Revue du code\n' > "$work/depot/$stories/0-8-essai.md"
  commit_all "done" > /dev/null
  check_rule
  assert_eq 1 "$rc" "ligne supprimée du fichier de story"
  assert_contains "suppression autre que" "$out" "raison"
}

case_commit_de_statut_autre_fichier() {
  status_repo
  done_commit
  printf 'code modifié\n' > "$work/depot/script.sh"
  commit_all "done" > /dev/null
  check_rule
  assert_eq 1 "$rc" "fichier hors de la règle"
  assert_contains "hors de la règle du commit de statut" "$out" "raison"
}

case_commit_de_statut_grep_en_erreur() {
  status_repo
  done_commit
  printf -- '- ligne retirée ensuite\n' >> "$work/depot/$stories/deferred-work.md"
  commit_all "relu" > /dev/null
  reviewed=$(git -C "$work/depot" rev-parse HEAD)
  printf '# Travail reporté\n' > "$work/depot/$stories/deferred-work.md"
  commit_all "suppression dans deferred-work.md" > /dev/null
  grep() { return 2; } # une erreur de grep ne doit jamais valoir « aucune ligne supprimée »
  check_rule
  unset -f grep
  assert_eq 1 "$rc" "erreur de grep : la règle refuse"
  assert_contains "impossible" "$out" "raison"
}

case_commit_de_statut_deux_commits() {
  status_repo
  printf -- '- entrée reportée\n' >> "$work/depot/$stories/deferred-work.md"
  commit_all "premier" > /dev/null
  done_commit
  commit_all "second" > /dev/null
  check_rule
  assert_eq 1 "$rc" "deux commits après le SHA relu"
  assert_contains "plus d'un commit" "$out" "raison"
}

run_case "$@"
