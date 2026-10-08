#!/usr/bin/env bash
# De bout en bout, contre une forge simulée : gates/verify-and-merge-pr.sh en audit et en fusion, et
# review/llm-review.sh sur un projet qui consomme un sous-module. Constat reporté de la revue de la
# phase B de la story outillage-14 : chaque décision était testée à part (merge-gates, sprint,
# config), mais aucun cas ne faisait tourner un point d'entrée entier, appels à la forge compris.
#
# **Aucun réseau.** Un faux curl répond depuis $work/api, une réponse par « méthode chemin » (et par
# rang d'appel quand la réponse change : la PR relue après la fusion) ; il note chaque appel et garde
# chaque corps envoyé. Un faux ssh fait servir les dépôts nus de $work/forge par git lui-même : le
# « git fetch origin » des scripts lit une vraie branche, à un vrai SHA. Un faux agy rend un rapport.
#
# **Aîné : tests/test-merge-gates.sh** (réponses de la forge en fichiers, état de CI dans sa vraie
# forme sous « status »), et le faux curl du projet source pour sa publication (rang d'appel, corps
# gardés, jeton lu sur l'entrée standard et jamais écrit). Gardes reprises : réponse absente → corps
# vide et code 404, jamais un 200 par défaut ; chaque cas qui refuse vérifie qu'aucune écriture n'a
# atteint la forge.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly repo=Proprietaire/projet-essai
readonly pr=7
readonly branche=feat/1-2-essai
depot=$work/depot
nu=$work/forge/$repo.git

# --- la forge simulée ------------------------------------------------------------------------------

faux_outils() {
  mkdir -p "$work/bin" "$work/api"
  {
    printf '#!/usr/bin/env bash\nw=%q\n' "$work"
    cat <<'FAUX'
cat > /dev/null # le jeton arrive par « -K - » : lu, jamais écrit
out="" methode=GET url="" corps="" format=""
while (($#)); do
  case $1 in
    -o) out=$2; shift 2 ;;
    -X) methode=$2; shift 2 ;;
    -w) format=$2; shift 2 ;;
    -K|-H) shift 2 ;;
    --data) corps=${2#@}; shift 2 ;;
    -s) shift ;;
    *) url=$1; shift ;;
  esac
done
chemin=${url#*/api/v1}
cle=$(printf '%s %s' "$methode" "$chemin" | sed 's#[^A-Za-z0-9]#_#g')
printf '%s %s\n' "$methode" "$chemin" >> "$w/appels"
[[ -z $corps ]] || { cat "$corps" >> "$w/corps"; printf '\n' >> "$w/corps"; }
n=1
[[ ! -f $w/rang-$cle ]] || n=$(($(cat "$w/rang-$cle") + 1))
printf '%s' "$n" > "$w/rang-$cle"
rep=$w/api/$cle.$n
[[ -f $rep ]] || rep=$w/api/$cle
if [[ -f $rep ]]; then
  cat "$rep" > "$out"
  code=$(cat "$rep.code" 2>/dev/null || echo 200)
else
  printf '{"message":"inconnu de la forge simulée"}' > "$out"
  code=404
fi
[[ -z $format ]] || printf '%s' "$code"
FAUX
  } > "$work/bin/curl"
  {
    printf '#!/bin/sh\n# « ssh hôte commande » : la commande tourne dans le dossier des dépôts nus\n'
    # shellcheck disable=SC2016 # faux ssh écrit sur le disque : son « $dernier » s'y développe à l'exécution
    printf 'for dernier; do :; done\ncd %q && exec sh -c "$dernier"\n' "$work/forge"
  } > "$work/bin/ssh"
  chmod +x "$work/bin/curl" "$work/bin/ssh"
}

api() { # $1 méthode, $2 chemin, $3 corps de la réponse, $4 code (200), $5 rang de l'appel (tous)
  local c
  c=$(printf '%s %s' "$1" "$2" | sed 's#[^A-Za-z0-9]#_#g')${5:+.$5}
  printf '%s' "$3" > "$work/api/$c"
  printf '%s' "${4:-200}" > "$work/api/$c.code"
}

appels() { [[ -f $work/appels ]] && cat "$work/appels"; return 0; }
aucune_ecriture() {
  # sans grep : « grep -v … || true » prendrait une erreur de grep (code 2) pour « aucune écriture »
  # (constat de la revue 2 de la PR n° 4)
  local ligne ecritures=""
  [[ ! -f $work/appels ]] || while IFS= read -r ligne || [[ -n $ligne ]]; do
    [[ $ligne == "GET "* ]] || ecritures+="$ligne"$'\n'
  done < "$work/appels"
  [[ -z $ecritures ]] || { printf 'la forge a reçu une écriture :\n%s\n' "$ecritures" >&2; exit 1; }
}

# Un 2 rendu une fois la PR connue est publié en alerte sur la PR (convention à trois codes, alerte hors
# du terminal) : la seule écriture admise est ce commentaire, qui nomme le script et le code.
# $1 = le script attendu dans l'alerte
seule_l_alerte() {
  local ligne ecritures=""
  [[ ! -f $work/appels ]] || while IFS= read -r ligne || [[ -n $ligne ]]; do
    [[ $ligne == "GET "* || $ligne == "POST /repos/$repo/issues/$pr/comments" ]] || ecritures+="$ligne"$'\n'
  done < "$work/appels"
  [[ -z $ecritures ]] || { printf 'la forge a reçu une écriture autre que l alerte :\n%s\n' "$ecritures" >&2; exit 1; }
  assert_contains "POST /repos/$repo/issues/$pr/comments" "$(appels)" "l'anomalie est publiée en alerte sur la PR"
  assert_contains "$1 : anomalie (code 2)" "$(jq -r .body "$work/corps" 2>/dev/null | tail -n 20)" "l'alerte nomme le script et le code"
}

# --- le projet -----------------------------------------------------------------------------------

stories=_bmad-output/implementation-artifacts

# La forme du suivi : numbered par défaut ; keyed pour les cas de la convention keyed (calculette#outillage-5),
# où le fichier 1-2-essai.md porte l'alias de la clé story-essai-longue.
forme_du_suivi=numbered

suivi() { # $1 statut de la story 1.2 ; écrit le suivi et le fichier de story
  mkdir -p "$depot/$stories"
  if [[ $forme_du_suivi == keyed ]]; then
    printf 'last_updated: 2026-10-06\naliases:\n  1-2-essai: story-essai-longue\ndevelopment_status:\n  epic-essai: in-progress  # epic nommé\n  premiere-story: done\n  story-essai-longue: %s  # décision\n  epic-essai-retrospective: optional\n' \
      "$1" > "$depot/$stories/sprint-status.yaml"
    printf '# Story essai\n\nStatus: %s\n' "$1" > "$depot/$stories/1-2-essai.md"
    printf "# Première\n\nstatus: 'done'\n" > "$depot/$stories/premiere-story.md"
    printf '# Travail reporté\n' > "$depot/$stories/deferred-work.md"
    if [[ ${suivi_ambigu:-} == 1 ]]; then # une seconde story que le nom de branche désigne aussi
      printf '  feat-1-2-essai: done\n' >> "$depot/$stories/sprint-status.yaml"
      printf '# Autre\n\nStatus: done\n' > "$depot/$stories/feat-1-2-essai.md"
    fi
    return 0
  fi
  printf 'last_updated: 2026-10-04\ndevelopment_status:\n  epic-1: in-progress\n  1-1-premiere: done\n  1-2-essai: %s\n  1-3-suivante: backlog\n' \
    "$1" > "$depot/$stories/sprint-status.yaml"
  printf '# Story 1.2\n\nStatus: %s\n' "$1" > "$depot/$stories/1-2-essai.md"
  printf '# Story 1.1\n\nStatus: done\n' > "$depot/$stories/1-1-premiere.md"
}

# Le projet : base dev avec sa CI, son garde-fou et son suivi ; puis la branche de la story 1.2, qui
# change du code et passe la story à done. Le dépôt nu de la forge porte les deux branches.
# $@ = changements du workflow.config ; le projet est au schéma 5, qu'exige verify-and-merge-pr (étendue
# et attente du verrou CI : celles d'avant le schéma 5, sauf changement)
projet() {
  new_repo
  write_workflow_config "$depot" "forge.repo=$repo" guard.command=scripts/garde.sh guard.patterns-file=motifs.txt \
    review.project-layer=couche.md workflow.schema=5 sprint.non-story-files=none ci.statuses=context ci.wait=0 "$@"
  mkdir -p "$depot/scripts" "$depot/.gitea/workflows"
  printf 'name: checks\n' > "$depot/.gitea/workflows/checks.yaml"
  printf '#!/bin/sh\n[ ! -f %q ] || { echo "refus du garde-fou"; exit 1; }\n' "$work/garde-refuse" > "$depot/scripts/garde.sh"
  chmod +x "$depot/scripts/garde.sh"
  printf '## Projet\n\nUn projet d essai.\n' > "$depot/couche.md"
  printf 'motifs.txt\n.env\n' > "$depot/.gitignore"
  printf 'MOTIF-FACTICE\n' > "$depot/motifs.txt"
  printf 'GITEA_URL=https://forge.example.invalid\nGITEA_USER=compte-essai\nGITEA_TOKEN=jeton-essai\n' > "$depot/.env"
  suivi in-progress
  printf 'v1\n' > "$depot/code.txt"
  commit_all "base" > /dev/null
  git -C "$depot" branch -M dev
  git -C "$depot" checkout -q -b "$branche"
  printf 'v2\n' > "$depot/code.txt"
  suivi "done"
  commit_all "feat(1.2): essai" > /dev/null
  git -C "$depot" checkout -q dev
  git -C "$depot" remote add origin "git@forge.example.invalid:$repo.git"
  mkdir -p "$(dirname "$nu")"
  git init -q --bare "$nu"
  git -C "$depot" push -q "$nu" dev "$branche"
  faux_outils
}

