#!/usr/bin/env bash
# Contrôles de la CI du dépôt commun : « aucun secret » (ci/check-secrets.sh, AC 11), « aucun nom de
# projet » (ci/check-names.sh, AC 3), preset Renovate (AC 10), fourniture de shellcheck épinglé
# (ci/ensure-shellcheck.sh) et contrat du workflow avec la protection de main. Les secrets et les noms d'essai sont fabriqués à l'exécution, par morceaux : écrits en clair
# ici, ils feraient échouer le contrôle sur ce fichier même.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Dépôt d'essai avec un premier commit propre.
depot_propre() {
  new_repo
  printf 'rien à signaler\n' > "$work/depot/README.md"
  commit_all "premier" > /dev/null
}

secrets() { run bash -c 'cd "$1" && bash "$2/ci/check-secrets.sh" "${@:3}"' _ "$work/depot" "$common" "$@"; }
noms() { # liste d'essai fabriquée à l'exécution, hors de l'arbre du dépôt d'essai
  printf '# noms d essai\n%s\n%s\n' "eley""one[.]fr" "financ""e-follow-up" > "$work/noms.txt"
  run bash -c 'cd "$1" && bash "$2/ci/check-names.sh" --patterns-file "$3"' _ "$work/depot" "$common" "$work/noms.txt"
}

# Un jeton d'essai de forme connue, et une valeur témoin qui ne doit jamais apparaître dans la sortie.
jeton() { printf 'gh%s_%s' p "$(printf 'A%.0s' {1..36})"; }

case_secrets_depot_propre() {
  depot_propre
  secrets
  assert_eq 0 "$rc" "un dépôt sans secret passe (messages : $err$out)"
  assert_contains "aucun secret ni chemin interdit (all)" "$out" "le contrôle le dit"
}

case_secrets_dans_l_arbre_sans_afficher_la_valeur() {
  depot_propre
  printf 'config:\n  cle: %s\n' "$(jeton)" > "$work/depot/config.yaml"
  git -C "$work/depot" add config.yaml
  secrets tree
  assert_eq 1 "$rc" "un jeton dans un fichier suivi est refusé"
  assert_contains "fichier config.yaml, ligne 2 (motif 2)" "$out" "l'endroit et le numéro du motif sont donnés"
  [[ $out$err != *"$(jeton)"* ]] || { echo "le contrôle affiche le secret" >&2; exit 1; }
}

case_secrets_dans_l_historique_meme_supprime() {
  depot_propre
  printf 'GITEA_TOKEN=%s\n' "$(printf 'b%.0s' {1..40})" > "$work/depot/notes.txt"
  commit_all "ajout" > /dev/null
  rm "$work/depot/notes.txt"
  commit_all "retrait" > /dev/null
  secrets tree
  assert_eq 0 "$rc" "l'arbre ne le contient plus (messages : $out)"
  secrets history
  assert_eq 1 "$rc" "l'historique le contient toujours : un commit poussé reste lisible par son SHA"
  assert_contains "fichier notes.txt, ligne 1 (motif 10)" "$out" "l'endroit dans l'historique est donné"
  [[ $out != *bbbbbbbbbbbbbbbb* ]] || { echo "le contrôle affiche le secret" >&2; exit 1; }
}

case_secrets_cle_privee_et_message_de_commit() {
  depot_propre
  printf -- '-----BEGIN %s KEY-----\nabc\n' "OPENSSH PRIVATE" > "$work/depot/cle.txt"
  git -C "$work/depot" add cle.txt
  git -C "$work/depot" commit -q -m "clé ajoutée par erreur

https://compte:$(printf 'x%.0s' {1..12})@forge.example.invalid/depot.git"
  secrets history
  assert_eq 1 "$rc" "une clé privée et un identifiant dans un message sont refusés"
  assert_contains "fichier cle.txt, ligne 1 (motif 1)" "$out" "la clé privée est trouvée"
  assert_contains "secret possible dans un message" "$out" "le message de commit est relu"
}

case_secrets_chemins_interdits() {
  depot_propre
  printf 'X=1\n' > "$work/depot/.env"
  printf 'X=\n' > "$work/depot/.env.example"
  mkdir -p "$work/depot/certs"
  printf 'rien\n' > "$work/depot/certs/serveur.pem"
  git -C "$work/depot" add -f .env .env.example certs/serveur.pem
  commit_all "chemins" > /dev/null
  secrets
  assert_eq 1 "$rc" "un .env ou une clé versionnés sont refusés"
  assert_contains "chemin interdit dans l'arbre : .env" "$out" ".env est nommé"
  assert_contains "certs/serveur.pem" "$out" "la clé est nommée"
  [[ $out != *"interdit dans l'arbre : .env.example"* ]] || { echo ".env.example est un modèle, pas un secret" >&2; exit 1; }
}

