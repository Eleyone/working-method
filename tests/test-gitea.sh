#!/usr/bin/env bash
# Adaptateur de la forge (gitea/gitea.sh) : ce que le paramétrage par workflow.config y a fait entrer —
# le dépôt canonique lu dans forge.repo, et la base d'une PR déduite de forge.base, de
# forge.release-branch et de forge.branch-prefixes —, et la convention à trois codes : die sort en 2
# (je n'ai pas pu), refuse en 1 (écart constaté), et un 2 rendu une fois la PR connue est publié en
# alerte sur la PR (alert_pr). Aucun appel réseau : un faux curl répond.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Chaque appel tourne dans son propre bash : die quitte, ce qui terminerait le cas. Un argument de plus
# se lit « $4 » dans le corps.
adaptateur() { # $1 = dossier de travail, $2 = corps à exécuter après le chargement
  run bash -c 'set -euo pipefail; script_name=essai; cd "$1"; . "$2/lib/config.sh"; . "$2/gitea/gitea.sh"; eval "$3"' \
    _ "$1" "$common" "$2" "${@:3}"
}

case_depot_canonique_lu_dans_workflow_config() {
  new_repo
  write_workflow_config "$work/depot"
  git -C "$work/depot" remote add origin "git@forge.example.invalid:Proprietaire/projet-essai.git"
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  adaptateur "$work/depot" 'config_load workflow.config; gitea_configure; check_origin; echo "ok $gitea_canonical_repo"'
  assert_eq 0 "$rc" "origin est le dépôt déclaré (messages : $err)"
  assert_eq "ok Proprietaire/projet-essai" "$out" "le dépôt canonique vient de forge.repo"
  git -C "$work/depot" remote set-url origin "https://forge.example.invalid/Proprietaire/autre.git"
  adaptateur "$work/depot" 'config_load workflow.config; gitea_configure; check_origin; echo atteint'
  assert_eq 2 "$rc" "un autre dépôt distant : rien n'est vérifiable, code 2"
  assert_contains "n'est pas Proprietaire/projet-essai" "$err" "le message nomme le dépôt attendu"
  [[ $err != *forge.example.invalid* ]] || { echo "le message affiche l'adresse de la forge" >&2; exit 1; }
}

case_check_origin_sans_configuration() {
  # Plus aucun nom de dépôt n'est écrit dans l'adaptateur : sans workflow.config lu, il refuse.
  new_repo
  git -C "$work/depot" remote add origin "git@forge.example.invalid:Proprietaire/projet-essai.git"
  adaptateur "$work/depot" 'check_origin; echo atteint'
  assert_eq 2 "$rc" "check_origin refuse sans dépôt canonique, en 2"
  assert_contains "gitea_configure n'a pas été appelé" "$err" "le message dit pourquoi"
  adaptateur "$work/depot" 'gitea_configure; echo atteint'
  assert_eq 2 "$rc" "gitea_configure refuse sans workflow.config chargé, en 2"
}

case_base_d_une_pr() {
  . "$common/gitea/gitea.sh"
  run branch_base feat/12-3-essai dev main "feat fix chore docs"
  assert_eq 0 "$rc" "préfixe admis"
  assert_eq dev "$out" "la base est forge.base"
  run branch_base refactor/x dev master "feat fix chore refactor perf test docs"
  assert_eq dev "$out" "les préfixes viennent de forge.branch-prefixes"
  run branch_base refactor/x dev main "feat fix chore docs"
  assert_eq 1 "$rc" "un préfixe non déclaré est refusé"
  assert_contains "Préfixes admis : feat/, fix/, chore/, docs/" "$out" "le refus liste les préfixes admis"
  run branch_base hotfix/x dev main "feat fix chore docs"
  assert_eq 1 "$rc" "hotfix/ n'est pas un préfixe déclaré"
  run branch_base feat/ dev main "feat"
  assert_eq 1 "$rc" "un préfixe sans nom de branche est refusé"
  run branch_base dev dev main "feat"
  assert_eq 1 "$rc" "aucune PR depuis la base"
  run branch_base main dev main "feat"
  assert_eq 1 "$rc" "aucune PR depuis la branche de publication"
  run branch_base release/v2 dev release/v2 "feat release"
  assert_eq 1 "$rc" "aucune PR depuis la branche de publication, même quand son nom porte un préfixe admis"
  assert_contains "branche de publication" "$out" "le refus le dit"
  run branch_base featx/y dev main "feat"
  assert_eq 1 "$rc" "un préfixe se lit jusqu'à « / », pas comme un début de mot"
  run branch_base feat/x main none "feat"
  assert_eq main "$out" "sans branche de publication, la base unique"
}