tete() { git -C "$depot" rev-parse "$branche"; }

pr_json() { # $1 SHA de tête, $2 merged (false)
  jq -nc --arg s "$1" --arg b "$branche" --argjson m "${2:-false}" \
    '{number: 7, title: "feat(1.2): essai", state: "open", draft: false, mergeable: true, merged: $m,
      merge_commit_sha: (if $m then "abcdef0123456789abcdef0123456789abcdef01" else null end),
      base: {ref: "dev"}, head: {ref: $b, sha: $s}}'
}

# La forge nominale : jeton reconnu, PR ouverte, rapport « pass » du compte sur la tête, CI verte.
forge_prete() { # $1 verdict du rapport (pass), $2 état de la CI (success)
  local h
  h=$(tete)
  api GET /user '{"login":"compte-essai"}'
  api GET /settings/api '{"max_response_items":50}'
  api GET "/repos/$repo/pulls/$pr" "$(pr_json "$h")"
  api GET "/repos/$repo/issues/$pr/timeline?limit=50&page=1" \
    "$(jq -nc --arg c "llm-review sha=$h base=dev model=modele-essai verdict=${1:-pass}" \
      '[{type: "comment", user: {login: "compte-essai"}, body: ($c + "\n\nrapport")}]')"
  api GET "/repos/$repo/commits/$h/status" \
    "$(jq -nc --arg e "${2:-success}" '{state: $e, statuses: [{context: "checks / checks (pull_request)", status: $e}]}')"
}

verifie() { # arguments de verify-and-merge-pr.sh
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run env PATH="$work/bin:$PATH" GIT_SSH_COMMAND="$work/bin/ssh" \
    bash -c 'cd "$1" && shift && bash "$@"' _ "$depot" "$common/gates/verify-and-merge-pr.sh" "$@"
}

verrou() { # $1 état attendu, $2 verrou ; la ligne de ce verrou dans la sortie
  assert_contains "$(printf '  %-7s %-16s' "$1" "$2")" "$out" "verrou « $2 » : $1"
}

# --- verify-and-merge-pr : audit -----------------------------------------------------------------------

case_audit_pr_conforme() {
  projet
  forge_prete
  verifie "$pr"
  assert_eq 0 "$rc" "tous les verrous passent (messages : $err)"
  verrou passe "PR fusionnable"
  verrou passe "revue LLM"
  verrou passe "garde-fou"
  verrou passe "CI"
  verrou passe "suivi de sprint"
  assert_contains "story 1.2 à done : cohérent" "$out" "la story est lue dans le nom de la branche"
  aucune_ecriture
}

readonly keyed_config=(sprint.convention=keyed sprint.non-story-files=deferred-work)

case_audit_pr_keyed_conforme() {
  forme_du_suivi=keyed
  projet "${keyed_config[@]}"
  forge_prete
  verifie "$pr"
  assert_eq 0 "$rc" "tous les verrous passent en keyed (messages : $err$out)"
  verrou passe "revue LLM"
  verrou passe "suivi de sprint"
  assert_contains "story story-essai-longue à done : cohérent" "$out" "la story est la clé que l'alias du nom de branche désigne"
  aucune_ecriture
}

case_audit_pr_keyed_branche_ambigue() {
  forme_du_suivi=keyed
  suivi_ambigu=1
  projet "${keyed_config[@]}"
  forge_prete
  verifie "$pr"
  assert_eq 1 "$rc" "deux stories pour une branche : le verrou de suivi bloque (messages : $err$out)"
  verrou bloque "suivi de sprint"
  assert_contains "désigne plus d'une story du suivi" "$out" "la raison"
  aucune_ecriture
}

case_audit_pr_keyed_commit_de_statut_apres_la_revue() {
  forme_du_suivi=keyed
  projet "${keyed_config[@]}"
  git -C "$depot" checkout -q "$branche"
  suivi review
  local relu h
  relu=$(commit_all "relu")
  suivi "done"
  commit_all "chore: statut done" > /dev/null
  git -C "$depot" push -q "$nu" "$branche"
  git -C "$depot" checkout -q dev
  forge_prete
  h=$(tete)
  api GET "/repos/$repo/issues/$pr/timeline?limit=50&page=1" \
    "$(jq -nc --arg c "llm-review sha=$relu base=dev model=modele-essai verdict=pass" \
      '[{type: "comment", user: {login: "compte-essai"}, body: ($c + "\n\nrapport")}]')"
  api GET "/repos/$repo/commits/$h/status" \
    '{"state":"success","statuses":[{"context":"checks / checks (pull_request)","status":"success"}]}'
  verifie "$pr"
  assert_eq 0 "$rc" "rapport sur le parent, commit de statut keyed conforme (messages : $err$out)"
  assert_contains "le commit de tête respecte la règle du commit de statut" "$out" "la règle est appliquée"
  aucune_ecriture
}

case_audit_pr_refusee_par_la_revue() {
  projet
  forge_prete block
  verifie "$pr"
  assert_eq 1 "$rc" "un rapport « block » sur la tête bloque"
  verrou bloque "revue LLM"
  verrou passe "CI"
  assert_contains "au moins un verrou bloque" "$out" "le résumé le dit"
  aucune_ecriture
}

case_audit_pr_refusee_par_la_ci_et_le_garde_fou() {
  projet
  forge_prete pass failure
  : > "$work/garde-refuse"
  verifie "$pr"
  assert_eq 1 "$rc" "CI rouge et garde-fou en refus : bloque"
  verrou bloque "garde-fou"
  verrou bloque "CI"
  aucune_ecriture
}

case_audit_pr_exemptee() {
  # une PR dont chaque fichier est sous _bmad-output/ : la revue n'est pas exigée, et la timeline
  # n'est même pas lue
  projet
  git -C "$depot" checkout -q -b docs/suivi dev
  printf 'note\n' > "$depot/$stories/note.md"
  commit_all "docs: une note" > /dev/null
  git -C "$depot" push -q "$nu" docs/suivi
  forge_prete
  api GET "/repos/$repo/pulls/$pr" "$(pr_json "$(git -C "$depot" rev-parse docs/suivi)" | jq -c '.head.ref = "docs/suivi"')"
  api GET "/repos/$repo/commits/$(git -C "$depot" rev-parse docs/suivi)/status" \
    '{"state":"success","statuses":[{"context":"checks / checks (pull_request)","status":"success"}]}'
  verifie "$pr"
  assert_eq 0 "$rc" "PR exemptée : tous les verrous passent (messages : $err)"
  verrou passe "revue LLM"
  assert_contains "exception documentaire" "$out" "l'exception est nommée"
  assert_contains "fichiers dirigeant les agents : non contrôlés (schéma 5)." "$out" "au schéma 5, le non-contrôle est dit"
  assert_contains "contrôle global (branche sans numéro de story)" "$out" "suivi : contrôle global"
  [[ $(appels) != *timeline* ]] || { echo "la timeline a été lue pour une PR exemptée" >&2; exit 1; }
  aucune_ecriture
}

# --- review.agent-paths (schéma 6, calculette#outillage-22) : les fichiers qui dirigent les agents ------

# L'expression que la calculette a retenue, et l'exception documentaire d'un projet dont les .md sont
# dispensés de revue.
readonly agent_config=(workflow.schema=6 "review.exempt-paths=[.]md$"
  "review.agent-paths=(^|/)(AGENTS|CLAUDE)[.]md$|^[.]claude/rules/|^docs/procedures/|^docs/review/|^[.](claude|cursor|gemini)/skills/")

# Une PR docs/suivi qui ne touche que ces fichiers ; la forge est prête pour elle, CI verte, sans rapport
# de revue sauf $1 (« pass » ou « block » : un rapport du compte sur sa tête). $2… = fichiers.
pr_documentaire() {
  local verdict=$1 f h
  shift
  git -C "$depot" checkout -q -b docs/suivi dev
  for f in "$@"; do
    mkdir -p "$(dirname "$depot/$f")"
    printf 'note\n' > "$depot/$f"
  done
  commit_all "docs: des notes" > /dev/null
  git -C "$depot" push -q "$nu" docs/suivi
  git -C "$depot" checkout -q dev
  forge_prete
  h=$(git -C "$depot" rev-parse docs/suivi)
  api GET "/repos/$repo/pulls/$pr" "$(pr_json "$h" | jq -c '.head.ref = "docs/suivi"')"
  api GET "/repos/$repo/commits/$h/status" \
    '{"state":"success","statuses":[{"context":"checks / checks (pull_request)","status":"success"}]}'
  if [[ -n $verdict ]]; then
    api GET "/repos/$repo/issues/$pr/timeline?limit=50&page=1" \
      "$(jq -nc --arg c "llm-review sha=$h base=dev model=modele-essai verdict=$verdict" \
        '[{type: "comment", user: {login: "compte-essai"}, body: ($c + "\n\nrapport")}]')"
  else
    api GET "/repos/$repo/issues/$pr/timeline?limit=50&page=1" '[]'
  fi
}

case_audit_agent_paths_pr_exemptee_sans_fichier_dirigeant() {
  projet "${agent_config[@]}"
  pr_documentaire "" docs/guide.md README.md
  verifie "$pr"
  assert_eq 0 "$rc" "aucun fichier qui dirige les agents : l'exception tient (messages : $err$out)"
  verrou passe "revue LLM"
  assert_contains "revue non exigée ; aucun fichier ne correspond à review.agent-paths." "$out" "le contrôle est dit"
  [[ $(appels) != *timeline* ]] || { echo "la timeline a été lue pour une PR exemptée" >&2; exit 1; }
  aucune_ecriture
}

