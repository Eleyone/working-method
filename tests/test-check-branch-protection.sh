#!/usr/bin/env bash
# Contrôle de la protection des branches (gitea/check-branch-protection.sh, lib/protection.sh), contre une
# forge simulée : la règle commune (procedures/gitea-branches.md, « La règle commune ») et les valeurs du
# projet (section [protection] de workflow.config, schéma 7). Origine : calculette#fix-protection-branches-dev-master.
#
# **Aucun réseau.** Un faux curl répond depuis $work/api, une réponse par « méthode chemin », et note
# chaque appel : le contrôle est en lecture seule, chaque cas vérifie qu'aucune écriture n'est partie.
# L'état conforme de la forge est construit à partir du workflow.config du cas ; chaque cas d'écart n'en
# change qu'un champ, pour prouver que ce champ-là, seul, fait sortir en 1.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly repo=Proprietaire/projet-essai
depot=$work/depot

faux_curl() {
  mkdir -p "$work/bin" "$work/api"
  {
    printf '#!/usr/bin/env bash\nw=%q\n' "$work"
    cat <<'FAUX'
cat > /dev/null # le jeton arrive par « -K - » : lu, jamais écrit
out="" methode=GET url="" format=""
while (($#)); do
  case $1 in
    -o) out=$2; shift 2 ;;
    -X) methode=$2; shift 2 ;;
    -w) format=$2; shift 2 ;;
    -K|-H|--data) shift 2 ;;
    -s) shift ;;
    *) url=$1; shift ;;
  esac
done
chemin=${url#*/api/v1}
cle=$(printf '%s %s' "$methode" "$chemin" | sed 's#[^A-Za-z0-9]#_#g')
printf '%s %s\n' "$methode" "$chemin" >> "$w/appels"
rep=$w/api/$cle
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
  chmod +x "$work/bin/curl"
}

api() { # $1 méthode, $2 chemin, $3 corps de la réponse, $4 code (200)
  local c
  c=$(printf '%s %s' "$1" "$2" | sed 's#[^A-Za-z0-9]#_#g')
  printf '%s' "$3" > "$work/api/$c"
  printf '%s' "${4:-200}" > "$work/api/$c.code"
}
api_file() { # $1 chemin d'un GET ; affiche le fichier de sa réponse
  printf '%s/api/%s' "$work" "$(printf 'GET %s' "$1" | sed 's#[^A-Za-z0-9]#_#g')"
}
# Change une réponse par un filtre jq : « change /repos/…/branch_protections '.[0].enable_push = true' »
change() { # $1 chemin d'un GET, $2 filtre jq
  local f
  f=$(api_file "$1")
  jq "$2" "$f" > "$f.new" && mv "$f.new" "$f"
}

aucune_ecriture() {
  local ligne ecritures=""
  [[ ! -f $work/appels ]] || while IFS= read -r ligne || [[ -n $ligne ]]; do
    [[ $ligne == "GET "* ]] || ecritures+="$ligne"$'\n'
  done < "$work/appels"
  [[ -z $ecritures ]] || { printf 'la forge a reçu une écriture :\n%s\n' "$ecritures" >&2; exit 1; }
}

# Le projet : schéma 7, base dev sans push, publication main poussée par un compte de CI, fusion réservée
# au propriétaire, contexte exigé. $@ = changements du workflow.config.
projet() {
  # un cas peut construire plusieurs projets : chacun repart d'un dépôt et d'une forge vides
  rm -rf "$depot" "$work/api" "$work/appels"
  new_repo
  write_workflow_config "$depot" "forge.repo=$repo" workflow.schema=7 sprint.non-story-files=none \
    ci.statuses=context ci.wait=0 review.agent-paths=none \
    protection.base-push=none protection.base-force-push=none protection.release-push=Compte-robot \
    protection.merge=Proprietaire "protection.status-contexts=checks / checks*" protection.block-outdated=false "$@"
  printf '.env\n' > "$depot/.gitignore"
  printf 'GITEA_URL=https://forge.example.invalid\nGITEA_USER=compte-essai\nGITEA_TOKEN=jeton-essai\n' > "$depot/.env"
  commit_all base > /dev/null
  git -C "$depot" remote add origin "git@forge.example.invalid:$repo.git"
  faux_curl
  api GET /user '{"login":"compte-essai"}'
  forge_conforme
}

