#!/usr/bin/env bash
# Décisions des verrous de fusion (gates/merge-gates.sh) : constats D1, D5 et S5 de la rétrospective
# de l'epic 0 du projet source, rapport retenu, règle du commit de statut ; puis ce que le paramétrage
# par workflow.config y a ajouté (contexte de CI, exception documentaire, base).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$common/gates/merge-gates.sh"

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
  # shellcheck disable=SC2329 # appelée par son nom, passé à read_timeline_reports
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

# Réponse de la forge, dans sa vraie forme : l'état de chaque statut est sous « status », le contexte
# s'écrit « <workflow> / <job> (<événement>) », et « state » n'existe qu'au niveau combiné.
ci_reponse() { # $1… = « <contexte>=<état> » ; sans argument, aucun statut
  local entrees="" arg
  for arg in "$@"; do
    entrees+="${entrees:+,}$(printf '{"context": "%s", "status": "%s"}' "${arg%%=*}" "${arg#*=}")"
  done
  printf '{"state": "peu importe", "total_count": %s, "statuses": [%s]}\n' "$#" "$entrees" > "$work/ci.json"
}

ci_case() { # $1 workflow sur la base, $2 décision attendue, $3 libellé, $4 contexte (checks), $5 étendue (context) ; la réponse est déjà écrite
  run ci_gate "$work/ci.json" "$1" .gitea/workflows/checks.yaml "${4:-checks}" "${5:-context}"
  assert_eq 0 "$rc" "$3 : code de retour"
  assert_eq "$2" "${out%%$'\t'*}" "$3"
}

case_verrou_ci() {
  ci_reponse "checks / checks (pull_request)=success"; ci_case 1 passe "CI verte"
  ci_reponse "checks / checks (push)=success" "checks / checks (pull_request)=success"
  ci_case 1 passe "deux statuts du même workflow, tous verts"
  # en cours : le script attend (ci.wait) ou bloque ; la décision le dit, le détail reste celui d'avant
  ci_reponse "checks / checks (pull_request)=pending"; ci_case 0 en-cours "CI en cours pendant l'amorçage (S5)"
  ci_reponse "checks / checks (pull_request)=pending"; ci_case 1 en-cours "CI en cours, workflow sur la base"
  assert_eq "en-cours	en cours sur la tête : relancer l'audit quand elle est terminée." "$out" "détail inchangé"
  ci_reponse "checks / checks (pull_request)=success" "checks / checks (push)=pending"
  ci_case 1 en-cours "un statut en cours suffit"
  ci_reponse "checks / checks (pull_request)=failure"; ci_case 0 bloque "CI en échec"
  ci_reponse "checks / checks (pull_request)=error"; ci_case 1 bloque "CI en erreur"
  ci_reponse "checks / checks (pull_request)=cancelled"; ci_case 1 bloque "run annulé : bloque comme un échec"
  ci_reponse "checks / checks (pull_request)=skipped"; ci_case 1 bloque "run ignoré : bloque aussi"
  ci_reponse; ci_case 0 amorçage "aucun statut, workflow absent de la base"
  ci_reponse; ci_case 1 bloque "aucun statut, workflow sur la base (story 3.16)"
}

case_verrou_ci_echec_partiel() {
  # Deux jobs du même workflow, l'un vert l'autre non : le verrou bloque, et ne nomme que l'état
  # fautif — « état success failure » se lisait mal (constat de la revue de la PR n° 52).
  ci_reponse "checks / un (pull_request)=success" "checks / deux (pull_request)=failure"
  ci_case 1 bloque "un job en échec bloque, même si l'autre est vert"
  assert_eq "bloque	état failure sur la tête." "$out" "seul l'état fautif est nommé"
  ci_reponse "checks / un (pull_request)=failure" "checks / deux (pull_request)=cancelled"
  ci_case 1 bloque "deux états fautifs"
  assert_contains "failure cancelled" "$out" "les deux sont nommés, une fois chacun"
  ci_reponse "checks / un (pull_request)=failure" "checks / deux (pull_request)=failure"
  ci_case 1 bloque "deux fois le même état"
  assert_eq "bloque	état failure sur la tête." "$out" "il n'est nommé qu'une fois"
}

case_verrou_ci_statut_sans_etat() {
  # Gitea n'est pas censé rendre un statut sans état ; s'il le faisait, le verrou bloque et le dit
  # en un seul mot (la boucle des états fautifs découpe sur les espaces).
  printf '{"statuses": [{"context": "checks / checks (push)"}]}\n' > "$work/ci.json"
  ci_case 1 bloque "un statut sans état bloque"
  assert_eq "bloque	état sans-état sur la tête." "$out" "l'état manquant est nommé en un seul mot"
}

case_verrou_ci_nomme_le_workflow() {
  # AD-16 : l'agent de parité commente sans bloquer. Son statut ne doit pas décider d'une fusion,
  # ni en la bloquant, ni en la permettant (constat de la revue de spec de la story 3.16).
  ci_reponse "parity-agent / agent (pull_request)=failure" "checks / checks (pull_request)=success"
  ci_case 1 passe "un autre workflow en échec ne bloque pas"
  ci_reponse "parity-agent / agent (pull_request)=success"
  ci_case 1 bloque "un autre workflow vert ne remplace pas le workflow des contrôles"
  assert_contains "aucun statut du workflow" "$out" "le message dit ce qui manque"
  ci_reponse "checks-autre / job (push)=success"
  ci_case 1 bloque "un workflow dont le nom commence par « checks » sans être lui ne compte pas"
}

case_verrou_ci_deux_absences_distinctes() {
  # Les deux « absent » ne se confondent pas à l'écran : l'un est l'amorçage, l'autre un blocage.
  ci_reponse; ci_case 0 amorçage "amorçage"
  assert_contains "absent de la base" "$out" "l'amorçage dit que le workflow manque à la base"
  ci_reponse; ci_case 1 bloque "workflow sur la base"
  assert_contains "existe sur la base" "$out" "le blocage dit que le workflow est là"
}

case_verrou_ci_reponse_illisible() {
  printf '[]\n' > "$work/ci.json"
  run ci_gate "$work/ci.json" 0 .gitea/workflows/checks.yaml checks context
  assert_eq 2 "$rc" "réponse illisible"
  printf 'pas du json\n' > "$work/ci.json"
  run ci_gate "$work/ci.json" 0 .gitea/workflows/checks.yaml checks context
  assert_eq 2 "$rc" "réponse qui n'est pas du JSON"
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
  printf "# Story 0.8\n\nStatus: done\n\n## Revue du code\n\nrapport\n\nDécision de l’auteur.\n" > "$work/depot/$stories/0-8-essai.md"
  printf -- '- entrée reportée\n' >> "$work/depot/$stories/deferred-work.md"
}

check_rule() { # lance la règle sur le dépôt de test
  cd "$work/depot"
  run status_commit_ok "$reviewed" "$(git rev-parse HEAD)" 0-8-essai "$stories/sprint-status.yaml" "$stories" numbered 0-8-essai
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
  # shellcheck disable=SC2034 # posées exprès, jamais lues : la règle ne doit pas dépendre des noms du script
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
  # shellcheck disable=SC2329 # remplace grep pour les fonctions appelées ensuite par check_rule
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

# --- règle du commit de statut, convention keyed (calculette#outillage-5) ----------------------------
# Le suivi d'origine (calculette#outillage-5) : epics nommés, commentaires de fin de ligne, fichier de story nommé par un
# alias. Le commit de statut garde chaque commentaire tel quel : seule la valeur du statut change.

keyed_repo() {
  new_repo
  mkdir -p "$work/depot/$stories"
  printf 'last_updated: 2026-10-05\naliases:\n  court: fix-long-nom\ndevelopment_status:\n  epic-outillage: in-progress  # epic\n  fix-long-nom: review  # décision\n  epic-outillage-retrospective: optional\n' \
    > "$work/depot/$stories/sprint-status.yaml"
  printf '# Court\n\nStatus: review  # en revue\n\n## Revue\n' > "$work/depot/$stories/court.md"
  printf 'code\n' > "$work/depot/script.sh"
  reviewed=$(commit_all "revue")
}

keyed_done_commit() { # $1 commentaire de la story dans le suivi (décision), $2 statut de l'epic (done)
  printf 'last_updated: 2026-10-06\naliases:\n  court: fix-long-nom\ndevelopment_status:\n  epic-outillage: %s  # epic\n  fix-long-nom: done  # %s\n  epic-outillage-retrospective: optional\n' \
    "${2:-done}" "${1:-décision}" > "$work/depot/$stories/sprint-status.yaml"
  printf '# Court\n\nStatus: done  # en revue\n\n## Revue\n\nDécision.\n' > "$work/depot/$stories/court.md"
}

check_keyed_rule() {
  cd "$work/depot"
  run status_commit_ok "$reviewed" "$(git rev-parse HEAD)" fix-long-nom "$stories/sprint-status.yaml" "$stories" keyed court
  cd "$root"
}

case_commit_de_statut_keyed_admis() {
  keyed_repo
  keyed_done_commit
  commit_all "done" > /dev/null
  check_keyed_rule
  assert_eq 0 "$rc" "epic nommé à done, commentaires gardés, fichier de l'alias (raison : $out)"
}

case_commit_de_statut_keyed_epic_inchange() {
  keyed_repo
  keyed_done_commit décision in-progress
  commit_all "done" > /dev/null
  check_keyed_rule
  assert_eq 0 "$rc" "seule la story passe à done (raison : $out)"
}

case_commit_de_statut_keyed_commentaire_change() {
  keyed_repo
  keyed_done_commit "autre décision"
  commit_all "done" > /dev/null
  check_keyed_rule
  assert_eq 1 "$rc" "un commentaire du suivi réécrit sort de la règle"
  assert_contains "suivi de sprint" "$out" "raison"
}

case_commit_de_statut_keyed_retrospective() {
  keyed_repo
  keyed_done_commit
  sed -i 's/epic-outillage-retrospective: optional/epic-outillage-retrospective: done/' "$work/depot/$stories/sprint-status.yaml"
  commit_all "done" > /dev/null
  check_keyed_rule
  assert_eq 1 "$rc" "une rétrospective ne change pas dans un commit de statut"
  assert_contains "suivi de sprint" "$out" "raison"
}

case_commit_de_statut_keyed_mauvais_fichier() {
  keyed_repo
  keyed_done_commit
  commit_all "done" > /dev/null
  check_keyed_rule
  assert_eq 0 "$rc" "le fichier nommé par l'appelant est celui du commit (raison : $out)"
  cd "$work/depot"
  run status_commit_ok "$reviewed" "$(git rev-parse HEAD)" fix-long-nom "$stories/sprint-status.yaml" "$stories" keyed fix-long-nom
  cd "$root"
  assert_eq 1 "$rc" "le fichier de story n'est pas celui que nomme l'appelant"
  assert_contains "hors de la règle du commit de statut" "$out" "raison"
}

case_commit_de_statut_keyed_gardes_du_suivi() {
  # Chaque garde du suivi, sur l'entrée qu'elle doit refuser : une ligne retirée hors des lignes de
  # statut, une ligne ajoutée hors des lignes de statut, une story qui ne passe pas à done.
  local cas raison
  while IFS='|' read -r cas raison; do
    keyed_repo
    keyed_done_commit
    case $cas in
      suppression) sed -i '/^  court: fix-long-nom$/d' "$work/depot/$stories/sprint-status.yaml" ;;
      ajout) printf '  fix-nouvelle: backlog\n' >> "$work/depot/$stories/sprint-status.yaml" ;;
      pas-done) sed -i 's/^  fix-long-nom: done  # décision$/  fix-long-nom: in-progress  # décision/' "$work/depot/$stories/sprint-status.yaml" ;;
    esac
    commit_all "done" > /dev/null
    check_keyed_rule
    assert_eq 1 "$rc" "garde « $cas » : la règle refuse"
    assert_contains "$raison" "$out" "garde « $cas » : raison"
    rm -rf "$work/depot"
  done <<'CAS'