case_env_file_nomme_dans_le_message() {
  new_repo
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  adaptateur "$work/depot" 'load_gitea_env "$PWD/secrets.env"'
  assert_eq 2 "$rc" "un fichier d'environnement absent : code 2"
  assert_contains "secrets.env absent (forge.env-file)" "$err" "le message nomme le fichier déclaré"
}

# --- prérequis communs : tous en 2, le script ne peut rien vérifier sans eux ---------------------

case_prerequis_outils_absents_rendent_2() {
  new_repo
  mkdir -p "$work/sans-jq" "$work/sans-curl"
  ln -s "$(real_command curl)" "$work/sans-jq/curl"
  ln -s "$(real_command jq)" "$work/sans-curl/jq"
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  adaptateur "$work/depot" 'PATH=$4/sans-jq; require_tools; echo atteint' "$work"
  assert_eq 2 "$rc" "jq introuvable : code 2"
  assert_contains "jq est introuvable" "$err" "le message nomme l'outil"
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  adaptateur "$work/depot" 'PATH=$4/sans-curl; require_tools; echo atteint' "$work"
  assert_eq 2 "$rc" "curl introuvable : code 2"
  assert_contains "curl est introuvable" "$err" "le message nomme l'outil"
}

case_prerequis_env_illisible_rend_2() {
  skip_if_root "le fichier d'environnement"
  new_repo
  printf 'GITEA_URL=https://forge.example.invalid\n' > "$work/depot/.env"
  chmod 000 "$work/depot/.env"
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  adaptateur "$work/depot" 'load_gitea_env "$PWD/.env"; echo atteint'
  chmod 600 "$work/depot/.env"
  assert_eq 2 "$rc" "un .env illisible : code 2"
  assert_contains ".env illisible" "$err" "le message le dit"
}

case_prerequis_variables_absentes_rendent_2() {
  new_repo
  local variable
  for variable in GITEA_URL GITEA_USER GITEA_TOKEN; do
    printf 'GITEA_URL=https://forge.example.invalid\nGITEA_USER=compte\nGITEA_TOKEN=jeton\n' \
      | grep -v "^$variable=" > "$work/depot/.env"
    # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
    adaptateur "$work/depot" 'load_gitea_env "$PWD/.env"; echo atteint'
    assert_eq 2 "$rc" "$variable absente : code 2"
    assert_contains "$variable absente de .env" "$err" "le message nomme la variable"
  done
}

case_refuse_rend_1() {
  new_repo
  adaptateur "$work/depot" 'refuse "écart constaté"; echo atteint'
  assert_eq 1 "$rc" "refuse : écart constaté, code 1"
  assert_eq "essai: écart constaté" "$err" "le message commence par le nom du script"
}

# --- alerte hors du terminal : un 2 rendu une fois la PR connue est publié sur la PR -------------

# Un faux curl : note la requête, garde le corps envoyé, répond le code de $work/code-reponse (201).
faux_curl() {
  mkdir -p "$work/bin"
  {
    printf '#!/usr/bin/env bash\nw=%q\n' "$work"
    cat <<'FAUX'
cat > /dev/null
out="" methode=GET url="" corps=""
while (($#)); do
  case $1 in
    -o) out=$2; shift 2 ;;
    -X) methode=$2; shift 2 ;;
    --data) corps=${2#@}; shift 2 ;;
    -K|-H|-w) shift 2 ;;
    *) url=$1; shift ;;
  esac