case_secrets_chemin_interdit_supprime_depuis() {
  # Un .env commité puis retiré : l'arbre est propre, l'historique ne l'est pas.
  depot_propre
  printf 'X=1\n' > "$work/depot/.env.local"
  git -C "$work/depot" add -f .env.local
  commit_all "erreur" > /dev/null
  git -C "$work/depot" rm -q .env.local
  commit_all "retrait" > /dev/null
  secrets tree
  assert_eq 0 "$rc" "l'arbre ne le contient plus (messages : $out)"
  secrets history
  assert_eq 1 "$rc" "l'historique, si"
  assert_contains "chemin interdit dans l'historique : commit" "$out" "le commit est nommé"
  assert_contains ".env.local" "$out" "et le chemin"
}

case_secrets_espaces_reserves_admis() {
  # Ce qu'écrivent les procédures : une variable sans valeur, un repère, une référence de secret de CI.
  depot_propre
  # shellcheck disable=SC2016 # faux secrets écrits tels quels dans un fichier d'essai
  printf 'GITEA_TOKEN=<jeton>\nGITEA_TOKEN: ${{ secrets.JETON_ESSAI_DE_LA_FORGE }}\nhttps://<compte>:<jeton>@forge\nGITEA_TOKEN absente de .env\n' \
    > "$work/depot/procedure.md"
  commit_all "procédure" > /dev/null
  secrets
  assert_eq 0 "$rc" "les repères des procédures ne sont pas des secrets (messages : $out)"
}

case_secrets_reference_a_une_variable_d_environnement() {
  # Les exemples de code de la méthode BMAD : un nom de variable, pas une valeur.
  depot_propre
  # shellcheck disable=SC2016 # code d'exemple écrit tel quel dans un fichier d'essai
  printf 'const SERVICE_API_KEY = process.env.SERVICE_API_KEY;\nconst PACT_BROKER_TOKEN = process.env.PACT_BROKER_TOKEN!;\n' \
    > "$work/depot/exemple.md"
  commit_all "exemple" > /dev/null
  secrets
  assert_eq 0 "$rc" "une référence à une variable d'environnement n'est pas un secret (messages : $out)"
  printf 'const A_TOKEN = process.env.A_TOKEN; const B_TOKEN = "%s";\n' "$(printf 'c%.0s' {1..32})" > "$work/depot/exemple.md"
  commit_all "valeur à côté" > /dev/null
  secrets tree
  assert_eq 1 "$rc" "une vraie valeur sur la même ligne reste signalée"
  secrets history
  assert_eq 1 "$rc" "dans l'historique aussi"
}

case_secrets_le_depot_commun_est_propre() {
  run bash -c 'cd "$1" && bash ci/check-secrets.sh tree' _ "$common"
  assert_eq 0 "$rc" "l'arbre du dépôt commun, motifs du contrôle compris, ne contient aucun secret (messages : $out)"
}

case_secrets_usage() {
  depot_propre
  secrets autre
  assert_eq 2 "$rc" "un mode inconnu est une anomalie"
}

case_noms_trouves_dans_le_contenu_et_les_chemins() {
  depot_propre
  local nom
  nom="eley""one.fr"
  printf 'voir le dépôt %s\n' "${nom^^}" > "$work/depot/doc.md"
  mkdir -p "$work/depot/finance-follow""-up"
  printf 'x\n' > "$work/depot/finance-follow""-up/a.txt"
  commit_all "noms" > /dev/null
  noms
  assert_eq 1 "$rc" "un nom de projet, quelle que soit sa casse, est refusé"
  assert_contains "nom de projet dans doc.md, ligne 1" "$out" "le fichier et la ligne sont donnés"
  assert_contains "nom de projet dans le chemin" "$out" "un chemin qui porte un nom est refusé"
}

case_noms_depot_propre() {
  depot_propre
  noms
  assert_eq 0 "$rc" "aucun nom (messages : $err$out)"
}

case_noms_le_depot_commun_est_propre() {
  # AC 3 : aucun nom de projet dans l'arbre du dépôt commun. La liste vit hors de l'arbre (variable
  # d'Actions CHECK_NAMES_PATTERNS) : sans elle, le cas le dit, et la CI la fournit toujours.
  [[ -n ${CHECK_NAMES_PATTERNS:-} ]] || skip_case "CHECK_NAMES_PATTERNS absente : la liste des noms vit hors de l'arbre"
  run bash -c 'cd "$1" && bash ci/check-names.sh' _ "$common"
  assert_eq 0 "$rc" "l'arbre du dépôt commun ne nomme aucun projet (messages : $out$err)"
}