suppression|suivi de sprint : suppression hors des lignes de statut
ajout|suivi de sprint : ajout hors des lignes de statut
pas-done|suivi de sprint : ajout hors des lignes de statut
CAS
  # la story absente des lignes ajoutées, sans autre changement : seule la garde « pas à done » répond
  keyed_repo
  sed -i 's/^last_updated: .*/last_updated: 2026-10-07/' "$work/depot/$stories/sprint-status.yaml"
  printf '# Court\n\nStatus: done  # en revue\n\n## Revue\n' > "$work/depot/$stories/court.md"
  commit_all "done" > /dev/null
  check_keyed_rule
  assert_eq 1 "$rc" "la story ne passe pas à done"
  assert_contains "suivi de sprint : la story ne passe pas à done" "$out" "raison"
}

case_commit_de_statut_keyed_en_tete_de_forme_ancienne() {
  # Les formes que lit le contrôle keyed : à done, l'en-tête garde la sienne, ou passe à « Status: done ».
  local avant apres
  while IFS='|' read -r avant apres; do
    keyed_repo
    printf '# Court\n\n%s\n\n## Revue\n' "$avant" > "$work/depot/$stories/court.md"
    reviewed=$(commit_all "revue")
    keyed_done_commit
    printf '# Court\n\n%s\n\n## Revue\n\nDécision.\n' "$apres" > "$work/depot/$stories/court.md"
    commit_all "done" > /dev/null
    check_keyed_rule
    assert_eq 0 "$rc" "« $avant » → « $apres » (raison : $out)"
    rm -rf "$work/depot"
  done <<'CAS'
status: 'review'|status: 'done'
status: 'review'|Status: done
**Status**: review  # x|**Status**: done  # x
**Status**: review  # x|Status: done  # x
CAS
  keyed_repo
  keyed_done_commit
  printf '# Court\n\nStatus: done  # autre\n\n## Revue\n\nDécision.\n' > "$work/depot/$stories/court.md"
  commit_all "done" > /dev/null
  check_keyed_rule
  assert_eq 1 "$rc" "le commentaire de l'en-tête change"
  assert_contains "commentaire changé" "$out" "raison"
}