# Une règle de la forge, au format de GET /branch_protections (Gitea 1.27.3), conforme à la règle commune.
# $1 branche, $2 comptes de push (JSON, null = aucun), $3 comptes de push forcé (JSON, null = aucun)
regle() {
  local merge contexts outdated
  merge=$(git config -f "$depot/workflow.config" protection.merge)
  contexts=$(git config -f "$depot/workflow.config" protection.status-contexts)
  outdated=$(git config -f "$depot/workflow.config" protection.block-outdated)
  jq -n --arg b "$1" --argjson push "$2" --argjson force "$3" --arg merge "$merge" --arg ctx "$contexts" \
    --argjson outdated "$outdated" '{
    branch_name: $b, rule_name: $b, priority: 1,
    enable_push: ($push != null), enable_push_whitelist: ($push != null),
    push_whitelist_usernames: ($push // []), push_whitelist_teams: [], push_whitelist_deploy_keys: false,
    enable_force_push: ($force != null), enable_force_push_allowlist: ($force != null),
    force_push_allowlist_usernames: ($force // []), force_push_allowlist_teams: [],
    force_push_allowlist_deploy_keys: false,
    enable_merge_whitelist: true, merge_whitelist_usernames: ($merge | split(" ")), merge_whitelist_teams: [],
    enable_bypass_allowlist: false, bypass_allowlist_usernames: [], bypass_allowlist_teams: [],
    enable_status_check: ($ctx != "none"),
    status_check_contexts: (if $ctx == "none" then null else ($ctx | split(",") | map(gsub("^\\s+|\\s+$"; ""))) end),
    required_approvals: 0, enable_approvals_whitelist: false, approvals_whitelist_username: [],
    approvals_whitelist_teams: [], block_on_rejected_reviews: false, block_on_official_review_requests: false,
    block_on_outdated_branch: $outdated, dismiss_stale_approvals: false, ignore_stale_approvals: false,
    require_signed_commits: false, protected_file_patterns: "", unprotected_file_patterns: "",
    block_admin_merge_override: false,
    created_at: "2026-10-08T10:00:00+02:00", updated_at: "2026-10-08T10:00:00+02:00"}'
}

accounts_json() { # $1 valeur d'un champ de comptes ; affiche sa liste JSON, ou null pour none
  if [[ $1 == none ]]; then echo null; else jq -cn --arg v "$1" '$v | split(" ")'; fi
}

forge_conforme() {
  local cfg=$depot/workflow.config base release rules
  base=$(git config -f "$cfg" forge.base)
  release=$(git config -f "$cfg" forge.release-branch)
  rules=$(regle "$base" "$(accounts_json "$(git config -f "$cfg" protection.base-push)")" \
    "$(accounts_json "$(git config -f "$cfg" protection.base-force-push)")")
  if [[ $release != none ]]; then
    rules+=$'\n'$(regle "$release" "$(accounts_json "$(git config -f "$cfg" protection.release-push)")" null)
  fi
  api GET "/repos/$repo/branch_protections" "$(jq -s . <<< "$rules")"
  # styles de la règle commune : squash, et avance rapide uniquement s'il y a une branche de publication
  api GET "/repos/$repo" "$(jq -n --arg r "$release" '{full_name: "Proprietaire/projet-essai",
    allow_merge_commits: false, allow_rebase: false, allow_rebase_explicit: false,
    allow_squash_merge: true, allow_fast_forward_only_merge: ($r != "none"),
    allow_manual_merge: false, default_merge_style: "squash", default_branch: "dev"}')"
  api GET "/repos/$repo/keys?limit=50&page=1" '[{"id":3,"title":"lecture","read_only":true}]'
  api GET "/repos/$repo/keys?limit=50&page=2" '[]'
}