case_audit_agent_paths_leve_l_exception_sans_revue() {
  projet "${agent_config[@]}"
  pr_documentaire "" docs/guide.md AGENTS.md e2e/AGENTS.md
  verifie "$pr"
  assert_eq 1 "$rc" "une PR documentaire qui touche AGENTS.md exige la revue : sans rapport, elle bloque (messages : $err$out)"
  verrou bloque "revue LLM"
  assert_contains "exception documentaire levée, la PR touche des fichiers qui dirigent les agents (review.agent-paths) : AGENTS.md, e2e/AGENTS.md ; aucun rapport llm-review" \
    "$out" "les fichiers en cause sont nommés dans le verrou, et la raison du blocage suit"
  assert_contains "docs/suivi" "$out" "la PR est celle de la branche documentaire"
  [[ $(appels) == *timeline* ]] || { echo "la timeline n'a pas été lue alors que la revue est exigée" >&2; exit 1; }
  verifie "$pr" --merge
  assert_eq 1 "$rc" "--merge refuse la PR sans revue (messages : $err$out)"
  assert_contains "rien n'est fusionné" "$out" "le refus est dit"
  aucune_ecriture
}

case_audit_agent_paths_leve_l_exception_rapport_block() {
  projet "${agent_config[@]}"
  pr_documentaire block .claude/rules/regle.md
  verifie "$pr"
  assert_eq 1 "$rc" "un rapport block bloque la PR dont l'exception est levée (messages : $err$out)"
  verrou bloque "revue LLM"
  assert_contains "(review.agent-paths) : .claude/rules/regle.md ; dernier rapport sur la tête : block" "$out" "fichier et verdict nommés"
  aucune_ecriture
}

case_audit_agent_paths_leve_l_exception_revue_pass() {
  projet "${agent_config[@]}"
  pr_documentaire pass docs/procedures/fusion.md docs/guide.md
  verifie "$pr"
  assert_eq 0 "$rc" "avec un rapport pass sur la tête, la PR passe (messages : $err$out)"
  verrou passe "revue LLM"
  assert_contains "(review.agent-paths) : docs/procedures/fusion.md ; rapport pass sur la tête (modele-essai)." "$out" "le fichier en cause et le rapport sont nommés"
  aucune_ecriture
}

case_audit_agent_paths_desactive_le_dit() {
  projet "${agent_config[@]}" review.agent-paths=none
  pr_documentaire "" AGENTS.md
  verifie "$pr"
  assert_eq 0 "$rc" "review.agent-paths = none : l'exception tient (messages : $err$out)"
  verrou passe "revue LLM"
  assert_contains "fichiers dirigeant les agents : désactivé (review.agent-paths = none)." "$out" "le désactivé est dit"
  aucune_ecriture
}

case_audit_agent_paths_schema_5_le_dit() {
  # le même projet au schéma 5 : la PR reste exemptée, comme avant le schéma 6, et le verrou dit ce
  # qu'il n'a pas contrôlé
  projet "review.exempt-paths=[.]md$"
  pr_documentaire "" AGENTS.md
  verifie "$pr"
  assert_eq 0 "$rc" "au schéma 5, la PR documentaire reste exemptée (messages : $err$out)"
  verrou passe "revue LLM"
  assert_contains "fichiers dirigeant les agents : non contrôlés (schéma 5)." "$out" "le non-contrôle est dit"
  [[ $(appels) != *timeline* ]] || { echo "la timeline a été lue pour une PR exemptée" >&2; exit 1; }
  aucune_ecriture
}

case_audit_agent_paths_pr_non_exemptee_inchangee() {
  # une PR qui touche AGENTS.md ET un script n'est pas exemptée : review.agent-paths n'y change rien,
  # pas même une ligne de sortie — schéma 5 et schéma 6 rendent le même audit à l'octet
  projet "review.exempt-paths=[.]md$"
  pr_documentaire "" AGENTS.md scripts/outil.sh
  verifie "$pr"
  local rc5=$rc out5=$out
  assert_eq 1 "$rc5" "sans rapport, une PR non exemptée bloque (messages : $err$out)"
  write_workflow_config "$depot" "forge.repo=$repo" guard.command=scripts/garde.sh guard.patterns-file=motifs.txt \
    review.project-layer=couche.md sprint.non-story-files=none ci.statuses=context ci.wait=0 "${agent_config[@]}"
  verifie "$pr"
  assert_eq "$rc5" "$rc" "même code au schéma 6"
  assert_eq "$out5" "$out" "même sortie à l'octet au schéma 6"
  [[ $out != *agent* ]] || { echo "une ligne sur les fichiers qui dirigent les agents est apparue : $out" >&2; exit 1; }
  aucune_ecriture
}

case_audit_verrous_desactives_le_disent() {
  projet guard.command=none guard.patterns-file=none ci.workflow=none ci.status-context=none ci.statuses=none \
    ci.wait=none sprint.convention=none sprint.status-file=none sprint.stories-dir=none sprint.spec-source=none
  forge_prete
  verifie "$pr"
  assert_eq 0 "$rc" "les verrous désactivés ne bloquent pas (messages : $err)"
  verrou inactif "garde-fou"
  verrou inactif "CI"
  verrou inactif "suivi de sprint"
  [[ $(appels) != */status* ]] || { echo "l'état de CI a été lu alors que la CI est désactivée" >&2; exit 1; }
  aucune_ecriture
}

case_audit_depot_distant_etranger() {
  projet
  forge_prete
  git -C "$depot" remote set-url origin "git@forge.example.invalid:Proprietaire/autre.git"
  verifie "$pr"
  assert_eq 2 "$rc" "un dépôt distant autre que forge.repo : audit impossible"
  assert_eq "" "$(appels)" "la forge n'est jamais appelée"
}

# --- verify-and-merge-pr : fusion ----------------------------------------------------------------

case_fusion_pr_conforme() {
  projet
  forge_prete
  local h
  h=$(tete)
  api POST "/repos/$repo/pulls/$pr/merge" '{}'
  api GET "/repos/$repo/pulls/$pr" "$(pr_json "$h" true)" 200 3
  verifie "$pr" --merge
  assert_eq 0 "$rc" "la PR est fusionnée (messages : $err)"
  assert_contains "fusionnée en squash vers dev : abcdef0" "$out" "le commit de fusion est nommé"
  assert_contains "POST /repos/$repo/pulls/$pr/merge" "$(appels)" "la fusion est demandée à la forge"
  local demande
  demande=$(cat "$work/corps")
  assert_eq squash "$(jq -r .Do <<< "$demande")" "fusion en squash"
  assert_eq "$h" "$(jq -r .head_commit_id <<< "$demande")" "la fusion est attachée à la tête auditée"
  assert_eq true "$(jq -r .delete_branch_after_merge <<< "$demande")" "la branche est supprimée après la fusion"
  assert_eq "feat(1.2): essai (#7)" "$(jq -r .MergeTitleField <<< "$demande")" "titre de la fusion"
}

case_fusion_refusee_quand_un_verrou_bloque() {
  projet
  forge_prete pass failure
  api POST "/repos/$repo/pulls/$pr/merge" '{}'
  verifie "$pr" --merge
  assert_eq 1 "$rc" "un verrou bloque : rien n'est fusionné"
  assert_contains "rien n'est fusionné" "$out" "le refus est dit"
  aucune_ecriture
}

case_fusion_refusee_si_la_tete_a_bouge() {
  projet
  forge_prete
  api GET "/repos/$repo/pulls/$pr" "$(pr_json 0123456789abcdef0123456789abcdef01234567)" 200 2
  api POST "/repos/$repo/pulls/$pr/merge" '{}'
  api POST "/repos/$repo/issues/$pr/comments" '{}' 201
  verifie "$pr" --merge
  assert_eq 2 "$rc" "la tête a bougé pendant l'audit : anomalie"
  assert_contains "a bougé pendant l'audit" "$err" "raison"
  seule_l_alerte verify-and-merge-pr
  assert_contains "alerte publiée sur la PR n° $pr" "$err" "le terminal le dit"
}

case_audit_alerte_refusee_par_la_forge_garde_le_2() {
  # aucune réponse prévue pour le commentaire : la forge simulée rend 404, et le terminal reste seul canal
  projet
  forge_prete
  api GET "/repos/$repo/pulls/$pr" "$(pr_json 0123456789abcdef0123456789abcdef01234567)"
  verifie "$pr"
  assert_eq 2 "$rc" "la branche a bougé depuis la lecture : anomalie"
  assert_contains "alerte non publiée sur la PR n° $pr (HTTP 404)" "$err" "l'échec de l'alerte est dit"
}

# --- create-pull-request : 1 = écart constaté sur la branche, le garde-fou ou la forge ; 0 = ouverte ---

ouvre() { # $1 titre ; depuis la branche de la story, corps dans $work/corps.md
  git -C "$depot" checkout -q "$branche"
  printf 'Le corps.\n' > "$work/corps.md"
  api GET /user '{"login":"compte-essai"}'
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run env PATH="$work/bin:$PATH" GIT_SSH_COMMAND="$work/bin/ssh" \
    bash -c 'cd "$1" && shift && bash "$@"' _ "$depot" "$common/gitea/create-pull-request.sh" --title "$1" --body-file "$work/corps.md"
}

case_ouverture_pr_conforme() {
  projet
  api GET "/repos/$repo/pulls?state=open&limit=50&page=1" '[]'
  api POST "/repos/$repo/pulls" '{"number":8}' 201
  api GET "/repos/$repo/pulls/8" '{"number":8,"body":"Le corps.\n"}'
  ouvre "feat(1.2): essai"
  assert_eq 0 "$rc" "la PR est ouverte (messages : $err)"
  assert_contains "PR n° 8 ouverte : $branche → dev" "$out" "le numéro et la base sont donnés"
}

case_ouverture_refusee_par_le_garde_fou_rend_1() {
  projet
  : > "$work/garde-refuse"
  ouvre "feat(1.2): essai"
  assert_eq 1 "$rc" "le garde-fou refuse la branche : écart constaté"
  assert_contains "le garde-fou public/privé refuse la branche" "$err" "le refus le dit"
  aucune_ecriture
}