case_commit_de_statut_keyed_gardes_du_fichier_de_story() {
  # Une ligne retirée du fichier de story autre que l'en-tête, puis un en-tête qui ne passe pas à done.
  keyed_repo
  keyed_done_commit
  printf '# Court\n\nStatus: done  # en revue\n\nDécision.\n' > "$work/depot/$stories/court.md"
  commit_all "done" > /dev/null
  check_keyed_rule
  assert_eq 1 "$rc" "une ligne retirée du fichier de story autre que l'en-tête"
  assert_contains "fichier de story : suppression autre que la ligne « Status: review »" "$out" "raison"
  keyed_repo
  keyed_done_commit
  printf '# Court\n\nStatus: in-progress  # en revue\n\n## Revue\n\nDécision.\n' > "$work/depot/$stories/court.md"
  commit_all "done" > /dev/null
  check_keyed_rule
  assert_eq 1 "$rc" "l'en-tête ne passe pas à done"
  assert_contains "fichier de story : « Status: done » absent" "$out" "raison"
}

case_commit_de_statut_keyed_deferred_work() {
  keyed_repo
  printf '# Travail reporté\n- entrée\n' > "$work/depot/$stories/deferred-work.md"
  reviewed=$(commit_all "revue")
  keyed_done_commit
  printf -- '- ajout\n' >> "$work/depot/$stories/deferred-work.md"
  commit_all "done" > /dev/null
  check_keyed_rule
  assert_eq 0 "$rc" "une ligne ajoutée à deferred-work.md est admise (raison : $out)"
  keyed_repo
  printf '# Travail reporté\n- entrée\n' > "$work/depot/$stories/deferred-work.md"
  reviewed=$(commit_all "revue")
  keyed_done_commit
  printf '# Travail reporté\n' > "$work/depot/$stories/deferred-work.md"
  commit_all "done" > /dev/null
  check_keyed_rule
  assert_eq 1 "$rc" "une ligne retirée de deferred-work.md sort de la règle"
  assert_contains "deferred-work.md : ligne supprimée" "$out" "raison"
}