controle() { run bash -c 'cd "$1" && PATH="$2:$PATH" bash "$3/gitea/check-branch-protection.sh"' _ "$depot" "$work/bin" "$common"; }

# Un écart attendu : code 1, l'écart nommé (champ, valeur lue, valeur attendue), aucune écriture.
ecart() { # $1 texte attendu dans la liste des écarts, $2 libellé
  controle
  assert_eq 1 "$rc" "$2 : écart constaté, code 1 (sortie : $out ; erreurs : $err)"
  assert_contains "$1" "$out" "$2 : l'écart est nommé"
  assert_contains "Réglages à poser dans l'interface" "$out" "$2 : la liste des réglages suit les écarts"
  aucune_ecriture
}

# --- conforme --------------------------------------------------------------------------------------

case_conforme_rend_0_et_dit_ses_limites() {
  projet
  controle
  assert_eq 0 "$rc" "une forge conforme rend 0 (sortie : $out ; erreurs : $err)"
  assert_contains "conforme" "$out" "le verdict est écrit"
  assert_contains "règle « dev »" "$out" "la branche de travail est nommée"
  assert_contains "règle « main »" "$out" "la branche de publication est nommée"
  assert_contains "étiquettes" "$out" "la limite est dite : les protections d'étiquettes ne sont pas couvertes"
  assert_contains "1 clé de déploiement en lecture seule" "$out" "une clé en lecture seule est relevée, pas signalée"
  [[ $out != *"Réglages à poser"* ]] || { echo "une liste de réglages sur une forge conforme" >&2; exit 1; }
  aucune_ecriture
}

case_conforme_avec_listes_de_push() {
  projet "protection.base-push=Proprietaire Compte-robot" protection.base-force-push=Proprietaire \
    protection.block-outdated=true
  # la forge rend les comptes dans un autre ordre et une autre casse : ni l'un ni l'autre ne compte
  change "/repos/$repo/branch_protections" '.[0].push_whitelist_usernames = ["compte-robot", "Proprietaire"]'
  controle
  assert_eq 0 "$rc" "listes de push conformes (sortie : $out ; erreurs : $err)"
}

case_sans_branche_de_publication() {
  projet forge.release-branch=none protection.release-push=none
  controle
  assert_eq 0 "$rc" "un dépôt sans branche de publication n'a qu'une règle (sortie : $out ; erreurs : $err)"
  assert_contains "sans branche de publication" "$out" "la sortie le dit"
}

case_aucun_contexte_exige() {
  projet protection.status-contexts=none
  controle
  assert_eq 0 "$rc" "aucun contexte exigé, aucun contrôle qualité (sortie : $out ; erreurs : $err)"
  change "/repos/$repo/branch_protections" '.[1].enable_status_check = true | .[1].status_check_contexts = ["checks*"]'
  ecart "règle « main » : enable_status_check : lu true, attendu false" "un contexte exigé que le projet ne déclare pas"
}

# --- un écart par famille ----------------------------------------------------------------------------

case_ecart_push() {
  projet
  change "/repos/$repo/branch_protections" '.[0].enable_push = true'
  ecart "règle « dev » : enable_push : lu true, attendu false" "push ouvert à tout compte en écriture"
  assert_contains "Soumission : « Désactiver la soumission »  ← à changer (lu : « Activer la soumission »)" "$out" \
    "le réglage à poser est nommé par son libellé, avec la valeur lue"
  assert_contains "Paramètres → Branches → Protection de branche → règle « dev » → « Éditer »" "$out" "l'écran est nommé"
  assert_contains "« Enregistrer la règle »" "$out" "le bouton de l'écran est nommé"
}