case_ouverture_titre_avec_motif_prive_rend_1() {
  projet
  ouvre "feat(1.2): MOTIF-FACTICE"
  assert_eq 1 "$rc" "un motif privé dans le titre : écart constaté"
  assert_contains "le titre ou le corps contient un motif privé" "$err" "le refus le dit, sans le motif"
  [[ $err != *MOTIF-FACTICE* ]] || { echo "le refus affiche le motif" >&2; exit 1; }
  aucune_ecriture
}

case_ouverture_branche_non_poussee_sur_ce_commit_rend_1() {
  projet
  git -C "$depot" checkout -q "$branche"
  printf 'v3\n' > "$depot/code.txt"
  commit_all "feat(1.2): suite, pas encore poussée" > /dev/null
  ouvre "feat(1.2): essai"
  assert_eq 1 "$rc" "la branche locale est en avance sur la forge : écart constaté"
  assert_contains "la branche $branche n'est pas poussée sur ce commit" "$err" "le refus le dit"
  aucune_ecriture
}

case_ouverture_pr_deja_ouverte_rend_1() {
  projet
  api GET "/repos/$repo/pulls?state=open&limit=50&page=1" "$(jq -nc --arg b "$branche" '[{number: 7, head: {ref: $b}}]')"
  ouvre "feat(1.2): essai"
  assert_eq 1 "$rc" "une PR déjà ouverte pour la branche : écart constaté"
  assert_contains "une PR est déjà ouverte pour $branche : n° 7" "$err" "le refus donne son numéro"
  aucune_ecriture
}

case_ouverture_corps_publie_different_rend_1() {
  projet
  api GET "/repos/$repo/pulls?state=open&limit=50&page=1" '[]'
  api POST "/repos/$repo/pulls" '{"number":8}' 201
  api GET "/repos/$repo/pulls/8" '{"number":8,"body":"Un autre corps.\n"}'
  ouvre "feat(1.2): essai"
  assert_eq 1 "$rc" "le corps publié diffère du fichier : écart constaté"
  assert_contains "son corps publié diffère du fichier" "$err" "le refus le dit"
}

case_ouverture_creation_refusee_par_la_forge_rend_2() {
  projet
  api GET "/repos/$repo/pulls?state=open&limit=50&page=1" '[]'
  api POST "/repos/$repo/pulls" '{"message":"refus"}' 422
  ouvre "feat(1.2): essai"
  assert_eq 2 "$rc" "la forge refuse la création : l'ouverture n'a pas eu lieu, code 2"
  assert_contains "la forge refuse la création (HTTP 422)" "$err" "le message le dit"
}

# --- llm-review : un projet qui consomme un sous-module --------------------------------------------

faux_agy() { # le relecteur simulé : note le contenu de sa copie, puis rend un rapport favorable
  {
    printf '#!/usr/bin/env bash\nw=%q\n' "$work"
    cat <<'FAUX'
(cd "$PWD" && find . -type f | LC_ALL=C sort) > "$w/copie-vue"
jeton=$(sed -n 's/^# jeton-de-lecture: //p' REVIEW-DIFF.patch)
cp REVIEW-DIFF.patch "$w/diff-vu"
printf 'JETON: %s\n\nRien à signaler.\n\nVERDICT: NON BLOQUANT — aucune\n' "$jeton"
FAUX
  } > "$work/bin/agy"
  chmod +x "$work/bin/agy"
}

# Le projet consomme un sous-module « commun » ; la PR en monte la version.
# $@ = changements du workflow.config, passés à projet
projet_avec_sous_module() {
  projet "$@"
  local commun=$work/commun
  mkdir -p "$commun"
  git -C "$commun" init -q
  git -C "$commun" config user.name essai
  git -C "$commun" config user.email essai@example.invalid
  printf 'echo outil v1\n' > "$commun/outil.sh"
  git -C "$commun" add -A && git -C "$commun" commit -q -m "outil v1"
  git -C "$depot" -c protocol.file.allow=always submodule add -q "$commun" commun
  git -C "$depot" commit -q -m "le sous-module"
  git -C "$depot" push -q "$nu" dev
  git -C "$depot" checkout -q "$branche" 2>/dev/null
  git -C "$depot" rebase -q dev
  printf 'echo outil v2\n' > "$commun/outil.sh"
  git -C "$commun" commit -q -am "outil v2"
  git -C "$depot/commun" -c protocol.file.allow=always fetch -q origin
  git -C "$depot/commun" checkout -q origin/HEAD 2>/dev/null || git -C "$depot/commun" checkout -q "$(git -C "$commun" rev-parse HEAD)"
  git -C "$depot" add commun
  git -C "$depot" commit -q -m "chore: monte le sous-module"
  git -C "$depot" push -q -f "$nu" "$branche"
  git -C "$depot" checkout -q dev
  faux_agy
  forge_prete
  api POST "/repos/$repo/issues/$pr/comments" '{}' 201
}

revue() { # AUTHOR_LLM est transmis s'il est posé : « AUTHOR_LLM=gpt revue » ; $@ = arguments de plus
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run env PATH="$work/bin:$PATH" GIT_SSH_COMMAND="$work/bin/ssh" TMPDIR="$work" \
    bash -c 'cd "$1" && shift && bash "$@"' _ "$depot" "$common/review/llm-review.sh" "$pr" "$@"
}

case_revue_exporte_le_sous_module() {
  projet_avec_sous_module
  revue
  assert_eq 0 "$rc" "la revue est publiée (messages : $err)"
  assert_contains "./commun/outil.sh" "$(cat "$work/copie-vue")" "le relecteur voit le code du sous-module"
  assert_contains "echo outil v2" "$(cat "$work/diff-vu")" "la montée se lit comme le diff du code du sous-module"
  assert_eq "llm-review sha=$(tete) base=dev model=gemini-3.1-pro-high verdict=pass" \
    "$(jq -r .body "$work/corps" | head -n 1)" "première ligne du rapport publié"
}

# Un dossier de sous-module vide : clone sans « submodule update », ou « submodule deinit ». Sans .git
# à lui, « git -C <dossier> » y interroge le dépôt PARENT.
sous_module_vide() {
  git -C "$depot" submodule deinit -q -f commun
  rm -rf "$depot/.git/modules/commun"
  [[ -d $depot/commun && ! -e $depot/commun/.git ]] \
    || { echo "préparation : dossier du sous-module attendu, sans .git" >&2; exit 1; }
}

# La revue refuse en 2 (elle ne peut pas conclure), sans lancer le relecteur ni rien publier.
# $1 = la raison, entre parenthèses dans le message : chaque garde est reconnue à la sienne.
revue_refusee_sous_module_non_initialise() {
  revue
  assert_eq 2 "$rc" "un sous-module non initialisé : la revue ne peut pas conclure (messages : $err)"
  assert_contains "sous-module commun non initialisé ($1)" "$err" "le message nomme le sous-module et la garde"
  assert_contains "git submodule update --init" "$err" "le message nomme le remède"
  [[ ! -e $work/copie-vue ]] || { echo "le relecteur a été lancé sur une copie incomplète" >&2; exit 1; }
  seule_l_alerte llm-review
}

case_revue_sous_module_non_initialise() {
  # le dépôt parent n'a pas le commit du sous-module : le refus ne doit pas tenir à ce hasard
  projet_avec_sous_module
  sous_module_vide
  ! git -C "$depot" cat-file -e "$(git -C "$depot" rev-parse "$branche:commun")^{commit}" 2>/dev/null \
    || { echo "préparation : le dépôt parent a déjà le commit du sous-module" >&2; exit 1; }
  revue_refusee_sous_module_non_initialise "son dossier relève du dépôt parent"
}

case_revue_sous_module_vide_et_commit_dans_le_parent() {
  # le dépôt parent a le commit du sous-module (récupéré par un « git fetch », par exemple) : « git -C
  # <dossier vide> » le trouve, et « git archive », lancé depuis ce sous-dossier du parent, n'en exporte
  # que le sous-arbre « commun/ » de ce commit, vide. Sans refus, le relecteur verrait un dossier vide.
  projet_avec_sous_module
  sous_module_vide
  git -C "$depot" -c protocol.file.allow=always fetch -q "$work/commun" HEAD
  git -C "$depot" cat-file -e "$(git -C "$depot" rev-parse "$branche:commun")^{commit}" \
    || { echo "préparation : le dépôt parent n'a pas le commit du sous-module" >&2; exit 1; }
  revue_refusee_sous_module_non_initialise "son dossier relève du dépôt parent"
}

case_revue_sous_module_au_git_invalide() {
  # un .git présent mais qui n'est pas un dépôt (dossier vide) : git l'ignore et remonte au parent, qui a
  # le commit. La présence d'un .git ne suffit pas : le sous-module doit être sa propre racine.
  projet_avec_sous_module
  sous_module_vide
  mkdir "$depot/commun/.git"
  git -C "$depot" -c protocol.file.allow=always fetch -q "$work/commun" HEAD
  revue_refusee_sous_module_non_initialise "son dossier relève du dépôt parent"
}

case_revue_sous_module_illisible() {
  # un .git qui désigne un dépôt absent : git refuse de lire le dossier, au lieu de remonter au parent
  projet_avec_sous_module
  sous_module_vide
  printf 'gitdir: %s\n' "$work/nulle-part" > "$depot/commun/.git"
  revue_refusee_sous_module_non_initialise "git ne le lit pas"
}

case_revue_sous_module_supprime() {
  # une PR qui supprime le sous-module : git écrit « (submodule deleted) », sans contenu, qu'il ait ou non
  # l'ancien commit — la suppression se lit dans le diff, et la revue a lieu
  projet_avec_sous_module
  git -C "$depot" checkout -q "$branche"
  git -C "$depot" rm -q commun
  git -C "$depot" commit -q -m "chore: retire le sous-module"
  git -C "$depot" push -q -f "$nu" "$branche"
  git -C "$depot" checkout -q dev
  rm -rf "$depot/.git/modules/commun"
  forge_prete
  revue
  assert_eq 0 "$rc" "la revue est publiée (messages : $err)"
  assert_contains "Submodule commun " "$(cat "$work/diff-vu")" "le diff nomme le sous-module"
  assert_contains "(submodule deleted)" "$(cat "$work/diff-vu")" "la suppression se lit dans le diff"
}