case_commit_de_statut_convention_inconnue() {
  status_repo
  done_commit
  commit_all "done" > /dev/null
  cd "$work/depot"
  run status_commit_ok "$reviewed" "$(git rev-parse HEAD)" 0-8-essai "$stories/sprint-status.yaml" "$stories" autre 0-8-essai
  cd "$root"
  assert_eq 1 "$rc" "convention inconnue : la règle refuse"
  assert_contains "convention" "$out" "raison"
}

case_verrou_ci_statut_ignore() {
  # Constat du 21/09/2026 : dès que les contextes sont obligatoires, la tête d'une PR porte un
  # « checks / checks (push) » ignoré à côté du « (pull_request) » vert, le déclencheur push
  # n'écoutant que dev et main. Un renoncement n'est pas un échec — mais il ne suffit pas.
  ci_reponse "checks / checks (push)=skipped" "checks / checks (pull_request)=success"
  ci_case 1 passe "un statut ignoré à côté d'un vert ne bloque pas"
  ci_reponse "checks / checks (push)=skipped"
  ci_case 1 bloque "un statut ignoré seul ne vaut pas un run"
  assert_contains "aucun run effectif" "$out" "le message dit ce qui manque"
  ci_reponse "checks / checks (push)=skipped" "checks / checks (pull_request)=failure"
  ci_case 1 bloque "un ignoré n'excuse pas un échec"
  assert_eq "bloque	état failure sur la tête." "$out" "seul l'état fautif est nommé"
  ci_reponse "checks / checks (push)=skipped" "checks / checks (pull_request)=pending"
  ci_case 1 en-cours "un run en cours reste en cours, ignoré ou non"
}