case_noms_sans_liste_ne_controle_rien() {
  depot_propre
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run env -u CHECK_NAMES_PATTERNS bash -c 'cd "$1" && bash "$2/ci/check-names.sh"' _ "$work/depot" "$common"
  assert_eq 2 "$rc" "sans liste, le contrôle sort en 2, jamais vert"
  assert_contains "liste des noms absente" "$err" "et le dit"
  printf '# rien\n\n' > "$work/vide.txt"
  run bash -c 'cd "$1" && bash "$2/ci/check-names.sh" --patterns-file "$3"' _ "$work/depot" "$common" "$work/vide.txt"
  assert_eq 2 "$rc" "une liste vide ne contrôle rien"
  printf '(\n' > "$work/invalide.txt"
  run bash -c 'cd "$1" && bash "$2/ci/check-names.sh" --patterns-file "$3"' _ "$work/depot" "$common" "$work/invalide.txt"
  assert_eq 2 "$rc" "une expression invalide n'est jamais « aucune correspondance »"
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run env CHECK_NAMES_PATTERNS="$(printf 'eley''one[.]fr')" bash -c 'cd "$1" && bash "$2/ci/check-names.sh"' _ "$work/depot" "$common"
  assert_eq 0 "$rc" "la liste passée par la variable est lue (messages : $err)"
}

case_fichiers_moins_diff_lus_quand_meme() {
  # .gitattributes marque les skills BMAD « -diff » (diff compact pour la revue) : git les tient alors
  # pour binaires, et « git grep -I » comme « git log -p » les sauteraient en silence.
  depot_propre
  mkdir -p "$work/depot/vendu"
  printf 'vendu/** -diff\n' > "$work/depot/.gitattributes"
  printf 'cle: %s\n' "$(jeton)" > "$work/depot/vendu/a.md"
  local nom
  nom="eley""one.fr"
  printf 'voir %s\n' "$nom" > "$work/depot/vendu/b.md"
  commit_all "vendu" > /dev/null
  secrets tree
  assert_eq 1 "$rc" "un secret dans un fichier « -diff » de l'arbre est trouvé"
  assert_contains "fichier vendu/a.md, ligne 1" "$out" "et situé"
  rm "$work/depot/vendu/a.md"
  commit_all "retrait" > /dev/null
  secrets history
  assert_eq 1 "$rc" "un secret dans un fichier « -diff » de l'historique est trouvé"
  assert_contains "fichier vendu/a.md, ligne 1" "$out" "et situé dans l'historique"
  noms
  assert_eq 1 "$rc" "un nom de projet dans un fichier « -diff » est trouvé"
  assert_contains "nom de projet dans vendu/b.md, ligne 1" "$out" "et situé"
}

case_preset_renovate() {
  # AC 10 : git-submodules activé, et AUCUN branchPrefix, à quelque niveau que ce soit.
  local preset="$common/renovate/default.json"
  assert_eq true "$(jq -r '."git-submodules".enabled' "$preset")" "le manager git-submodules est activé"
  assert_eq 0 "$(jq '[.. | objects | select(has("branchPrefix"))] | length' "$preset")" "aucun branchPrefix dans le preset"
  # la garde elle-même : un preset qui en porterait un serait vu
  jq '. + {"packageRules": [{"branchPrefix": "x/"}]}' "$preset" > "$work/preset.json"
  assert_eq 1 "$(jq '[.. | objects | select(has("branchPrefix"))] | length' "$work/preset.json")" "un branchPrefix imbriqué serait trouvé"
}

case_workflow_nomme_comme_la_protection() {
  # La protection de main exige le contexte « checks / checks* » : workflow et job s'appellent checks.
  local wf
  wf=$(cat "$common/.gitea/workflows/checks.yml")
  assert_contains $'\nname: checks\n' "$wf" "le workflow s'appelle checks"
  assert_contains $'\njobs:\n  checks:\n' "$wf" "le job s'appelle checks"
  assert_contains $'shell: sh\n        run: sh bin/check-bash' "$wf" "le prérequis bash est vérifié en sh, avant tout bash"
  assert_contains "bash ci/checks-job.sh" "$wf" "le job lance le script partagé avec le poste"
}