done
printf '%s %s\n' "$methode" "${url#*/api/v1}" >> "$w/appels"
[[ -z $corps ]] || cp "$corps" "$w/corps.json"
printf '{}' > "$out"
cat "$w/code-reponse" 2>/dev/null || printf 201
FAUX
  } > "$work/bin/curl"
  chmod +x "$work/bin/curl"
}

# Le contexte d'un script qui a lu son .env ; $1 = le corps à exécuter ensuite, $2 se lit « $4 ».
alerte() {
  new_repo
  faux_curl
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run env PATH="$work/bin:$PATH" bash -c 'set -euo pipefail; script_name=essai; cd "$1"; . "$2/lib/config.sh"
    . "$2/gitea/gitea.sh"; gitea_canonical_repo=Proprietaire/projet-essai; gitea_url=https://forge.example.invalid
    gitea_user=compte gitea_token=jeton; eval "$3"' _ "$work/depot" "$common" "$@"
}

case_alerte_publiee_sur_la_pr_quand_die_rend_2() {
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  alerte 'gitea_alert_pr=7; die "lecture de $PWD/fichier impossible"; echo atteint'
  assert_eq 2 "$rc" "die rend 2, alerte publiée ou non"
  assert_eq "POST /repos/Proprietaire/projet-essai/issues/7/comments" "$(cat "$work/appels")" "l'alerte est un commentaire de la PR"
  local corps
  corps=$(jq -r .body "$work/corps.json")
  assert_contains "essai : anomalie (code 2)" "$corps" "l'alerte nomme le script et le code"
  assert_contains "lecture de <dépôt>/fichier impossible" "$corps" "le message est repris, chemin du poste masqué"
  [[ $corps != *"$work"* ]] || { echo "l'alerte affiche un chemin du poste" >&2; exit 1; }
  [[ $corps != "llm-review sha="* ]] || { echo "l'alerte se ferait lire comme un rapport de revue" >&2; exit 1; }
  assert_contains "alerte publiée sur la PR n° 7" "$err" "le terminal le dit"
}

case_alerte_masque_l_adresse_de_la_forge() {
  alerte 'gitea_alert_pr=7; die "réponse de https://forge.example.invalid/api/v1/x illisible"; echo atteint'
  assert_eq 2 "$rc" "die rend 2"
  local corps
  corps=$(jq -r .body "$work/corps.json")
  assert_contains "réponse de <adresse>/api/v1/x illisible" "$corps" "l'adresse de la forge est masquée"
  [[ $corps != *forge.example.invalid* ]] || { echo "l'alerte affiche l'adresse de la forge" >&2; exit 1; }
}

case_alerte_refusee_par_la_forge_garde_le_2() {
  printf 500 > "$work/code-reponse"
  alerte 'gitea_alert_pr=7; die "forge muette"; echo atteint'
  assert_eq 2 "$rc" "une alerte refusée ne change pas le code"
  assert_contains "alerte non publiée sur la PR n° 7 (HTTP 500)" "$err" "le terminal reste le seul canal, et le dit"
}

case_alerte_absente_sans_pr_connue() {
  alerte 'die "avant la PR"; echo atteint'
  assert_eq 2 "$rc" "die rend 2"
  [[ ! -e $work/appels ]] || { echo "une alerte est partie sans PR connue" >&2; exit 1; }
}

case_alerte_jamais_sur_un_refus() {
  alerte 'gitea_alert_pr=7; refuse "écart"; echo atteint'
  assert_eq 1 "$rc" "refuse rend 1"
  [[ ! -e $work/appels ]] || { echo "un écart constaté a été publié en alerte" >&2; exit 1; }
}

case_alerte_retenue_si_le_message_contient_un_motif_prive() {
  printf 'MOTIF-FACTICE\n' > "$work/motifs"
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  alerte 'gitea_alert_pr=7; gitea_alert_patterns=$4; die "contenu motif-factice"; echo atteint' "$work/motifs"
  assert_eq 2 "$rc" "die rend 2"
  [[ ! -e $work/appels ]] || { echo "une alerte au motif privé a été publiée" >&2; exit 1; }
  assert_contains "alerte non publiée sur la PR n° 7 : le message contient un motif privé" "$err" "le terminal le dit"
}

run_case "$@"