case_verrou_ci_contexte_lu_dans_workflow_config() {
  # Le nom du workflow n'est plus écrit dans le verrou : il vient de ci.status-context, espaces et
  # « & » compris, et le workflow « checks » n'y a plus de place particulière.
  ci_reponse "CI Tests & Quality / phpunit (push)=success" "checks / checks (pull_request)=failure"
  ci_case 1 passe "le contexte déclaré décide, un autre workflow n'entre pas" "CI Tests & Quality"
  ci_reponse "CI Tests & Quality / phpunit (push)=success" "CI Tests & Quality / phpstan (push)=failure"
  ci_case 1 bloque "un job du workflow déclaré en échec bloque" "CI Tests & Quality"
  ci_reponse "CI Tests & Quality Extra / job (push)=success"
  ci_case 1 bloque "un workflow dont le nom commence par le contexte sans être lui ne compte pas" "CI Tests & Quality"
  assert_contains "aucun statut du workflow « CI Tests & Quality »" "$out" "le message nomme le workflow déclaré"
  ci_reponse "checks / checks (pull_request)=success"
  run ci_gate "$work/ci.json" 1 .gitea/workflows/checks.yaml "" context
  assert_eq 2 "$rc" "un contexte vide ne prend pas tous les statuts : réponse refusée"
}