case_ecart_liste_de_push() {
  projet
  change "/repos/$repo/branch_protections" '.[1].push_whitelist_usernames = ["Proprietaire"]'
  ecart "règle « main » : push_whitelist_usernames : lu Proprietaire, attendu Compte-robot" "liste de push de la publication"
  assert_contains "Utilisateurs autorisés à pousser : Compte-robot  ← à changer (lu : Proprietaire)" "$out" "la liste à poser"
}

case_ecart_push_force() {
  projet
  change "/repos/$repo/branch_protections" '.[1].enable_force_push = true'
  ecart "règle « main » : enable_force_push : lu true, attendu false" "push forcé sur la publication"
  assert_contains "Poussée forcée : « Désactiver les poussés forcées »  ← à changer" "$out" "le libellé de la forge, tel quel"
}

case_ecart_fusion() {
  projet
  change "/repos/$repo/branch_protections" '.[0].enable_merge_whitelist = false | .[0].merge_whitelist_usernames = []'
  ecart "règle « dev » : enable_merge_whitelist : lu false, attendu true" "fusion ouverte à tout compte en écriture"
  assert_contains "Fusion de demande d'ajout : « Fusion sur autorisation uniquement »  ← à changer (lu : « Activer la fusion »)" \
    "$out" "le réglage de fusion à poser"
  assert_contains "Utilisateurs autorisés à fusionner : Proprietaire  ← à changer (lu : (vide))" "$out" "la liste de fusion à poser"
}

case_ecart_contextes() {
  projet
  change "/repos/$repo/branch_protections" '.[0].status_check_contexts = ["checks / checks (push)"]'
  ecart "règle « dev » : status_check_contexts : lu checks / checks (push), attendu checks / checks*" "motif de contexte"
  assert_contains "Motifs de vérification des statuts (un par ligne) : checks / checks*" "$out" "le motif à poser"
}

case_ecart_branche_a_jour_et_contournement() {
  projet
  change "/repos/$repo/branch_protections" '.[0].block_on_outdated_branch = true | .[0].block_admin_merge_override = true | .[0].enable_bypass_allowlist = true'
  ecart "règle « dev » : block_on_outdated_branch : lu true, attendu false" "branche à jour exigée"
  assert_contains "règle « dev » : block_admin_merge_override : lu true, attendu false" "$out" "l'administrateur garde la fusion d'urgence"
  assert_contains "règle « dev » : enable_bypass_allowlist : lu true, attendu false" "$out" "aucune liste de contournement"
}

case_ecart_styles_de_fusion() {
  projet
  change "/repos/$repo" '.allow_fast_forward_only_merge = false | .allow_merge_commits = true | .allow_rebase = true | .default_merge_style = "merge"'
  ecart "dépôt : allow_fast_forward_only_merge : lu false, attendu true" "l'avance rapide de la publication fermée"
  assert_contains "dépôt : allow_merge_commits : lu true, attendu false" "$out" "le commit de fusion est fermé par la règle commune"
  assert_contains "dépôt : allow_rebase : lu true, attendu false" "$out" "un style qu'aucun chemin n'emploie"
  assert_contains "dépôt : default_merge_style : lu merge, attendu squash" "$out" "le style par défaut"
  assert_contains "Paramètres → Dépôt → Paramètres avancés → Demandes d'ajout" "$out" "l'écran des styles est nommé"
  assert_contains "Styles de fusion — Avance rapide uniquement : cochée  ← à changer (lu : décochée)" "$out" "le style à ouvrir"
  assert_contains "Styles de fusion — Créer une révision de fusion : décochée  ← à changer (lu : cochée)" "$out" "le style à fermer"
  assert_contains "Méthode de fusion par défaut : « Créer une révision de concaténation »  ← à changer" "$out" "le défaut à poser"
  assert_contains "« Appliquer »" "$out" "le bouton de l'écran"
  # chaque autre style, ouvert seul, est un écart
  local champ
  for champ in allow_merge_commits allow_rebase_explicit allow_manual_merge; do
    projet
    change "/repos/$repo" ".$champ = true"
    ecart "dépôt : $champ : lu true, attendu false" "$champ ouvert"
  done
  # sans branche de publication, l'avance rapide n'a aucun chemin : ouverte, elle est un écart
  projet forge.release-branch=none protection.release-push=none
  change "/repos/$repo" '.allow_fast_forward_only_merge = true'
  ecart "dépôt : allow_fast_forward_only_merge : lu true, attendu false" "avance rapide sans branche de publication"
}