case_revue_sous_module_sans_le_commit_de_la_base() {
  # initialisé, avec le commit de la tête, mais sans celui de la base : « git diff --submodule=diff »
  # n'écrirait que « (commits not present) », en code 0, et la montée ne se lirait plus comme un diff.
  # La tête épingle un commit sans parent, puis tout ce qui n'en descend pas est purgé du sous-module.
  projet_avec_sous_module
  git -C "$work/commun" checkout -q --orphan seul
  printf 'echo outil v3\n' > "$work/commun/outil.sh"
  git -C "$work/commun" commit -q -am "outil v3"
  local v3
  v3=$(git -C "$work/commun" rev-parse HEAD)
  git -C "$depot/commun" -c protocol.file.allow=always fetch -q origin seul
  git -C "$depot/commun" checkout -q "$v3"
  git -C "$depot/commun" for-each-ref --format='%(refname)' | while read -r ref; do
    git -C "$depot/commun" update-ref -d "$ref"
  done
  git -C "$depot/commun" reflog expire --expire=now --all
  git -C "$depot/commun" gc -q --prune=now
  git -C "$depot" checkout -q "$branche"
  git -C "$depot" add commun
  git -C "$depot" commit -q -m "chore: monte le sous-module en v3"
  git -C "$depot" push -q -f "$nu" "$branche"
  git -C "$depot" checkout -q dev
  ! git -C "$depot/commun" cat-file -e "$(git -C "$depot" rev-parse dev:commun)^{commit}" 2>/dev/null \
    || { echo "préparation : le commit de la base est encore dans le sous-module" >&2; exit 1; }
  forge_prete
  revue
  assert_eq 2 "$rc" "un sous-module sans le commit de la base : la revue ne peut pas conclure (messages : $err)"
  assert_contains "sous-module commun sans le commit $(git -C "$depot" rev-parse --short=7 dev:commun) de la base" "$err" "le message nomme le cas"
  [[ ! -e $work/copie-vue ]] || { echo "le relecteur a été lancé sur une copie incomplète" >&2; exit 1; }
  seule_l_alerte llm-review
}