case_exception_documentaire() {
  run review_exemption '^_bmad-output/' $'_bmad-output/a.md\n_bmad-output/b.yaml'
  assert_eq 0 "$rc" "tous les fichiers correspondent : exemptée"
  run review_exemption '^_bmad-output/' $'_bmad-output/a.md\nAGENTS.md'
  assert_eq 1 "$rc" "un seul fichier ailleurs rétablit la revue"
  run review_exemption '[.]md$' $'docs/a.md\nREADME.md'
  assert_eq 0 "$rc" "l'expression vient du projet : PR documentaire"
  run review_exemption '[.]md$' $'docs/a.md\nscripts/x.sh'
  assert_eq 1 "$rc" "un script dans la PR rétablit la revue"
  run review_exemption none $'_bmad-output/a.md'
  assert_eq 1 "$rc" "none : aucune exception"
  run review_exemption none $'docs/none.md'
  assert_eq 1 "$rc" "none n'est jamais lu comme une expression : un fichier qui s'appelle none n'est pas exempté"
  run review_exemption '^_bmad-output/' ''
  assert_eq 1 "$rc" "aucun fichier n'est pas une exemption"
  run review_exemption '(' 'a.md'
  assert_eq 2 "$rc" "une expression que grep refuse n'est jamais « aucune correspondance »"
}

# review.agent-paths (schéma 6, calculette#outillage-22) : les fichiers qui dirigent les agents lèvent
# l'exception documentaire. L'expression est celle que la calculette a retenue.
readonly agent_paths_regex='(^|/)(AGENTS|CLAUDE)[.]md$|^[.]claude/rules/|^docs/procedures/|^docs/review/|^[.](claude|cursor|gemini)/skills/'

case_fichiers_qui_dirigent_les_agents() {
  run agent_paths_touched "$agent_paths_regex" $'docs/README.md\n_bmad-output/a.md'
  assert_eq 1 "$rc" "aucun fichier en cause : l'exception tient"
  assert_eq "" "$out" "et rien n'est nommé"
  run agent_paths_touched "$agent_paths_regex" $'docs/a.md\nAGENTS.md'
  assert_eq 0 "$rc" "AGENTS.md à la racine : en cause"
  assert_eq "AGENTS.md" "$out" "le seul fichier en cause est nommé"
  run agent_paths_touched "$agent_paths_regex" $'e2e/AGENTS.md\ndocker/CLAUDE.md'
  assert_eq 0 "$rc" "AGENTS.md imbriqué : en cause"
  assert_eq $'e2e/AGENTS.md\ndocker/CLAUDE.md' "$out" "chaque fichier en cause, un par ligne, dans l'ordre de la liste"
  run agent_paths_touched "$agent_paths_regex" 'docs/procedures/x.md'
  assert_eq 0 "$rc" "une procédure : en cause"
  run agent_paths_touched "$agent_paths_regex" $'.claude/skills/x/SKILL.md\n.claude/rules/r.md\ndocs/review/couche.md'
  assert_eq 0 "$rc" "skills, règles et couche de revue : en cause"
  assert_eq 3 "$(wc -l <<< "$out")" "les trois sont nommés"
  run agent_paths_touched "$agent_paths_regex" 'docs/README.md'
  assert_eq 1 "$rc" "docs/README.md ne dirige pas les agents"
  run agent_paths_touched "$agent_paths_regex" 'docs/NOT-AGENTS.md'
  assert_eq 1 "$rc" "un nom qui finit par AGENTS.md sans l'être n'est pas en cause"
  run agent_paths_touched none 'none'
  assert_eq 1 "$rc" "none n'est jamais lu comme une expression : un fichier nommé none n'est pas en cause"
  assert_eq "" "$out" "et rien n'est nommé"
  run agent_paths_touched '(' 'AGENTS.md'
  assert_eq 2 "$rc" "une expression invalide n'est jamais « aucune correspondance »"
  run agent_paths_touched '(' ''
  assert_eq 2 "$rc" "une expression invalide sort en 2, même sur une liste vide"
  run agent_paths_touched "$agent_paths_regex" ''
  assert_eq 1 "$rc" "liste vide : aucun fichier en cause"
  # une expression qui admet la chaîne vide : sans la garde de liste vide, la ligne vide que lit la
  # boucle serait « en cause » (revue 3 de la PR n° 19)
  run agent_paths_touched '.*' ''
  assert_eq 1 "$rc" "liste vide, même avec une expression qui admet le vide : aucun fichier en cause"
  assert_eq "" "$out" "et rien n'est nommé"
  # un chemin que git cite (octet hors ASCII) : son guillemet ferait manquer le motif ancré ; il compte
  # comme en cause, jamais comme dispensé (revue 2 de la PR n° 19)
  run agent_paths_touched "$agent_paths_regex" $'docs/a.md\n"docs/proc\\303\\251dures/a.md"'
  assert_eq 0 "$rc" "un chemin cité par git est en cause"
  assert_eq '"docs/proc\303\251dures/a.md"' "$out" "et nommé tel que git l'écrit"
  run agent_paths_touched "$agent_paths_regex" '.claude/skills/mon skill/SKILL.md'
  assert_eq 0 "$rc" "une espace dans le chemin ne le fait pas manquer (git ne le cite pas)"
}