case_ecart_cle_de_deploiement() {
  projet
  api GET "/repos/$repo/keys?limit=50&page=1" '[{"id":3,"title":"lecture","read_only":true},{"id":9,"title":"adresse@example.invalid","read_only":false}]'
  ecart "clé de déploiement n° 9 : read_only : lu false, attendu true" "une clé qui peut pousser"
  [[ $out != *adresse@example.invalid* ]] || { echo "le titre d'une clé est affiché" >&2; exit 1; }
  assert_contains "Paramètres → Clés de déploiement → clé n° 9" "$out" "l'écran de la clé est nommé"
  projet
  change "/repos/$repo/branch_protections" '.[1].push_whitelist_deploy_keys = true'
  ecart "règle « main » : push_whitelist_deploy_keys : lu true, attendu false" "une clé admise à pousser par la règle"
}

case_ecart_regle_absente() {
  projet
  change "/repos/$repo/branch_protections" '[.[0]]'
  ecart "règle « main » : absente" "la branche de publication sans règle"
  assert_contains "Paramètres → Branches → Protection de branche → « Ajouter une nouvelle règle »" "$out" "l'écran de création"
  assert_contains "Motif de nom de branche protégé : main" "$out" "le nom exact de la règle"
  assert_contains "Soumission : « Soumissions sur autorisation uniquement »" "$out" "chaque réglage de la nouvelle règle"
  assert_contains "Utilisateurs autorisés à pousser : Compte-robot" "$out" "la liste de push de la nouvelle règle"
}

case_ecart_regle_en_trop() {
  projet
  change "/repos/$repo/branch_protections" '. + [(.[0] | .rule_name = "release/*" | .branch_name = "release/*")]'
  ecart "règle « release/* » : en trop (ni forge.base ni forge.release-branch)" "une règle sur une autre branche"
  assert_contains "règle « release/* » → « Supprimer la règle »" "$out" "le geste à faire"
  # une règle à joker qui couvre la branche de travail n'en tient pas lieu
  projet
  change "/repos/$repo/branch_protections" '[.[1], (.[0] | .rule_name = "de*" | .branch_name = "de*")]'
  ecart "règle « dev » : absente" "un joker ne remplace pas la règle au nom exact"
  assert_contains "règle « de* » : en trop" "$out" "le joker est signalé en trop"
}

# --- jamais 0 sur une lecture qui a échoué -------------------------------------------------------------

case_anomalie_jeton_absent() {
  projet
  printf 'GITEA_URL=https://forge.example.invalid\nGITEA_USER=compte-essai\n' > "$depot/.env"
  controle
  assert_eq 2 "$rc" "sans jeton, rien n'est vérifié : code 2"
  assert_contains "GITEA_TOKEN absente" "$err" "la cause est nommée"
  [[ ! -f $work/appels ]] || { echo "la forge a été appelée sans jeton" >&2; exit 1; }
}

case_anomalie_401() {
  projet
  api GET /user '{"message":"token is required"}' 401
  controle
  assert_eq 2 "$rc" "jeton refusé : code 2"
  assert_contains "HTTP 401" "$err" "le code de la forge est nommé"
  aucune_ecriture
}