case_revue_export_vide_du_sous_module() {
  # ceinture : si git exportait encore, pour un sous-module, une archive sans entrée, la copie n'aurait
  # pas son code. Le faux git rend une archive vide, en code 0.
  projet_avec_sous_module
  {
    printf '#!/usr/bin/env bash\nvrai=%q\n' "$(command -v git)"
    cat <<'FAUX'
if [[ "$*" == *"/commun archive "* ]]; then
  while (($#)); do
    [[ $1 != -o ]] || { tar -c -f "$2" -T /dev/null; exit; }
    shift
  done
  exec tar -c -f - -T /dev/null
fi
exec "$vrai" "$@"
FAUX
  } > "$work/bin/git"
  chmod +x "$work/bin/git"
  revue
  assert_eq 2 "$rc" "un export vide du sous-module : la revue ne peut pas conclure (messages : $err)"
  assert_contains "export du sous-module commun vide" "$err" "le message nomme le sous-module"
  [[ ! -e $work/copie-vue ]] || { echo "le relecteur a été lancé sur une copie incomplète" >&2; exit 1; }
  seule_l_alerte llm-review
}

case_revue_sous_module_sans_le_commit() {
  # initialisé, mais sans le commit que la PR épingle : la revue s'arrête, comme sans sous-module
  projet_avec_sous_module
  local v1
  v1=$(git -C "$depot/commun" rev-parse HEAD~1)
  git -C "$depot/commun" checkout -q "$v1"
  git -C "$depot/commun" for-each-ref --format='%(refname)' | while read -r ref; do
    git -C "$depot/commun" update-ref -d "$ref"
  done
  git -C "$depot/commun" reflog expire --expire=now --all
  git -C "$depot/commun" gc -q --prune=now
  ! git -C "$depot/commun" cat-file -e "$(git -C "$depot" rev-parse "origin/$branche:commun" 2>/dev/null || git -C "$depot" rev-parse "$branche:commun")^{commit}" 2>/dev/null \
    || { echo "préparation : le commit épinglé est encore là" >&2; exit 1; }
  revue
  assert_eq 2 "$rc" "un sous-module sans le commit épinglé : la revue ne peut pas conclure"
  assert_contains "sans le commit" "$err" "le message nomme le cas"
  [[ ! -e $work/copie-vue ]] || { echo "le relecteur a été lancé sur une copie incomplète" >&2; exit 1; }
  seule_l_alerte llm-review
}

# Un faux binaire qui échoue quand ses arguments contiennent les deux motifs donnés, et délègue au vrai
# sinon : chaque garde de l'export des sous-modules est éprouvée sur l'échec qu'elle doit arrêter.
faux_qui_echoue() { # $1 binaire, $2 et $3 motifs (expressions de [[ =~ ]]) cherchés dans « $* », $4 code (1)
  local vrai
  vrai=$(command -v "$1") || { echo "préparation : $1 introuvable" >&2; exit 1; }
  # shellcheck disable=SC2016 # faux binaire écrit sur le disque : ses « $ » s'y développent à l'exécution
  printf '#!/usr/bin/env bash\nm1=%q m2=%q\n[[ "$*" =~ $m1 && "$*" =~ $m2 ]] && exit %q\nexec %q "$@"\n' "$2" "$3" "${4:-1}" "$vrai" > "$work/bin/$1"
  chmod +x "$work/bin/$1"
}

revue_refusee() { # $1 message attendu ; la revue n'a pas pu conclure : 2, et l'alerte sur la PR
  revue
  assert_eq 2 "$rc" "la revue ne peut pas conclure (messages : $err)"
  assert_contains "$1" "$err" "le message nomme l'étape"
  [[ ! -e $work/copie-vue ]] || { echo "le relecteur a été lancé sur une copie incomplète" >&2; exit 1; }
  seule_l_alerte llm-review
}

case_revue_arbre_du_commit_illisible() {
  projet_avec_sous_module
  faux_qui_echoue git 'ls-tree' '-z'
  revue_refusee "lecture de l'arbre du commit relu impossible"
}

case_revue_dossier_du_sous_module_impossible() {
  projet_avec_sous_module
  faux_qui_echoue mkdir '-p' '/copie/commun$'
  revue_refusee "création de commun dans la copie isolée impossible"
}

case_revue_export_du_sous_module_impossible() {
  projet_avec_sous_module
  faux_qui_echoue git '/commun ' 'archive'
  revue_refusee "export du sous-module commun impossible"
}

case_revue_export_du_sous_module_illisible() {
  projet_avec_sous_module
  faux_qui_echoue tar '-t' 'sous-module\.tar'
  revue_refusee "export du sous-module commun illisible"
}

case_revue_extraction_du_sous_module_impossible() {
  projet_avec_sous_module
  faux_qui_echoue tar '-x' 'sous-module\.tar'
  revue_refusee "export du sous-module commun impossible"
}

case_revue_liste_des_sous_modules_modifies_impossible() {
  projet_avec_sous_module
  faux_qui_echoue git '^diff ' '--raw'
  revue_refusee "diff de la PR impossible"
}

case_revue_diff_de_la_pr_impossible() {
  projet_avec_sous_module
  faux_qui_echoue git '^diff ' '--submodule=diff'
  revue_refusee "diff de la PR impossible"
}

# --- llm-review : trois codes. 1 = ce qu'on s'apprêtait à envoyer ou publier est refusé à raison ; 2 = la
# revue n'a pas pu avoir lieu. Un 2 rendu une fois la PR connue est publié en alerte sur la PR.

# Un relecteur simulé de rechange ; $1 = la réponse, où « @JETON@ » devient le jeton de lecture de la copie.
faux_agy_qui_repond() {
  printf '%s\n' "$1" > "$work/reponse-agy"
  {
    printf '#!/usr/bin/env bash\nw=%q\n' "$work"
    # shellcheck disable=SC2016 # faux relecteur écrit sur le disque : ses « $ » s'y développent à l'exécution
    printf '%s\n' 'jeton=$(sed -n "s/^# jeton-de-lecture: //p" REVIEW-DIFF.patch)' 'sed "s/@JETON@/$jeton/" "$w/reponse-agy"'
  } > "$work/bin/agy"
  chmod +x "$work/bin/agy"
}

revue_refus_constate() { # $1 message attendu : 1, rien publié, aucune alerte
  revue "${@:2}"
  assert_eq 1 "$rc" "un envoi ou une publication refusé à raison : écart constaté (messages : $err)"
  assert_contains "$1" "$err" "le message nomme le refus"
  aucune_ecriture
}

case_revue_garde_fou_refuse_rend_1() {
  projet_avec_sous_module
  : > "$work/garde-refuse"
  revue_refus_constate "le garde-fou public/privé refuse le périmètre relu"
  [[ ! -e $work/copie-vue ]] || { echo "le relecteur a été lancé malgré le garde-fou" >&2; exit 1; }
}

case_revue_chemin_prive_dans_la_copie_rend_1() {
  projet_avec_sous_module
  git -C "$depot" checkout -q "$branche"
  mkdir -p "$depot/docs/private"
  printf 'note\n' > "$depot/docs/private/note.md"
  commit_all "docs: une note privée" > /dev/null
  git -C "$depot" push -q -f "$nu" "$branche"
  git -C "$depot" checkout -q dev
  forge_prete
  revue_refus_constate "la copie isolée contient docs/private"
}

case_revue_contexte_avec_motif_prive_rend_1() {
  projet_avec_sous_module
  printf 'précision : MOTIF-FACTICE\n' > "$work/contexte.md"
  revue_refus_constate "le fichier de contexte contient un motif privé" --context "$work/contexte.md"
  assert_eq "" "$(appels)" "la forge n'est pas même lue"
}

case_revue_rapport_avec_motif_prive_rend_1() {
  projet_avec_sous_module
  faux_agy_qui_repond "$(printf 'JETON: @JETON@\n\nCite MOTIF-FACTICE.\n\nVERDICT: NON BLOQUANT — aucune')"
  revue_refus_constate "le rapport contient un motif privé"
}

case_revue_relecteur_introuvable_rend_2() {
  projet_avec_sous_module
  rm -f "$work/bin/agy"
  # le PATH du cas sans aucun dossier qui porte un agy : celui du poste, s'il y en a un, n'est pas vu
  local sans_agy="" dossier dossiers
  IFS=: read -r -a dossiers <<< "$PATH"
  for dossier in "${dossiers[@]}"; do [[ -x $dossier/agy ]] || sans_agy+="${sans_agy:+:}$dossier"; done
  PATH=$sans_agy revue
  assert_eq 2 "$rc" "agy introuvable : prérequis du poste, code 2"
  assert_contains "agy est introuvable" "$err" "le message nomme l'outil"
  assert_eq "" "$(appels)" "rien n'est lu ni publié avant de connaître la PR"
}

case_revue_pr_fermee_rend_2_et_alerte() {
  projet_avec_sous_module
  api GET "/repos/$repo/pulls/$pr" "$(pr_json "$(tete)" | jq -c '.state = "closed"')"
  revue
  assert_eq 2 "$rc" "une PR fermée : rien à relire, code 2"
  assert_contains "la PR n° $pr n'est pas ouverte" "$err" "le message le dit"
  seule_l_alerte llm-review
}

case_revue_rapport_sans_jeton_rend_2_et_alerte() {
  projet_avec_sous_module
  faux_agy_qui_repond "$(printf 'Rien à signaler.\n\nVERDICT: NON BLOQUANT — aucune')"
  revue
  assert_eq 2 "$rc" "un rapport qui ne cite pas le jeton : pas une revue, code 2"
  assert_contains "ne cite pas le jeton de lecture" "$err" "le message le dit"
  seule_l_alerte llm-review
}

case_revue_verdict_illisible_rend_2_et_alerte() {
  projet_avec_sous_module
  faux_agy_qui_repond "$(printf 'JETON: @JETON@\n\nRien à signaler.')"
  revue
  assert_eq 2 "$rc" "aucun verdict lisible : code 2"
  assert_contains "pas un verdict lisible" "$err" "le message le dit"
  seule_l_alerte llm-review
}

case_revue_relecteur_qui_echoue_rend_2_et_alerte() {
  projet_avec_sous_module
  printf '#!/bin/sh\nexit 124\n' > "$work/bin/agy"
  revue
  assert_eq 2 "$rc" "un relecteur qui n'aboutit pas : code 2"
  assert_contains "le relecteur n'a pas abouti (code 124" "$err" "le message donne son code"
  seule_l_alerte llm-review
}

case_revue_commande_shell_tentee_rend_2_et_alerte() {
  projet_avec_sous_module
  printf '#!/bin/sh\necho "permission denied: run_command" >&2\nexit 0\n' > "$work/bin/agy"
  revue
  assert_eq 2 "$rc" "une commande shell tentée par le relecteur : pas de revue, code 2"
  assert_contains "le relecteur a tenté une commande shell" "$err" "le message le dit"
  seule_l_alerte llm-review
}

case_revue_pr_illisible_alerte_des_la_lecture() {
  # la forge répond 200, mais un corps que jq ne lit pas : la PR existe, l'alerte part déjà
  projet_avec_sous_module
  api GET "/repos/$repo/pulls/$pr" 'pas du json'
  revue
  assert_eq 2 "$rc" "réponse illisible : code 2"
  assert_contains "réponse de la forge illisible pour la PR n° $pr" "$err" "le message le dit"
  seule_l_alerte llm-review
}

# Le rapport ajouté au fichier de story, depuis la branche de la PR, qui a sa section « Revue du code ».
sur_la_branche_avec_section() {
  git -C "$depot" checkout -q "$branche"
  printf '\n## Revue du code\n' >> "$depot/$stories/1-2-essai.md"
  cp "$depot/$stories/1-2-essai.md" "$work/story-avant.md"
}

case_revue_keyed_rapport_ajoute_au_fichier_de_l_alias() {
  forme_du_suivi=keyed
  projet_avec_sous_module "${keyed_config[@]}"
  sur_la_branche_avec_section
  revue
  assert_eq 0 "$rc" "la revue est publiée en keyed (messages : $err)"
  assert_contains "Rien à signaler." "$(cat "$depot/$stories/1-2-essai.md")" "le rapport est dans le fichier qui porte l'alias"
}

case_revue_keyed_sans_suivi_dans_l_arbre() {
  # Une PR qui ajoute le suivi : l'arbre de travail n'en a pas encore. Pas de story, et aucune erreur de
  # redirection ne fuit ni ne passe pour « aucune story ».
  forme_du_suivi=keyed
  projet_avec_sous_module "${keyed_config[@]}"
  git -C "$depot" checkout -q "$branche"
  rm "$depot/$stories/sprint-status.yaml"
  revue
  assert_eq 0 "$rc" "la revue est publiée sans suivi dans l'arbre (messages : $err)"
  [[ $err != *"No such file"* && $err != *"Aucun fichier"* ]] || { echo "erreur de redirection affichée : $err" >&2; exit 1; }
  assert_contains "aucune story associée" "$err" "le script dit qu'il n'a pas de story"
}

case_revue_keyed_branche_ambigue_rend_2() {
  forme_du_suivi=keyed
  suivi_ambigu=1
  projet_avec_sous_module "${keyed_config[@]}"
  git -C "$depot" checkout -q "$branche"
  revue
  assert_eq 2 "$rc" "deux stories pour la branche : la revue ne peut pas conclure"
  assert_contains "ambiguë dans le suivi de sprint" "$err" "la raison"
}

case_revue_rapport_ajoute_au_fichier_de_story() {
  projet_avec_sous_module
  sur_la_branche_avec_section
  revue
  assert_eq 0 "$rc" "la revue est publiée et le rapport ajouté (messages : $err)"
  assert_contains "Rien à signaler." "$(cat "$depot/$stories/1-2-essai.md")" "le rapport est dans la section"
}

case_revue_comparaison_du_fichier_de_story_impossible_rend_2() {
  projet_avec_sous_module
  sur_la_branche_avec_section
  faux_qui_echoue diff 'story' 'story\.md' 2
  revue
  assert_eq 2 "$rc" "un diff en erreur n'est jamais lu comme « rien de supprimé » (messages : $err)"
  assert_contains "comparaison du fichier de story impossible (diff, code 2)" "$err" "le message le dit"
  assert_eq "$(cat "$work/story-avant.md")" "$(cat "$depot/$stories/1-2-essai.md")" "le fichier de story est inchangé"
}

case_revue_mise_a_jour_qui_supprimerait_une_ligne_rend_2() {
  # un awk qui perd la première ligne du fichier de story : la garde doit refuser d'écrire
  projet_avec_sous_module
  sur_la_branche_avec_section
  local vrai
  vrai=$(command -v awk)
  # shellcheck disable=SC2016 # faux awk écrit sur le disque : ses « $ » s'y développent à l'exécution
  printf '#!/usr/bin/env bash\nif [[ "$*" == *"section="* ]]; then %q "$@" | tail -n +2; else exec %q "$@"; fi\n' "$vrai" "$vrai" > "$work/bin/awk"
  chmod +x "$work/bin/awk"
  revue
  assert_eq 2 "$rc" "une mise à jour qui supprimerait une ligne est refusée (messages : $err)"
  assert_contains "la mise à jour supprimerait des lignes" "$err" "le message le dit"
  assert_eq "$(cat "$work/story-avant.md")" "$(cat "$depot/$stories/1-2-essai.md")" "le fichier de story est inchangé"
}

case_revue_forge_qui_refuse_le_rapport_rend_2() {
  projet_avec_sous_module
  api POST "/repos/$repo/issues/$pr/comments" '{"message":"refus"}' 403
  revue
  assert_eq 2 "$rc" "la forge refuse le rapport : la revue n'est pas publiée, code 2"
  assert_contains "la forge refuse le commentaire (HTTP 403)" "$err" "le message le dit"
  assert_contains "alerte non publiée sur la PR n° $pr (HTTP 403)" "$err" "l'alerte non plus, et le terminal le dit"
}

# --- llm-review : la table « fournisseur de l'auteur → relecteur » (review.reviewers) -------------

# Le projet nominal, avec la table donnée ; $1 = valeur de review.reviewers
projet_avec_table() {
  projet "review.reviewers=$1"
  faux_agy
  forge_prete
  api POST "/repos/$repo/issues/$pr/comments" '{}' 201
}

case_revue_auteur_couvert_relu_par_le_modele_de_sa_ligne() {
  local auteur modele
  for auteur in claude gemini gpt; do
    # chaque auteur sur un projet neuf : la forge simulée garde ses appels, ses corps et ses rangs
    rm -rf "${work:?}/depot" "${work:?}/forge" "${work:?}/bin" "${work:?}/api" "${work:?}/appels" \
      "${work:?}/corps" "${work:?}"/rang-* "${work:?}/copie-vue"
    projet_avec_table "claude=gemini-3.1-pro-high gemini=claude-opus-4-6-thinking gpt=claude-opus-5-5-high"
    case $auteur in
      claude) modele=gemini-3.1-pro-high ;;
      gemini) modele=claude-opus-4-6-thinking ;;
      gpt) modele=claude-opus-5-5-high ;;
    esac
    AUTHOR_LLM=$auteur revue
    assert_eq 0 "$rc" "auteur $auteur : la revue est publiée (messages : $err)"
    assert_eq "llm-review sha=$(tete) base=dev model=$modele verdict=pass" \
      "$(jq -r .body "$work/corps" | head -n 1)" "auteur $auteur : relu par le modèle de sa ligne"
  done
}

