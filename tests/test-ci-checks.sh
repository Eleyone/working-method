#!/usr/bin/env bash
# Contrôles de la CI du dépôt commun : « aucun secret » (ci/check-secrets.sh, AC 11), « aucun nom de
# projet » (ci/check-names.sh, AC 3), preset Renovate (AC 10) et contrat du workflow avec la protection
# de main. Les secrets et les noms d'essai sont fabriqués à l'exécution, par morceaux : écrits en clair
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
  printf 'GITEA_TOKEN=<jeton>\nGITEA_TOKEN: ${{ secrets.JETON_ESSAI_DE_LA_FORGE }}\nhttps://<compte>:<jeton>@forge\nGITEA_TOKEN absente de .env\n' \
    > "$work/depot/procedure.md"
  commit_all "procédure" > /dev/null
  secrets
  assert_eq 0 "$rc" "les repères des procédures ne sont pas des secrets (messages : $out)"
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
  run env -u CHECK_NAMES_PATTERNS bash -c 'cd "$1" && bash "$2/ci/check-names.sh"' _ "$work/depot" "$common"
  assert_eq 2 "$rc" "sans liste, le contrôle sort en 2, jamais vert"
  assert_contains "liste des noms absente" "$err" "et le dit"
  printf '# rien\n\n' > "$work/vide.txt"
  run bash -c 'cd "$1" && bash "$2/ci/check-names.sh" --patterns-file "$3"' _ "$work/depot" "$common" "$work/vide.txt"
  assert_eq 2 "$rc" "une liste vide ne contrôle rien"
  printf '(\n' > "$work/invalide.txt"
  run bash -c 'cd "$1" && bash "$2/ci/check-names.sh" --patterns-file "$3"' _ "$work/depot" "$common" "$work/invalide.txt"
  assert_eq 2 "$rc" "une expression invalide n'est jamais « aucune correspondance »"
  run env CHECK_NAMES_PATTERNS="$(printf 'eley''one[.]fr')" bash -c 'cd "$1" && bash "$2/ci/check-names.sh"' _ "$work/depot" "$common"
  assert_eq 0 "$rc" "la liste passée par la variable est lue (messages : $err)"
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

run_case "$@"