# --- ci/ensure-shellcheck.sh ------------------------------------------------------------------------
# Aucun réseau : l'archive vient d'un fichier local (file://), et les outils du script sont reliés un
# par un dans un PATH d'essai, si bien qu'un shellcheck installé sur le poste ne s'y glisse jamais.
# Le curl relié est file_only_curl : le vrai, réduit aux URL file:// (le lanceur place un faux curl en
# tête du PATH, et le script testé n'a jamais le réseau). Les autres outils viennent de real_command.
outils_shellcheck() { # $1 = dossier ; $2… = outils à NE PAS relier
  local outil chemin
  mkdir -p "$1"
  for outil in sh curl sha256sum tar gzip uname sed cut dirname mkdir rm chmod mv cat printf; do
    [[ " ${*:2} " != *" $outil "* ]] || continue
    if [[ $outil == curl ]]; then
      file_only_curl "$1"
      continue
    fi
    chemin=$(real_command "$outil") || continue
    [[ $chemin == /* ]] || continue # builtin sans binaire : le sh d'essai a le sien
    ln -sf "$chemin" "$1/$outil"
  done
}
faux_shellcheck() { # $1 = dossier, $2 = version annoncée
  printf '#!/bin/sh\nprintf "ShellCheck\\nversion: %s\\n"\n' "$2" > "$1/shellcheck"
  chmod 755 "$1/shellcheck"
}
# Archive d'essai : même arborescence que l'archive amont, avec un shellcheck qui annonce la bonne
# version — seule son empreinte la distingue de la vraie.
archive_factice() {
  mkdir -p "$work/archive/shellcheck-v0.11.0"
  faux_shellcheck "$work/archive/shellcheck-v0.11.0" 0.11.0
  tar -czf "$work/archive.tar.gz" -C "$work/archive" shellcheck-v0.11.0
}
fournir() { # $1 = PATH ; le dossier de destination est sous $work/job
  run env -i PATH="$1" RUNNER_TEMP="$work/job" ENSURE_SHELLCHECK_URL="file://$work/archive.tar.gz" \
    "$(command -v sh)" "$common/ci/ensure-shellcheck.sh"
}

case_shellcheck_present_a_la_version_epinglee() {
  outils_shellcheck "$work/bin" curl
  faux_shellcheck "$work/bin" 0.11.0
  fournir "$work/bin"
  assert_eq 0 "$rc" "le shellcheck présent est retenu (messages : $err)"
  assert_eq "$work/bin" "$out" "son dossier est affiché"
  [[ ! -e $work/job ]] || { echo "rien ne doit être téléchargé" >&2; exit 1; }
}

case_shellcheck_autre_version_jamais_retenu() {
  # une autre version rendrait d'autres constats que la CI : l'archive épinglée est exigée
  archive_factice
  outils_shellcheck "$work/bin"
  faux_shellcheck "$work/bin" 0.9.0
  fournir "$work/bin"
  assert_eq 2 "$rc" "le shellcheck 0.9.0 n'est pas retenu, et l'archive d'essai est refusée"
  assert_contains "pas en version 0.11.0" "$err" "la raison du téléchargement est dite"
  assert_contains "empreinte SHA-256 inattendue" "$err" "l'archive non épinglée est refusée"
  assert_eq "" "$out" "aucun dossier affiché"
}

case_shellcheck_empreinte_refusee_rien_ne_reste() {
  archive_factice
  outils_shellcheck "$work/bin"
  fournir "$work/bin"
  assert_eq 2 "$rc" "une archive à l'empreinte inattendue est refusée (messages : $err)"
  assert_contains "empreinte SHA-256 inattendue" "$err" "raison"
  assert_eq "" "$(find "$work/job" -type f)" "aucun fichier téléchargé ne reste"
}

case_shellcheck_sans_curl_ni_sha256sum() {
  archive_factice
  outils_shellcheck "$work/sans-curl" curl
  fournir "$work/sans-curl"
  assert_eq 2 "$rc" "sans curl : code 2"
  assert_contains "curl introuvable" "$err" "raison"
  outils_shellcheck "$work/sans-somme" sha256sum
  fournir "$work/sans-somme"
  assert_eq 2 "$rc" "sans sha256sum : code 2, jamais une archive non vérifiée"
  assert_contains "sha256sum introuvable" "$err" "raison"
}

case_shellcheck_argument_refuse() {
  outils_shellcheck "$work/bin" curl
  run env -i PATH="$work/bin" RUNNER_TEMP="$work/job" "$(command -v sh)" "$common/ci/ensure-shellcheck.sh" --download "$work/x"
  assert_eq 2 "$rc" "un argument est refusé : code 2"
  assert_contains "aucun argument attendu" "$err" "raison"
  [[ ! -e $work/job && ! -e $work/x ]] || { echo "rien ne doit être créé" >&2; exit 1; }
}

case_shellcheck_telechargement_impossible() {
  # un téléchargement interrompu : curl écrit un début d'archive, puis échoue ; rien ne doit rester
  outils_shellcheck "$work/bin" curl
  # shellcheck disable=SC2016 # faux curl écrit sur le disque : ses « $ » s'y développent à l'exécution
  printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && { printf partiel > "$2"; }; shift; done\nexit 22\n' > "$work/bin/curl"
  chmod 755 "$work/bin/curl"
  fournir "$work/bin"
  assert_eq 2 "$rc" "téléchargement impossible : code 2"
  assert_contains "téléchargement de shellcheck 0.11.0 impossible" "$err" "raison"
  assert_eq "" "$(find "$work/job" -type f)" "aucun fichier partiel ne reste"
}

case_shellcheck_dossier_impossible_a_creer() {
  skip_if_root "le dossier en lecture seule"
  archive_factice
  outils_shellcheck "$work/bin"
  mkdir -p "$work/lecture-seule"
  chmod 555 "$work/lecture-seule"
  run env -i PATH="$work/bin" RUNNER_TEMP="$work/lecture-seule" ENSURE_SHELLCHECK_URL="file://$work/archive.tar.gz" \
    "$(command -v sh)" "$common/ci/ensure-shellcheck.sh"
  assert_eq 2 "$rc" "dossier de destination impossible à créer : code 2"
  assert_contains "impossible à créer" "$err" "raison"
}

case_shellcheck_sans_tar() {
  archive_factice
  outils_shellcheck "$work/sans-tar" tar
  fournir "$work/sans-tar"
  assert_eq 2 "$rc" "sans tar : code 2, avant tout téléchargement"
  assert_contains "tar introuvable" "$err" "raison"
  [[ ! -e $work/job ]] || { echo "rien ne doit être téléchargé sans tar" >&2; exit 1; }
}

# Après l'empreinte : un faux sha256sum rend l'empreinte épinglée, si bien qu'une archive d'essai
# franchit la vérification et que l'extraction, l'installation et la version installée s'exercent
# sans réseau. L'empreinte, elle, reste celle du script : le faux ne fait que l'annoncer.
apres_empreinte() { # $1 = dossier d'outils
  outils_shellcheck "$1" sha256sum
  # shellcheck disable=SC2016 # faux sha256sum écrit sur le disque : son « $1 » s'y développe à l'exécution
  printf '#!/bin/sh\necho "%s  $1"\n' "$(sed -n 's/^SHELLCHECK_SHA256=//p' "$common/ci/ensure-shellcheck.sh")" > "$1/sha256sum"
  chmod 755 "$1/sha256sum"
}

case_shellcheck_chemin_nominal_sans_reseau() {
  archive_factice
  apres_empreinte "$work/bin"
  fournir "$work/bin"
  assert_eq 0 "$rc" "archive au bon contenu : shellcheck fourni (messages : $err)"
  assert_eq "$work/job/shellcheck-0.11.0" "$out" "le dossier du binaire installé est affiché"
  assert_contains "version: 0.11.0" "$("$out/shellcheck" --version)" "le binaire installé est celui de l'archive"
  assert_eq "$work/job/shellcheck-0.11.0/shellcheck" "$(find "$work/job/shellcheck-0.11.0" -mindepth 1)" "seul le binaire reste : archive et dossier d'extraction supprimés"
}

case_shellcheck_dossier_d_extraction_impossible() {
  archive_factice
  apres_empreinte "$work/bin"
  # un faux mkdir qui refuse le seul dossier d'extraction, et délègue le reste au vrai
  rm -f "$work/bin/mkdir"
  printf '#!/bin/sh\ncase "$*" in *extraction*) exit 1 ;; esac\nexec %q "$@"\n' "$(command -v mkdir)" > "$work/bin/mkdir"
  chmod 755 "$work/bin/mkdir"
  fournir "$work/bin"
  assert_eq 2 "$rc" "dossier d'extraction impossible : code 2"
  assert_contains "extraction impossible à créer" "$err" "raison"
  assert_eq "" "$out" "aucun dossier affiché"
  assert_eq "" "$(find "$work/job" -type f)" "l'archive téléchargée ne reste pas"
}

case_shellcheck_installation_impossible_rien_ne_reste() {
  archive_factice
  apres_empreinte "$work/bin"
  # un faux mv qui échoue : le binaire extrait ne peut pas être mis en place
  rm -f "$work/bin/mv"
  printf '#!/bin/sh\nexit 1\n' > "$work/bin/mv"
  chmod 755 "$work/bin/mv"
  fournir "$work/bin"
  assert_eq 2 "$rc" "installation impossible : code 2"
  assert_contains "installation de shellcheck" "$err" "raison"
  assert_eq "" "$(find "$work/job" -mindepth 2)" "ni archive, ni dossier d'extraction ne restent"
}

case_shellcheck_archive_illisible() {
  printf 'pas une archive\n' > "$work/archive.tar.gz"
  apres_empreinte "$work/bin"
  fournir "$work/bin"
  assert_eq 2 "$rc" "archive illisible : code 2"
  assert_contains "archive de shellcheck illisible" "$err" "raison"
  assert_eq "" "$(find "$work/job" -type f)" "rien ne reste"
}

case_shellcheck_binaire_absent_de_l_archive() {
  mkdir -p "$work/archive/autre"
  printf 'x\n' > "$work/archive/autre/LISEZMOI"
  tar -czf "$work/archive.tar.gz" -C "$work/archive" autre
  apres_empreinte "$work/bin"
  fournir "$work/bin"
  assert_eq 2 "$rc" "binaire absent de l'archive : code 2"
  assert_contains "binaire absent de l'archive" "$err" "raison"
  assert_eq "" "$(find "$work/job" -type f)" "rien ne reste"
}

case_shellcheck_binaire_d_une_autre_version() {
  mkdir -p "$work/archive/shellcheck-v0.11.0"
  faux_shellcheck "$work/archive/shellcheck-v0.11.0" 0.10.0
  tar -czf "$work/archive.tar.gz" -C "$work/archive" shellcheck-v0.11.0
  apres_empreinte "$work/bin"
  fournir "$work/bin"
  assert_eq 2 "$rc" "binaire installé d'une autre version : code 2"
  assert_contains "pas en version 0.11.0" "$err" "raison"
  assert_eq "" "$out" "aucun dossier affiché"
  assert_eq "" "$(find "$work/job" -type f)" "le binaire refusé ne reste pas"
}

case_shellcheck_architecture_non_prevue() {
  archive_factice
  outils_shellcheck "$work/bin" uname
  printf '#!/bin/sh\necho aarch64\n' > "$work/bin/uname"
  chmod 755 "$work/bin/uname"
  fournir "$work/bin"
  assert_eq 2 "$rc" "architecture non prévue : code 2"
  assert_contains "architecture aarch64 non prévue" "$err" "raison"
}

case_shellcheck_lance_par_le_job() {
  assert_contains 'step "shellcheck (tous niveaux)" bash ci/run-shellcheck.sh' "$(cat "$common/ci/checks-job.sh")" \
    "le job lance l'analyse"
}

# ci/run-shellcheck.sh, dans un dépôt d'essai : ses deux scripts y sont copiés, et un faux shellcheck
# 0.11.0 en tête du PATH note ses arguments (ensure-shellcheck.sh le retient : bonne version).
depot_shellcheck() { # $1 = 1 pour suivre un script d'essai dans le dépôt
  new_repo
  mkdir -p "$work/depot/ci" "$work/sc"
  cp "$common/ci/run-shellcheck.sh" "$common/ci/ensure-shellcheck.sh" "$work/depot/ci/"
  # shellcheck disable=SC2016 # faux shellcheck écrit sur le disque : ses « $ » s'y développent à l'exécution
  printf '#!/bin/sh\ncase "$1" in --version) printf "ShellCheck\\nversion: 0.11.0\\n" ;; *) printf "%%s\\n" "$@" > %q ;; esac\n' \
    "$work/arguments" > "$work/sc/shellcheck"
  chmod 755 "$work/sc/shellcheck"
  if [[ ${1:-} == 1 ]]; then
    printf '#!/bin/sh\n' > "$work/depot/a b.sh"
    printf '#!/bin/sh\n' > "$work/depot/ligne
coupee.sh"
    git -C "$work/depot" add "a b.sh" "ligne
coupee.sh"
    git -C "$work/depot" commit -q -m "scripts"
  fi
}
analyse() { run env PATH="$work/sc:$PATH" TMPDIR="$work" bash "$work/depot/ci/run-shellcheck.sh" "$@"; }

case_shellcheck_lance_a_tous_les_niveaux() {
  depot_shellcheck 1
  analyse
  assert_eq 0 "$rc" "analyse lancée (messages : $err)"
  assert_contains "sur 2 script(s)" "$out" "les scripts suivis sont comptés, un nom coupé d'un saut de ligne compris"
  assert_eq "--
a b.sh
ligne
coupee.sh" "$(cat "$work/arguments")" "« -- », puis chaque script en argument, sans aucune option de sévérité"
}

case_shellcheck_nom_en_tiret_reste_un_fichier() {
  # un fichier suivi « -eSC2086.sh » serait lu comme l'option « -e SC2086 » sans « -- »
  depot_shellcheck
  printf '#!/bin/sh\n' > "$work/depot/-eSC2086.sh"
  git -C "$work/depot" add -- -eSC2086.sh
  git -C "$work/depot" commit -q -m "nom en tiret"
  analyse
  assert_eq 0 "$rc" "analyse lancée (messages : $err)"
  assert_eq "--
-eSC2086.sh" "$(cat "$work/arguments")" "le nom en tiret vient après « -- »"
}

case_shellcheck_fichier_temporaire_impossible() {
  depot_shellcheck 1
  printf '#!/bin/sh\nexit 1\n' > "$work/sc/mktemp"
  chmod 755 "$work/sc/mktemp"
  analyse
  assert_eq 2 "$rc" "mktemp en échec : code 2"
  assert_contains "fichier temporaire impossible" "$err" "raison"
  [[ ! -e $work/arguments ]] || { echo "shellcheck a été lancé sans liste" >&2; exit 1; }
}

case_shellcheck_version_illisible() {
  # le binaire répond à la vérification de version, puis plus : l'analyse s'arrête en le disant
  depot_shellcheck 1
  # shellcheck disable=SC2016 # faux shellcheck écrit sur le disque : ses « $ » s'y développent à l'exécution
  printf '#!/bin/sh\nif [ -e %q ]; then exit 3; fi\n: > %q\necho "version: 0.11.0"\n' "$work/deja" "$work/deja" > "$work/sc/shellcheck"
  analyse
  assert_eq 2 "$rc" "version illisible : code 2"
  assert_contains "ne répond pas à --version" "$err" "raison"
}

case_shellcheck_liste_vide_rend_2() {
  depot_shellcheck
  analyse
  assert_eq 2 "$rc" "aucun script suivi : jamais une réussite"
  assert_contains "aucun script suivi" "$err" "raison"
  [[ ! -e $work/arguments ]] || { echo "shellcheck a été lancé sans fichier" >&2; exit 1; }
}

case_shellcheck_liste_illisible_rend_2() {
  depot_shellcheck 1
  rm -rf "$work/depot/.git"
  analyse
  assert_eq 2 "$rc" "liste illisible : code 2"
  assert_contains "liste des scripts illisible" "$err" "raison"
}

case_shellcheck_fournisseur_en_echec_rend_2() {
  # un shellcheck d'une autre version est écarté, et l'archive épinglée n'est pas joignable :
  # ensure-shellcheck.sh échoue, et l'analyse ne passe jamais pour faite
  depot_shellcheck 1
  # shellcheck disable=SC2016 # faux shellcheck écrit sur le disque : son « $1 » s'y développe à l'exécution
  printf '#!/bin/sh\n[ "$1" = --version ] && { echo "version: 0.9.0"; exit 0; }\n: > %q\n' "$work/arguments" > "$work/sc/shellcheck"
  # le vrai curl, réduit aux URL file://, devant le faux du lanceur
  file_only_curl "$work/vrai-curl"
  run env PATH="$work/sc:$work/vrai-curl:$PATH" TMPDIR="$work" RUNNER_TEMP="$work/job" ENSURE_SHELLCHECK_URL="file://$work/absente.tar.gz" \
    bash "$work/depot/ci/run-shellcheck.sh"
  assert_eq 2 "$rc" "shellcheck impossible à fournir : code 2"
  assert_contains "shellcheck épinglé impossible à fournir" "$err" "raison"
  [[ ! -e $work/arguments ]] || { echo "un shellcheck non épinglé a été lancé" >&2; exit 1; }
}

case_shellcheck_argument_du_job_refuse() {
  depot_shellcheck 1
  analyse --inutile
  assert_eq 2 "$rc" "un argument est refusé"
}

# --- prérequis bash 4.3 -----------------------------------------------------------------------------
# bin/check-bash admet bash 4.3 : rien dans les scripts suivis ne doit exiger plus. Constructions
# relevées (manuel de bash, fichier NEWS) : « mapfile -d » / « readarray -d » et « local - » (4.4),
# transformations « ${x@Q} » et voisines (4.4), « shopt inherit_errexit » (4.4), « wait -p » (5.1),
# EPOCHSECONDS, EPOCHREALTIME, SRANDOM, BASH_ARGV0 (5.0). Une construction plus récente n'est admise
# que derrière une garde explicite, « 2>/dev/null || true » sur la même ligne (patsub_replacement,
# bash 5.2, dans review/llm-review.sh).
constructions_recentes() { # $@ = fichiers ; « fichier:ligne » de chaque construction non gardée
  grep -nHE '(mapfile|readarray)([[:space:]]+-[[:alnum:]]+)*[[:space:]]+-d|^[[:space:]]*local[[:space:]]+-([[:space:]]|$)|\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?@[QEPAaKkULu]\}|inherit_errexit|wait[[:space:]]+-p|EPOCHSECONDS|EPOCHREALTIME|SRANDOM|BASH_ARGV0' "$@" \
    | grep -v '2>/dev/null || true' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true
}

case_aucune_construction_posterieure_a_bash_4_3() {
  local scripts trouve
  mapfile -t scripts < <(git -C "$common" ls-files -- '*.sh' bin/check-bash bin/install bin/install.bash)
  ((${#scripts[@]})) || { echo "aucun script suivi" >&2; exit 1; }
  trouve=$(cd "$common" && constructions_recentes "${scripts[@]}" | grep -v '^tests/test-ci-checks.sh:' || true)
  assert_eq "" "$trouve" "aucune construction postérieure à bash 4.3 hors d'une garde"
  # la garde elle-même : chaque forme est vue dans un script d'essai
  # shellcheck disable=SC2016 # constructions écrites telles quelles dans un fichier d'essai
  printf '%s\n' "mapfile -d '' -t l < f" "readarray -t -d x l" "  local -" 'echo "${v@Q}"' 'echo "${t[0]@U}"' \
    "shopt -s inherit_errexit" "wait -p id" 'echo "$EPOCHSECONDS"' "shopt -u patsub_replacement 2>/dev/null || true" \
    "# mapfile -d dans un commentaire" > "$work/recent.sh"
  assert_eq 8 "$(constructions_recentes "$work/recent.sh" | grep -c .)" "huit constructions vues ; la ligne gardée et le commentaire écartés"
}

# --- ci/checks-job.sh : le pire code l'emporte. Un 2 (étape qui n'a pas pu vérifier) reste un 2 ---------

# Une copie du job dont chaque étape est un faux qui rend le code de $work/codes/<étape> (0 sinon).
job_aux_etapes() { # $@ = « étape=code »
  local racine=$work/job etape
  mkdir -p "$racine/ci" "$racine/tests" "$work/codes"
  cp "$common/ci/checks-job.sh" "$racine/ci/"
  for etape in tests/run.sh ci/check-secrets.sh ci/check-names.sh ci/run-shellcheck.sh ci/bmad-reinstall.sh; do
    # shellcheck disable=SC2016 # faux écrit sur le disque : son « $( ) » s'y développe à l'exécution
    printf '#!/usr/bin/env bash\nexit "$(cat %q 2>/dev/null || echo 0)"\n' "$work/codes/${etape//\//_}" > "$racine/$etape"
  done
  for etape in "$@"; do printf '%s' "${etape#*=}" > "$work/codes/${etape%%=*}"; done
  run bash "$racine/ci/checks-job.sh"
}

case_job_tout_passe_rend_0() {
  job_aux_etapes
  assert_eq 0 "$rc" "toutes les étapes à 0 : 0 ($err)"
}

case_job_un_ecart_rend_1() {
  job_aux_etapes ci_check-names.sh=1
  assert_eq 1 "$rc" "une étape à 1 : 1"
  assert_contains "::error::checks-job : aucun nom de projet — écart constaté (code 1)" "$err" "l'étape rouge porte son ::error::"
}

case_job_un_2_l_emporte_sur_un_1() {
  job_aux_etapes ci_check-names.sh=1 tests_run.sh=2
  assert_eq 2 "$rc" "une étape à 2 et une à 1 : 2, jamais rangé en 1"
  assert_contains "::error::checks-job : tests — anomalie, rien n'a été vérifié (code 2)" "$err" "le 2 est nommé comme anomalie"
  assert_contains "::error::checks-job : aucun nom de projet — écart constaté (code 1)" "$err" "le 1 reste nommé"
}

case_job_sans_jq_ni_moyen_de_le_fournir_rend_2() {
  job_aux_etapes
  printf '#!/bin/sh\nexit 2\n' > "$work/job/ci/ensure-jq.sh"
  # un PATH réduit aux outils du job, sans jq
  local outil
  mkdir -p "$work/sans-jq"
  for outil in bash sh dirname cat; do ln -s "$(real_command "$outil")" "$work/sans-jq/$outil"; done
  run env PATH="$work/sans-jq" "$work/sans-jq/bash" "$work/job/ci/checks-job.sh"
  assert_eq 2 "$rc" "jq impossible à fournir : aucune étape ne tourne, code 2"
  assert_contains "::error::checks-job : jq impossible à fournir" "$err" "l'étape rouge porte son ::error::"
}

case_job_un_code_inattendu_rend_2() {
  job_aux_etapes ci_run-shellcheck.sh=127
  assert_eq 2 "$rc" "un code hors convention (127, outil introuvable) : anomalie"
}

run_case "$@"