case_verrou_de_base() {
  run base_gate dev dev main
  assert_eq "passe" "${out%%$'\t'*}" "la base déclarée passe"
  run base_gate main dev main
  assert_eq "bloque" "${out%%$'\t'*}" "la branche de publication est refusée"
  assert_contains "branche de publication" "$out" "et le message le dit"
  run base_gate autre dev main
  assert_eq "bloque" "${out%%$'\t'*}" "toute autre base est refusée"
  assert_contains "seule dev est admise" "$out" "le message nomme la base admise"
  run base_gate main main none
  assert_eq "passe" "${out%%$'\t'*}" "sans branche de publication, la base unique passe"
}

# --- étendue « all » (ci.statuses, schéma 5 ; calculette#outillage-8, V12) ---------------------------

case_verrou_ci_etendue_obligatoire() {
  ci_reponse "checks / checks (pull_request)=success"
  run ci_gate "$work/ci.json" 1 .gitea/workflows/checks.yaml checks
  assert_eq 2 "$rc" "sans étendue, aucun repli sur « context »"
  run ci_gate "$work/ci.json" 1 .gitea/workflows/checks.yaml checks tous
  assert_eq 2 "$rc" "une étendue inconnue est refusée"
}

case_verrou_ci_tous_les_statuts() {
  # calculette#outillage-8 juge tous ses workflows : l'audit de dépendances bloque comme la CI.
  ci_reponse "CI Tests & Quality / phpunit (push)=success" "Security Audit / audit (push)=failure"
  ci_case 1 bloque "un autre workflow en échec bloque" "CI Tests & Quality" all
  assert_eq "bloque	état failure sur la tête." "$out" "l'état fautif est nommé"
  ci_reponse "CI Tests & Quality / phpunit (push)=success" "Security Audit / audit (push)=pending"
  ci_case 1 en-cours "un autre workflow en cours se fait attendre" "CI Tests & Quality" all
  ci_reponse "CI Tests & Quality / phpunit (push)=success" "Security Audit / audit (push)=success"
  ci_case 1 passe "tous verts" "CI Tests & Quality" all
  assert_eq "passe	verte sur la tête (tous les statuts)." "$out" "le détail dit l'étendue"
  ci_reponse "CI Tests & Quality / phpunit (push)=success" "Security Audit / audit (push)=skipped"
  ci_case 1 passe "un statut ignoré est écarté" "CI Tests & Quality" all
  ci_reponse "CI Tests & Quality / phpunit (push)=pending" "Security Audit / audit (push)=failure"
  ci_case 1 bloque "un échec bloque tout de suite, sans attendre le run en cours" "CI Tests & Quality" all
  assert_eq "bloque	état failure sur la tête." "$out" "seul l'état fautif est nommé"
  ci_reponse "checks / checks (pull_request)=pending" "checks / autre (pull_request)=failure"
  ci_case 1 en-cours "context : l'ordre d'avant le schéma 5 est gardé (en cours d'abord)"
}