case_anomalie_403() {
  projet
  api GET "/repos/$repo/branch_protections" '{"message":"forbidden"}' 403
  controle
  assert_eq 2 "$rc" "lecture des règles refusée : code 2, jamais 0"
  assert_contains "HTTP 403" "$err" "le code de la forge est nommé"
  assert_contains "administration" "$err" "la cause probable est dite"
  aucune_ecriture
}

case_anomalie_reponse_illisible() {
  local chemin
  for chemin in "/repos/$repo/branch_protections" "/repos/$repo" "/repos/$repo/keys?limit=50&page=1"; do
    projet
    api GET "$chemin" '<html>proxy</html>'
    controle
    assert_eq 2 "$rc" "réponse illisible ($chemin) : code 2"
    assert_contains "illisible" "$err" "la sortie le dit ($chemin)"
  done
  # une règle sans l'un des champs relus (une autre version de la forge) : illisible, pas conforme
  projet
  change "/repos/$repo/branch_protections" '.[0] |= del(.enable_force_push)'
  controle
  assert_eq 2 "$rc" "un champ attendu manque à la règle : code 2"
  assert_contains "enable_force_push" "$err" "le champ manquant est nommé"
  projet
  change "/repos/$repo" 'del(.allow_manual_merge)'
  controle
  assert_eq 2 "$rc" "un champ attendu manque au dépôt : code 2"
}

case_anomalie_schema_6() {
  projet
  write_workflow_config "$depot" "forge.repo=$repo" workflow.schema=6 sprint.non-story-files=none \
    ci.statuses=context ci.wait=0 review.agent-paths=none
  controle
  assert_eq 2 "$rc" "un workflow.config sans section [protection] : code 2"
  assert_contains "schéma 7" "$err" "le schéma attendu est nommé"
  [[ ! -f $work/appels ]] || { echo "la forge a été appelée sans valeurs attendues" >&2; exit 1; }
}

case_anomalie_trop_de_pages_de_cles() {
  projet
  local page
  for page in $(seq 1 21); do
    api GET "/repos/$repo/keys?limit=50&page=$page" '[{"id":1,"title":"x","read_only":true}]'
  done
  controle
  assert_eq 2 "$rc" "la liste des clés ne finit pas : code 2, jamais une liste tronquée"
}

case_anomalie_usage_et_hors_du_depot() {
  projet
  run bash -c 'cd "$1" && PATH="$2:$PATH" bash "$3/gitea/check-branch-protection.sh" --apply' _ "$depot" "$work/bin" "$common"
  assert_eq 2 "$rc" "un argument : usage, code 2 (rien n'est écrit, il n'existe pas de mode d'écriture)"
  assert_contains "usage" "$err" "l'usage est rappelé"
  mkdir -p "$work/hors"
  run bash -c 'cd "$1" && PATH="$2:$PATH" GIT_CEILING_DIRECTORIES="$1/.." bash "$3/gitea/check-branch-protection.sh"' _ "$work/hors" "$work/bin" "$common"
  assert_eq 2 "$rc" "hors d'un dépôt git : code 2"
  assert_contains "à lancer dans le dépôt" "$err" "la cause est nommée"
  [[ ! -f $work/appels ]] || { echo "la forge a été appelée" >&2; exit 1; }
}

case_anomalie_autres_codes_http() {
  local code
  for code in 404 500; do
    projet
    api GET "/repos/$repo" '{"message":"erreur"}' "$code"
    controle
    assert_eq 2 "$rc" "HTTP $code sur le dépôt : code 2"
    assert_contains "HTTP $code" "$err" "le code est nommé ($code)"
  done
  projet
  api GET "/repos/$repo/keys?limit=50&page=1" '{"message":"erreur"}' 500
  controle
  assert_eq 2 "$rc" "HTTP 500 sur les clés : code 2"
  assert_contains "lecture impossible : clés de déploiement (page 1) (HTTP 500)" "$err" "la lecture en cause est nommée"
}