case_revue_auteur_non_couvert_rend_2_sans_relecteur() {
  projet_avec_table "claude=gemini-3.1-pro-high gemini=claude-opus-4-6-thinking"
  AUTHOR_LLM=gpt revue
  assert_eq 2 "$rc" "un fournisseur d'auteur sans entrée : la revue ne peut pas conclure"
  assert_contains "AUTHOR_LLM=gpt : fournisseur d'auteur absent de la table review.reviewers (couverts : claude gemini)" "$err" "le message nomme l'auteur et les fournisseurs couverts"
  [[ ! -e $work/copie-vue ]] || { echo "un relecteur a été appelé pour un auteur non couvert" >&2; exit 1; }
  assert_eq "" "$(appels)" "aucun appel à la forge"
  # une casse différente n'est pas une entrée : pas de rapprochement, pas de défaut
  AUTHOR_LLM=Claude revue
  assert_eq 2 "$rc" "« Claude » n'est pas « claude »"
  [[ ! -e $work/copie-vue ]] || { echo "un relecteur a été appelé pour « Claude »" >&2; exit 1; }
}

case_revue_relecteur_du_meme_fournisseur_rend_2() {
  projet_avec_table "claude=gemini-3.1-pro-high gemini=gemini-3.8-flash-high"
  AUTHOR_LLM=claude revue
  assert_eq 2 "$rc" "une table qui contourne la revue croisée est refusée, pour tout auteur"
  assert_contains "le relecteur est du même fournisseur que l'auteur (gemini)" "$err" "la ligne fautive est nommée"
  [[ ! -e $work/copie-vue ]] || { echo "un relecteur a été appelé malgré une table refusée" >&2; exit 1; }
  assert_eq "" "$(appels)" "aucun appel à la forge"
}

case_revue_anciennes_cles_rendent_2_avec_la_nouvelle_forme() {
  projet workflow.schema=2 -review.reviewers review.reviewer-for-claude=gemini-3.1-pro-high \
    review.reviewer-for-gemini=claude-opus-4-6-thinking
  faux_agy
  revue
  assert_eq 2 "$rc" "un workflow.config aux anciennes clés est refusé"
  assert_contains "review.reviewer-for-claude : retiré au schéma 3 : la table review.reviewers le remplace" "$err" "la nouvelle forme est nommée"
  [[ ! -e $work/copie-vue ]] || { echo "un relecteur a été appelé sur une configuration refusée" >&2; exit 1; }
  assert_eq "" "$(appels)" "aucun appel à la forge"
}

# --- verify-and-merge-pr : le substitut d'amorçage ------------------------------------------------
# --- verrou CI : étendue et attente (schéma 5 ; calculette#outillage-8, V12) ---------------------------

statut_ci() { # $1 état du workflow des contrôles, $2 rang de l'appel (tous)
  api GET "/repos/$repo/commits/$(tete)/status" \
    "$(jq -nc --arg e "$1" '{state: $e, statuses: [{context: "checks / checks (pull_request)", status: $e}]}')" 200 "${2:-}"
}

lectures_ci() { # nombre de lectures de l'état de CI de la tête
  local n=0 ligne
  while IFS= read -r ligne; do
    [[ $ligne != "GET /repos/$repo/commits/"*/status ]] || n=$((n + 1))
  done < <(appels)
  printf '%s' "$n"
}

case_audit_schema_4_refuse_sans_repli() {
  projet workflow.schema=4 -ci.statuses -ci.wait
  forge_prete
  verifie "$pr"
  assert_eq 2 "$rc" "un workflow.config au schéma 4 est refusé (messages : $err$out)"
  assert_contains "exige le schéma 5 (ci.statuses, ci.wait" "$err" "le schéma et les champs sont nommés"
  assert_eq "" "$(appels)" "refusé avant tout appel à la forge"
}

case_audit_ci_en_cours_sans_attente_bloque_tout_de_suite() {
  projet
  forge_prete
  statut_ci pending
  verifie "$pr"
  assert_eq 1 "$rc" "ci.wait = 0 : une CI en cours bloque (messages : $err)"
  verrou bloque "CI"
  assert_contains "en cours sur la tête : relancer l'audit quand elle est terminée." "$out" "le message d'avant le schéma 5"
  assert_eq 1 "$(lectures_ci)" "une seule lecture : aucune attente"
  aucune_ecriture
}

case_audit_ci_en_cours_attendue_puis_verte() {
  projet ci.wait=1
  forge_prete
  statut_ci success
  statut_ci pending 1
  verifie "$pr"
  assert_eq 0 "$rc" "la CI en cours est attendue, puis verte (messages : $err$out)"
  verrou passe "CI"
  assert_eq 2 "$(lectures_ci)" "deux lectures"
  assert_contains "CI en cours sur la tête" "$err" "l'attente est annoncée"
  aucune_ecriture
}

case_audit_ci_toujours_en_cours_apres_l_attente() {
  projet ci.wait=1
  forge_prete
  statut_ci pending
  verifie "$pr"
  assert_eq 1 "$rc" "l'attente épuisée bloque (messages : $err)"
  verrou bloque "CI"
  assert_contains "toujours en cours sur la tête après 1 s" "$out" "le message dit l'attente"
  assert_eq 2 "$(lectures_ci)" "la lecture d'origine et une relecture après l'attente"
  aucune_ecriture
}

case_audit_ci_sans_aucun_statut_jamais_attendue() {
  # le runner coincé : « pending » sans statut. Rien ne tourne, il n'y a rien à attendre.
  projet ci.wait=1 ci.statuses=all
  forge_prete
  api GET "/repos/$repo/commits/$(tete)/status" '{"state":"pending","statuses":[]}'
  verifie "$pr"
  assert_eq 1 "$rc" "aucun statut : refus immédiat (messages : $err)"
  assert_contains "aucun statut sur la tête" "$out" "le message dit que rien n'a démarré"
  assert_eq 1 "$(lectures_ci)" "aucune attente"
  aucune_ecriture
}

case_audit_ci_tous_les_statuts() {
  projet ci.statuses=all
  forge_prete
  api GET "/repos/$repo/commits/$(tete)/status" \
    '{"state":"failure","statuses":[{"context":"checks / checks (pull_request)","status":"success"},{"context":"audit / audit (push)","status":"failure"}]}'
  verifie "$pr"
  assert_eq 1 "$rc" "ci.statuses = all : un autre workflow en échec bloque (messages : $err)"
  verrou bloque "CI"
  assert_contains "état failure sur la tête" "$out" "l'état fautif est nommé"
  aucune_ecriture
}

case_audit_ci_contexte_seul() {
  projet ci.statuses=context
  forge_prete
  api GET "/repos/$repo/commits/$(tete)/status" \
    '{"state":"failure","statuses":[{"context":"checks / checks (pull_request)","status":"success"},{"context":"audit / audit (push)","status":"failure"}]}'
  verifie "$pr"
  assert_eq 0 "$rc" "ci.statuses = context : l'autre workflow ne décide pas (messages : $err)"
}

# Règle d'amorçage (ci.bootstrap = true) : le workflow ci.workflow est absent de la base, et la tête
# n'a aucun statut de CI. Le script lance alors lui-même checks.command, dans une copie de la tête
# créée par « git worktree add ». Une telle copie n'a AUCUN sous-module initialisé : leurs dossiers y
# sont vides. Un contrôle qui lit le sous-module sans en vérifier la présence y passerait à tort, et un
# contrôle qui la vérifie y refuserait sans avoir rien contrôlé. Le substitut peuple donc les
# sous-modules de la copie depuis ceux du dépôt de travail, sans réseau, ou refuse en 2.

# Le contrôle du projet (checks.command = scripts/check.sh), écrit AVANT la création du projet, pour
# être dans la base comme dans la tête. Il note toujours le dossier où il tourne : un cas qui refuse
# vérifie ainsi qu'il n'a pas été lancé. $1 = la suite du contrôle (sh), où « $w » est $work.
controle() {
  mkdir -p "$depot/scripts"
  {
    printf '#!/bin/sh\nw=%q\n' "$work"
    # shellcheck disable=SC2016 # contrôle écrit sur le disque : son « $w » s'y développe à l'exécution
    printf 'pwd > "$w/controle-lance"\n%s\n' "$1"
  } > "$depot/scripts/check.sh"
  chmod +x "$depot/scripts/check.sh"
}

# Le workflow de CI nommé n'existe pas sur la base : c'est la condition de la règle d'amorçage.
readonly sans_ci=ci.workflow=.gitea/workflows/absent.yaml

# La forge nominale, mais sans aucun statut de CI sur la tête.
forge_amorcage() {
  forge_prete
  api POST "/repos/$repo/issues/$pr/comments" '{}' 201
  api GET "/repos/$repo/commits/$(tete)/status" '{"state":"","statuses":[]}'
}

# L'audit, le dépôt d'origine du sous-module mis hors d'atteinte : la copie ne peut être peuplée que
# depuis le sous-module du dépôt de travail, jamais en clonant l'URL de .gitmodules.
verifie_amorcage() {
  [[ ! -d $work/commun ]] || mv "$work/commun" "$work/commun-hors-d-atteinte"
  verifie "$pr"
}

# La copie part avec l'audit, sous-modules compris : « git worktree add » range le dépôt d'un
# sous-module initialisé dans la copie sous .git/worktrees/<copie>/modules du dépôt de travail.
copie_retiree() {
  [[ ! -d $depot/.git/worktrees || -z $(ls -A "$depot/.git/worktrees") ]] \
    || { printf 'la copie de la tête est restée dans le dépôt de travail :\n%s\n' "$(ls -A "$depot/.git/worktrees")" >&2; exit 1; }
}