case_verrou_ci_tous_les_statuts_exige_le_workflow_des_controles() {
  # « tous » s'ajoute au workflow des contrôles, il ne le remplace pas : un audit vert seul ne vaut pas une CI.
  ci_reponse "Security Audit / audit (push)=success"
  ci_case 1 bloque "le workflow des contrôles manque" "CI Tests & Quality" all
  assert_contains "aucun statut du workflow « CI Tests & Quality »" "$out" "le message le nomme"
  ci_reponse "Security Audit / audit (push)=success"
  ci_case 0 amorçage "workflow absent de la base : amorçage" "CI Tests & Quality" all
  ci_reponse "Security Audit / audit (push)=failure"
  ci_case 0 bloque "pendant l'amorçage, un autre workflow en échec bloque quand même" "CI Tests & Quality" all
  ci_reponse "CI Tests & Quality / phpunit (push)=skipped" "Security Audit / audit (push)=success"
  ci_case 1 bloque "le workflow des contrôles seulement ignoré ne compte pas" "CI Tests & Quality" all
  assert_contains "aucun run effectif" "$out" "le message dit ce qui manque"
}

case_verrou_ci_tous_les_statuts_runner_coince() {
  # « pending » sans aucun statut : rien n'a démarré. Jamais « en cours », donc jamais attendu.
  printf '{"state": "pending", "total_count": 0, "statuses": []}\n' > "$work/ci.json"
  ci_case 1 bloque "aucun statut, workflow sur la base" "CI Tests & Quality" all
  assert_contains "aucun statut sur la tête" "$out" "le message dit que rien n'a démarré"
  printf '{"state": "pending", "total_count": 0, "statuses": []}\n' > "$work/ci.json"
  ci_case 0 amorçage "aucun statut, workflow absent de la base" "CI Tests & Quality" all
}

case_attente_ci_ne_depasse_jamais_ci_wait() {
  # constat de la revue 1 de la PR n° 17 : un pas fixe de 30 s attendait 60 s pour ci.wait = 40
  run ci_wait_step 0 40; assert_eq 30 "$out" "premier pas : 30 s"
  run ci_wait_step 30 40; assert_eq 10 "$out" "dernier pas raccourci à ce qui reste"
  run ci_wait_step 40 40; assert_eq "" "$out" "attente épuisée : aucun pas"
  assert_eq 0 "$rc" "épuisée n'est pas une erreur"
  run ci_wait_step 0 0; assert_eq "" "$out" "ci.wait = 0 : aucune attente"
  run ci_wait_step 0 1; assert_eq 1 "$out" "ci.wait plus court que le pas"
  local attendu=0 pas lectures=1
  while pas=$(ci_wait_step "$attendu" 1200) && [[ -n $pas ]]; do
    attendu=$((attendu + pas)); lectures=$((lectures + 1))
  done
  assert_eq "1200 41" "$attendu $lectures" "1200 s : 40 attentes de 30 s, 41 lectures (l'ancien sondage de calculette)"
  attendu=0
  while pas=$(ci_wait_step "$attendu" 95) && [[ -n $pas ]]; do attendu=$((attendu + pas)); done
  assert_eq 95 "$attendu" "l'attente totale vaut ci.wait, jamais plus"
  run ci_wait_step x 40; assert_eq 2 "$rc" "entrée illisible"
  run ci_wait_step 0 ""; assert_eq 2 "$rc" "ci.wait absent : aucune valeur de repli"
}

run_case "$@"