# Un faux jq, qui délègue au vrai sauf pour l'appel que le cas veut faire échouer : $1 motif cherché dans
# les arguments, $2 ce que fait l'appel visé (« echec » : code 5 ; « verdict » : sortie sans verdict).
faux_jq() {
  local vrai
  vrai=$(command -v jq)
  {
    printf '#!/usr/bin/env bash
vrai=%q motif=%q mode=%q
' "$vrai" "$1" "$2"
    cat <<'FAUX'
if [[ " $* " == *"$motif"* ]]; then
  [[ $mode == echec ]] && exit 5
  printf 'ni conforme ni écart\nune ligne\n'
  exit 0
fi
exec "$vrai" "$@"
FAUX
  } > "$work/bin/jq"
  chmod +x "$work/bin/jq"
}

case_anomalie_assemblage_des_cles() {
  projet
  faux_jq '.[0] + .[1]' echec
  controle
  assert_eq 2 "$rc" "les pages de clés ne s'assemblent pas : code 2"
  assert_contains "assemblage des pages impossible" "$err" "la cause est nommée"
}

case_anomalie_valeurs_attendues_illisibles() {
  projet
  faux_jq 'def accounts' echec
  controle
  assert_eq 2 "$rc" "les valeurs attendues ne s'écrivent pas : code 2"
  assert_contains "valeurs attendues illisibles dans workflow.config" "$err" "la cause est nommée"
  [[ ! -f $work/appels ]] || { echo "la forge a été appelée sans valeurs attendues" >&2; exit 1; }
}

case_anomalie_comparaison_impossible() {
  projet
  faux_jq protection.jq echec
  controle
  assert_eq 2 "$rc" "le programme de comparaison échoue : code 2, jamais 0"
  assert_contains "comparaison impossible (jq, code 5)" "$out" "la cause est nommée"
  projet
  faux_jq protection.jq verdict
  controle
  assert_eq 2 "$rc" "une sortie sans verdict : code 2, jamais 0"
  assert_contains "verdict illisible" "$out" "la cause est nommée"
}

case_formes_de_reponse_refusees() {
  # La forme de chaque réponse, jugée par la bibliothèque sur des fichiers : une liste de clés assemblée
  # par le script est toujours une liste, mais protection_check_shapes ne le suppose pas.
  # shellcheck source=../lib/config.sh
  . "$common/lib/config.sh"
  # shellcheck source=../lib/protection.sh
  . "$common/lib/protection.sh"
  projet
  local exp=$work/attendu.json depot_json regles cles
  (cd "$depot" && config_load workflow.config && protection_expected "$exp")
  depot_json=$(api_file "/repos/$repo")
  regles=$(api_file "/repos/$repo/branch_protections")
  cles=$(api_file "/repos/$repo/keys?limit=50&page=1")
  run protection_check_shapes "$exp" "$depot_json" "$regles" "$cles"
  assert_eq 0 "$rc" "les réponses conformes ont la forme relue (sortie : $out)"
  printf '[]' > "$work/liste.json"
  printf '{}' > "$work/objet.json"
  run protection_check_shapes "$exp" "$work/liste.json" "$regles" "$cles"
  assert_eq 2 "$rc" "un dépôt qui n'est pas un objet"
  assert_contains "dépôt (GET /repos/<dépôt>) : un objet JSON attendu" "$out" "la réponse est nommée"
  run protection_check_shapes "$exp" "$depot_json" "$work/objet.json" "$cles"
  assert_eq 2 "$rc" "des règles qui ne sont pas une liste"
  assert_contains "règles (GET /branch_protections) : une liste JSON attendue" "$out" "la réponse est nommée"
  run protection_check_shapes "$exp" "$depot_json" "$regles" "$work/objet.json"
  assert_eq 2 "$rc" "des clés qui ne sont pas une liste"
  assert_contains "clés de déploiement (GET /keys) : une liste JSON attendue" "$out" "la réponse est nommée"
  printf '[{"priority":1}]' > "$work/sans-nom.json"
  run protection_check_shapes "$exp" "$depot_json" "$work/sans-nom.json" "$cles"
  assert_eq 2 "$rc" "une règle sans rule_name"
  assert_contains "une entrée sans rule_name" "$out" "le défaut est nommé"
  printf '[{"id":3,"title":"x"}]' > "$work/cle.json"
  run protection_check_shapes "$exp" "$depot_json" "$regles" "$work/cle.json"
  assert_eq 2 "$rc" "une clé sans read_only : illisible, jamais une clé qui ne peut pas pousser"
  assert_contains "une entrée sans id ni read_only" "$out" "le défaut est nommé"
  printf '[{"id":"3","read_only":true}]' > "$work/cle.json"
  run protection_check_shapes "$exp" "$depot_json" "$regles" "$work/cle.json"
  assert_eq 2 "$rc" "une clé dont l'id n'est pas un nombre"
  # de bout en bout : une page de clés dont une entrée est incomplète
  projet
  api GET "/repos/$repo/keys?limit=50&page=1" '[{"id":3,"title":"x"}]'
  controle
  assert_eq 2 "$rc" "une clé incomplète : code 2"
  assert_contains "une entrée sans id ni read_only" "$err" "le défaut est nommé"
}

