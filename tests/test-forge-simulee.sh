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

# --- le projet -----------------------------------------------------------------------------------

stories=_bmad-output/implementation-artifacts

suivi() { # $1 statut de la story 1.2 ; écrit le suivi et le fichier de story
  mkdir -p "$depot/$stories"
  printf 'last_updated: 2026-10-04\ndevelopment_status:\n  epic-1: in-progress\n  1-1-premiere: done\n  1-2-essai: %s\n  1-3-suivante: backlog\n' \
    "$1" > "$depot/$stories/sprint-status.yaml"
  printf '# Story 1.2\n\nStatus: %s\n' "$1" > "$depot/$stories/1-2-essai.md"
  printf '# Story 1.1\n\nStatus: done\n' > "$depot/$stories/1-1-premiere.md"
}

# Le projet : base dev avec sa CI, son garde-fou et son suivi ; puis la branche de la story 1.2, qui
# change du code et passe la story à done. Le dépôt nu de la forge porte les deux branches.
# $@ = changements du workflow.config
projet() {
  new_repo
  write_workflow_config "$depot" "forge.repo=$repo" guard.command=scripts/garde.sh guard.patterns-file=motifs.txt \
    review.project-layer=couche.md "$@"
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
  assert_contains "contrôle global (branche sans numéro de story)" "$out" "suivi : contrôle global"
  [[ $(appels) != *timeline* ]] || { echo "la timeline a été lue pour une PR exemptée" >&2; exit 1; }
  aucune_ecriture
}

case_audit_verrous_desactives_le_disent() {
  projet guard.command=none guard.patterns-file=none ci.workflow=none ci.status-context=none \
    sprint.convention=none sprint.status-file=none sprint.stories-dir=none sprint.spec-source=none
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
  verifie "$pr" --merge
  assert_eq 2 "$rc" "la tête a bougé pendant l'audit : anomalie"
  assert_contains "a bougé pendant l'audit" "$err" "raison"
  aucune_ecriture
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
projet_avec_sous_module() {
  projet
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

revue() { # AUTHOR_LLM est transmis s'il est posé : « AUTHOR_LLM=gpt revue »
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run env PATH="$work/bin:$PATH" GIT_SSH_COMMAND="$work/bin/ssh" TMPDIR="$work" \
    bash -c 'cd "$1" && shift && bash "$@"' _ "$depot" "$common/review/llm-review.sh" "$pr"
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

case_revue_sous_module_non_initialise() {
  projet_avec_sous_module
  git -C "$depot" submodule deinit -q -f commun
  rm -rf "$depot/.git/modules/commun"
  revue
  assert_eq 1 "$rc" "un sous-module absent arrête la revue"
  assert_contains "sous-module commun non initialisé" "$err" "le message nomme le sous-module et le remède"
  [[ ! -e $work/copie-vue ]] || { echo "le relecteur a été lancé sur une copie incomplète" >&2; exit 1; }
  aucune_ecriture
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
  assert_eq 1 "$rc" "un sous-module sans le commit épinglé arrête la revue"
  assert_contains "sans le commit" "$err" "le message nomme le cas"
  [[ ! -e $work/copie-vue ]] || { echo "le relecteur a été lancé sur une copie incomplète" >&2; exit 1; }
  aucune_ecriture
}

# Un faux binaire qui échoue quand ses arguments contiennent les deux motifs donnés, et délègue au vrai
# sinon : chaque garde de l'export des sous-modules est éprouvée sur l'échec qu'elle doit arrêter.
faux_qui_echoue() { # $1 binaire, $2 et $3 motifs (expressions de [[ =~ ]]) cherchés dans « $* »
  local vrai
  vrai=$(command -v "$1") || { echo "préparation : $1 introuvable" >&2; exit 1; }
  # shellcheck disable=SC2016 # faux binaire écrit sur le disque : ses « $ » s'y développent à l'exécution
  printf '#!/usr/bin/env bash\nm1=%q m2=%q\n[[ "$*" =~ $m1 && "$*" =~ $m2 ]] && exit 1\nexec %q "$@"\n' "$2" "$3" "$vrai" > "$work/bin/$1"
  chmod +x "$work/bin/$1"
}

revue_refusee() { # $1 message attendu
  revue
  assert_eq 1 "$rc" "la revue s'arrête"
  assert_contains "$1" "$err" "le message nomme l'étape"
  [[ ! -e $work/copie-vue ]] || { echo "le relecteur a été lancé sur une copie incomplète" >&2; exit 1; }
  aucune_ecriture
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

case_revue_diff_de_la_pr_impossible() {
  projet_avec_sous_module
  faux_qui_echoue git '^diff ' '--submodule=diff'
  revue_refusee "diff de la PR impossible"
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

run_case "$@"