# Un refus du substitut faute de pouvoir construire une copie complète : code 2, le message attendu,
# le contrôle jamais lancé, rien écrit sur la forge, la copie retirée. $1 = le message attendu.
amorcage_refuse() {
  verifie_amorcage
  assert_eq 2 "$rc" "copie complète impossible : l'audit ne peut pas conclure (messages : $err)"
  assert_contains "$1" "$err" "le message nomme la cause"
  [[ ! -e $work/controle-lance ]] || { echo "le contrôle a été lancé sur une copie incomplète" >&2; exit 1; }
  seule_l_alerte verify-and-merge-pr
  copie_retiree
}

# Le contrôle de la forme d'un projet consommateur : il exige le sous-module, et refuse en 2 sinon.
# Il note aussi ce que git répond dans le sous-module : la racine du sous-module, à son commit.
# shellcheck disable=SC2016 # contrôle écrit sur le disque : son « $w » s'y développe à l'exécution
readonly controle_qui_exige_le_sous_module='[ -f commun/outil.sh ] || { echo "mécanisme des contrôles absent : sous-module non initialisé"; exit 2; }
git -C commun rev-parse --show-prefix HEAD > "$w/vu-par-git"'

case_amorcage_substitut_sans_sous_module() {
  # contre-épreuve : sans sous-module, le substitut tourne dans la copie et le verrou rend « absent »
  controle 'exit 0'
  projet "$sans_ci"
  forge_amorcage
  verifie_amorcage
  assert_eq 0 "$rc" "le substitut réussit (messages : $err)"
  verrou absent "CI"
  assert_contains "règle d'amorçage, substitut réussi (garde-fou (verrou 3), scripts/check.sh sur la tête)" "$out" "le substitut est nommé"
  [[ -f $work/controle-lance ]] || { echo "le contrôle n'a pas été lancé" >&2; exit 1; }
  [[ $(cat "$work/controle-lance") != "$depot" ]] || { echo "le contrôle a tourné dans le dépôt de travail" >&2; exit 1; }
  aucune_ecriture
  copie_retiree
}

case_amorcage_controle_voit_le_sous_module() {
  # La forme « passe à tort » : le contrôle refuse un motif dans les fichiers du sous-module, sans en
  # vérifier la présence. La version montée par la PR porte ce motif (« outil v2 ») : sur un dossier
  # vide, il ne trouverait rien à refuser, et le substitut réussirait sans avoir rien vu.
  # shellcheck disable=SC2016 # contrôle écrit sur le disque : ses « $ » s'y développent à l'exécution
  controle 'find commun -path commun/.git -prune -o -type f -print | LC_ALL=C sort > "$w/vu"
for f in $(cat "$w/vu"); do
  if grep -q "outil v2" "$f"; then echo "motif refusé dans $f"; exit 1; fi
done'
  projet_avec_sous_module "$sans_ci"
  forge_amorcage
  verifie_amorcage
  assert_eq 1 "$rc" "le motif refusé dans le sous-module bloque (messages : $err)"
  assert_eq "commun/outil.sh" "$(cat "$work/vu")" "le contrôle voit le fichier du sous-module"
  verrou bloque "CI"
  assert_contains "motif refusé dans commun/outil.sh" "$out" "la sortie du contrôle est rendue"
  aucune_ecriture
  copie_retiree
}

case_amorcage_controle_qui_exige_le_sous_module() {
  # La forme qui bloquait à tort : le contrôle exige le sous-module et refuse en 2 s'il manque. Dans
  # la copie, git doit répondre pour le sous-module lui-même, au commit que la tête épingle.
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  forge_amorcage
  verifie_amorcage
  assert_eq 0 "$rc" "le substitut réussit (messages : $err ; sortie : $out)"
  verrou absent "CI"
  assert_eq "$(printf '\n%s' "$(git -C "$depot" rev-parse "$branche:commun")")" "$(cat "$work/vu-par-git")" \
    "dans la copie, git répond pour le sous-module, au commit de la tête"
  aucune_ecriture
  copie_retiree
}

case_amorcage_sous_module_non_initialise() {
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  forge_amorcage
  sous_module_vide
  ! git -C "$depot" cat-file -e "$(git -C "$depot" rev-parse "$branche:commun")^{commit}" 2>/dev/null \
    || { echo "préparation : le dépôt parent a déjà le commit du sous-module" >&2; exit 1; }
  amorcage_refuse "sous-module commun non initialisé (son dossier relève du dépôt parent) : « git submodule update --init »"
}

case_amorcage_sous_module_vide_et_commit_dans_le_parent() {
  # le dépôt parent a le commit du sous-module : « git -C <dossier vide> » le trouve. Seule la garde
  # « --show-prefix » voit que git a répondu pour le parent.
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  forge_amorcage
  sous_module_vide
  git -C "$depot" -c protocol.file.allow=always fetch -q "$work/commun" HEAD
  git -C "$depot" cat-file -e "$(git -C "$depot" rev-parse "$branche:commun")^{commit}" \
    || { echo "préparation : le dépôt parent n'a pas le commit du sous-module" >&2; exit 1; }
  amorcage_refuse "sous-module commun non initialisé (son dossier relève du dépôt parent)"
}

case_amorcage_sous_module_illisible() {
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  forge_amorcage
  sous_module_vide
  printf 'gitdir: %s\n' "$work/nulle-part" > "$depot/commun/.git"
  amorcage_refuse "sous-module commun non initialisé (git ne le lit pas)"
}

case_amorcage_sous_module_sans_le_commit() {
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  forge_amorcage
  local v1 epingle
  epingle=$(git -C "$depot" rev-parse "$branche:commun")
  v1=$(git -C "$depot/commun" rev-parse HEAD~1)
  git -C "$depot/commun" checkout -q "$v1"
  git -C "$depot/commun" for-each-ref --format='%(refname)' | while read -r ref; do
    git -C "$depot/commun" update-ref -d "$ref"
  done
  git -C "$depot/commun" reflog expire --expire=now --all
  git -C "$depot/commun" gc -q --prune=now
  ! git -C "$depot/commun" cat-file -e "$epingle^{commit}" 2>/dev/null \
    || { echo "préparation : le commit épinglé est encore là" >&2; exit 1; }
  amorcage_refuse "sous-module commun sans le commit ${epingle:0:7} de la tête"
}

case_amorcage_sous_module_imbrique() {
  # le commit épinglé contient lui-même un sous-module : le substitut ne peuple pas les sous-modules
  # imbriqués, et le dit, plutôt que de lancer le contrôle sur une copie où l'un d'eux serait vide
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  git -C "$work/commun" update-index --add --cacheinfo "160000,$(git -C "$work/commun" rev-parse HEAD),imbrique"
  git -C "$work/commun" commit -q -m "un sous-module imbriqué"
  git -C "$depot/commun" -c protocol.file.allow=always fetch -q origin
  git -C "$depot/commun" checkout -q "$(git -C "$work/commun" rev-parse HEAD)"
  git -C "$depot" checkout -q "$branche"
  git -C "$depot" add commun
  git -C "$depot" commit -q -m "chore: monte le sous-module imbriquant"
  git -C "$depot" push -q -f "$nu" "$branche"
  git -C "$depot" checkout -q dev
  forge_amorcage
  amorcage_refuse "sous-module commun contient lui-même un sous-module (imbrique)"
}

case_amorcage_sous_module_absent_de_gitmodules() {
  # un sous-module sans entrée dans le .gitmodules de la tête : rien ne dit où le peupler
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  git -C "$depot" checkout -q "$branche"
  git -C "$depot" config -f .gitmodules --remove-section submodule.commun
  git -C "$depot" add .gitmodules
  git -C "$depot" commit -q -m "chore: retire l'entrée du sous-module"
  git -C "$depot" push -q -f "$nu" "$branche"
  git -C "$depot" checkout -q dev
  forge_amorcage
  amorcage_refuse "sous-module commun absent du .gitmodules de la tête"
}

case_amorcage_gitmodules_illisible() {
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  forge_amorcage
  # code 128, celui d'une lecture impossible : le code 1 de git config veut dire « aucune entrée »
  faux_qui_echoue git 'config' '--blob' 128
  amorcage_refuse "lecture du .gitmodules de la tête impossible"
}

case_amorcage_arbre_de_la_tete_illisible() {
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  forge_amorcage
  faux_qui_echoue git '^ls-tree ' '-z'
  amorcage_refuse "lecture de l'arbre de la tête impossible"
}

case_amorcage_arbre_du_sous_module_illisible() {
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  forge_amorcage
  faux_qui_echoue git '/commun ' 'ls-tree'
  amorcage_refuse "lecture de l'arbre du sous-module commun impossible"
}

case_amorcage_copie_impossible() {
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  forge_amorcage
  faux_qui_echoue git 'worktree' ' add '
  amorcage_refuse "création de la copie de la tête impossible"
}

case_amorcage_peuplement_impossible() {
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  forge_amorcage
  faux_qui_echoue git 'submodule' 'update'
  amorcage_refuse "peuplement du sous-module commun dans la copie impossible"
}

case_amorcage_peuplement_sans_effet() {
  # ceinture : un « submodule update » qui rend 0 sans rien extraire (un réglage qui le neutraliserait,
  # par exemple) laisserait le dossier vide. Le faux git rend 0 sans rien faire.
  controle "$controle_qui_exige_le_sous_module"
  projet_avec_sous_module "$sans_ci"
  forge_amorcage
  {
    printf '#!/usr/bin/env bash\nvrai=%q\n' "$(command -v git)"
    # shellcheck disable=SC2016 # faux git écrit sur le disque : ses « $ » s'y développent à l'exécution
    printf '[[ "$*" == *" submodule update "* ]] && exit 0\nexec "$vrai" "$@"\n'
  } > "$work/bin/git"
  chmod +x "$work/bin/git"
  amorcage_refuse "sous-module commun absent de la copie au commit $(git -C "$depot" rev-parse --short=7 "$branche:commun")"
}

run_case "$@"