case_valeurs_attendues_sans_configuration() {
  # protection_expected lit workflow.config déjà chargé : sans lui, ou d'avant le schéma 7, il rend 2
  # et le script s'arrête avant tout appel à la forge
  # shellcheck source=../lib/config.sh
  . "$common/lib/config.sh"
  # shellcheck source=../lib/protection.sh
  . "$common/lib/protection.sh"
  run protection_expected "$work/attendu.json"
  assert_eq 2 "$rc" "aucun workflow.config chargé : code 2"
  write_workflow_config "$work/projet" workflow.schema=6 sprint.non-story-files=none ci.statuses=context ci.wait=0 \
    review.agent-paths=none
  config_load "$work/projet/workflow.config"
  run protection_expected "$work/attendu.json"
  assert_eq 2 "$rc" "un workflow.config au schéma 6 : code 2"
  assert_contains "protection.base-push" "$err" "le champ manquant est nommé"
}

# --- le dépôt commun lui-même : sa protection est le modèle -----------------------------------------------

case_depot_commun_conforme_sur_son_releve() {
  # Relevé du 08/10/2026 par l'API (règle de main, réglages du dépôt), jugé avec le workflow.config du
  # dépôt commun : le modèle de la règle commune doit y être conforme.
  new_repo
  cp "$common/workflow.config" "$depot/workflow.config"
  local r
  r=$(git config -f "$depot/workflow.config" forge.repo)
  printf '.env\n' > "$depot/.gitignore"
  printf 'GITEA_URL=https://forge.example.invalid\nGITEA_USER=compte-essai\nGITEA_TOKEN=jeton-essai\n' > "$depot/.env"
  commit_all base > /dev/null
  git -C "$depot" remote add origin "git@forge.example.invalid:$r.git"
  faux_curl
  api GET /user '{"login":"compte-essai"}'
  api GET "/repos/$r/branch_protections" "$(cat "$fixtures/protection/depot-commun-branch-protections.json")"
  api GET "/repos/$r" "$(cat "$fixtures/protection/depot-commun-repo.json")"
  api GET "/repos/$r/keys?limit=50&page=1" '[]'
  controle
  assert_eq 0 "$rc" "le dépôt commun est conforme à sa propre règle (sortie : $out ; erreurs : $err)"
  assert_contains "sans branche de publication" "$out" "il n'a qu'une branche durable"
}

run_case "$@"
