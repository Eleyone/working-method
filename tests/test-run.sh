#!/usr/bin/env bash
# Lanceur des tests et ses gardes : la suite ne touche jamais les sorties que le projet protège
# (tests.protected-outputs, rétrospective de l'epic 2 du projet source, F1) ni l'état git du dépôt ;
# chaque cas tourne dans son propre processus ; un cas n'appelle jamais le vrai docker, curl, psql ou ssh.
# Hors ligne : run.sh, lib.sh et les bibliothèques sont copiés dans un faux dépôt git, avec un fichier
# de test d'essai et un workflow.config.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

faux_depot() { # $1 = corps du cas d'essai, $2… = changements du workflow.config ; prépare $work/faux avec un public/ témoin
  local corps=$1
  shift
  mkdir -p "$work/faux/tests" "$work/faux/lib" "$work/faux/public"
  cp "$common/tests/run.sh" "$common/tests/lib.sh" "$work/faux/tests/"
  # lib.sh charge les enveloppes communes, run.sh le lecteur de workflow.config : le faux dépôt les emporte
  cp "$common/lib/shell.sh" "$common/lib/config.sh" "$work/faux/lib/"
  : > "$work/faux/public/index.html"
  # Les sorties de build sont ignorées par git, comme dans un vrai projet : seul le relevé des sorties
  # protégées les voit, pas celui de git status.
  printf 'public/\nbuild/\ndist/\n' > "$work/faux/.gitignore"
  # shellcheck disable=SC2016 # fichier de test factice écrit sur le disque : ses « $ » s'y développent à l'exécution
  printf '#!/usr/bin/env bash\n. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"\ncase_essai() {\n  %s\n}\nrun_case "$@"\n' "$corps" \
    > "$work/faux/tests/test-essai.sh"
  git -C "$work/faux" init -q
  write_workflow_config "$work/faux" "$@"
}

case_run_accepte_une_suite_qui_ne_touche_pas_les_sorties() {
  faux_depot 'true'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "suite sans effet sur public/ (messages : $err)"
  assert_contains "1 cas réussis" "$out" "le cas est compté"
}

case_run_refuse_une_suite_qui_efface_public() {
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'rm -rf "$root/public"'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "une suite qui efface public/ échoue"
  assert_contains "a modifié une sortie protégée du projet (public build)" "$err" "le message nomme les sorties protégées"
}

case_run_refuse_une_suite_qui_cree_build() {
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'mkdir -p "$root/build/work"'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "une suite qui crée build/ échoue"
}

case_run_sorties_lues_dans_workflow_config() {
  # Les sorties ne sont plus écrites dans le lanceur : un autre nom est protégé, public/ ne l'est plus.
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'mkdir -p "$root/dist"' "tests.protected-outputs=dist"
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "la sortie déclarée est protégée"
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'rm -rf "$root/public"' "tests.protected-outputs=dist"
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "une sortie non déclarée n'est pas relevée (messages : $err)"
}

case_run_none_le_dit() {
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'rm -rf "$root/public"' "tests.protected-outputs=none"
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "aucune sortie protégée : la suite passe (messages : $err)"
  assert_contains "aucune sortie protégée (tests.protected-outputs = none)" "$err" "et le lanceur le dit"
}

case_run_workflow_config_refuse() {
  faux_depot 'true' -tests.protected-outputs
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 2 "$rc" "un workflow.config incomplet empêche les tests de tourner"
  assert_contains "tests.protected-outputs : champ absent" "$err" "le champ manquant est nommé"
}

# Remplace le fichier de test d'essai du faux dépôt par celui lu sur l'entrée standard.
fichier_essai() {
  cat > "$work/faux/tests/test-essai.sh"
}

# --- un processus par cas ---------------------------------------------------------------------------
# Un cas lancé dans le processus du lanceur, ou derrière un « || » de celui-ci, aurait son set -e
# suspendu : « false » au milieu du cas passerait en silence, et le cas réussirait sans rien tester.

case_run_set_e_actif_dans_chaque_cas() {
  faux_depot 'false; true'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "un échec au milieu du cas le fait échouer : set -e y est actif (messages : $err)"
  assert_contains "ÉCHEC tests/test-essai.sh : essai" "$err" "le cas est nommé"
}

case_run_aucun_etat_partage_entre_les_cas() {
  # Le premier cas laisse une variable et un dossier courant ; le second, lancé après lui
  # (ordre alphabétique de --list), ne doit rien en voir.
  faux_depot 'true'
  # shellcheck disable=SC2016 # fichier de test factice écrit sur le disque : ses « $ » s'y développent à l'exécution
  fichier_essai <<'ESSAI'
#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
case_a_laisse_un_etat() {
  ETAT_LAISSE=oui
  cd /
}
case_b_ne_le_voit_pas() {
  [[ -z ${ETAT_LAISSE:-} ]] || { echo "variable héritée du cas précédent" >&2; exit 1; }
  [[ $PWD == "$root" ]] || { echo "dossier courant hérité : $PWD" >&2; exit 1; }
}
run_case "$@"
ESSAI
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "chaque cas part d'un processus neuf (messages : $err)"
  assert_contains "2 cas réussis" "$out" "les deux cas sont comptés"
}

# --- aucun vrai docker, curl, psql ni ssh -----------------------------------------------------------

case_run_refuse_un_appel_reel_aux_outils_interdits() {
  local outil
  for outil in docker curl psql ssh; do
    # « || true » : même un appel dont le cas avale l'échec est vu
    faux_depot "$outil --version >/dev/null 2>&1 || true"
    run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
    assert_eq 1 "$rc" "$outil appelé pour de vrai : la suite échoue (messages : $err)"
    assert_contains "ÉCHEC tests/test-essai.sh : essai" "$err" "$outil : le cas est nommé"
    assert_contains "appel réel à $outil" "$err" "$outil : l'outil est nommé"
  done
}

case_run_refuse_un_appel_reel_par_lien_ou_sans_environnement() {
  # Un cas qui relie l'outil trouvé dans son PATH (forme courante d'un PATH d'essai) ou qui vide son
  # environnement atteint le faux du lanceur : l'appel est vu quand même.
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : ses « $ » s'y développent à l'exécution
  faux_depot 'mkdir -p "$work/bin" && ln -s "$(command -v curl)" "$work/bin/curl" && { "$work/bin/curl" -s file:///dev/null || true; }'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "curl relié par un lien : la suite échoue (messages : $err)"
  assert_contains "appel réel à curl" "$err" "lien : l'outil est nommé"
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : ses « $ » s'y développent à l'exécution
  faux_depot 'env -i PATH="$PATH" ssh hote true || true'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "ssh sans environnement : la suite échoue (messages : $err)"
  assert_contains "appel réel à ssh" "$err" "env -i : l'outil est nommé"
}

case_run_refuse_un_appel_reel_meme_si_le_cas_echoue() {
  faux_depot 'docker ps; false'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "le cas échoue"
  assert_contains "appel réel à docker" "$err" "l'appel réel est dit, pas seulement l'échec"
}

case_run_accepte_un_faux_place_devant() {
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : ses « $ » s'y développent à l'exécution
  faux_depot 'mkdir -p "$work/faux-bin" && printf "#!/bin/sh\nexit 0\n" > "$work/faux-bin/docker" && chmod +x "$work/faux-bin/docker" && PATH="$work/faux-bin:$PATH" docker ps'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "un cas qui place son faux docker devant passe (messages : $err)"
}

case_run_vrai_binaire_hors_des_faux() {
  # Un cas qui a besoin d'un vrai outil hors réseau (curl sur une URL file://, par exemple) le
  # demande nommément : real_command le cherche dans le PATH, sans les faux du lanceur.
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : ses « $ » s'y développent à l'exécution
  faux_depot 'chemin=$(real_command sh) && [[ $chemin == /* && $chemin != "$TESTS_FORBIDDEN_DIR"/* ]] && ! real_command outil-qui-n-existe-pas'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "real_command rend le vrai binaire, et échoue sur un outil absent (messages : $err)"
  # une entrée vide du PATH (le dossier courant) n'est jamais retenue
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : ses « $ » s'y développent à l'exécution
  faux_depot 'mkdir -p "$work/ici" && printf "#!/bin/sh\n" > "$work/ici/outil-ici" && chmod +x "$work/ici/outil-ici" && cd "$work/ici" && ! PATH="::$PATH:" real_command outil-ici'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "un outil du dossier courant n'est pas retenu (messages : $err)"
}

# --- git status identique avant et après la suite ---------------------------------------------------

case_run_refuse_une_suite_qui_modifie_l_etat_git() {
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot ': > "$root/nouveau.txt"'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "un fichier non suivi créé fait échouer la suite (messages : $err)"
  assert_contains "a modifié l'état git du dépôt" "$err" "le message nomme la garde"
  assert_contains "nouveau.txt" "$err" "l'écart est affiché"
}

case_run_refuse_une_modification_d_un_fichier_deja_modifie() {
  # Un fichier déjà modifié avant la suite garde la même ligne « M » dans git status : seul le
  # contenu du diff montre qu'un cas l'a modifié de nouveau.
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'echo encore >> "$root/suivi.txt"'
  echo un > "$work/faux/suivi.txt"
  git -C "$work/faux" add suivi.txt
  echo deux >> "$work/faux/suivi.txt"
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "une seconde modification d'un fichier suivi fait échouer la suite (messages : $err)"
  assert_contains "a modifié l'état git du dépôt" "$err" "le message nomme la garde"
}

case_run_refuse_une_suite_qui_modifie_l_index_seul() {
  # Un fichier indexé, identique dans l'arbre : sa ligne reste « A » si un cas le modifie et l'indexe
  # de nouveau, et le diff de l'arbre reste vide. Seule l'empreinte de l'index voit l'écart.
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'echo deux > "$root/indexe.txt" && git -C "$root" add indexe.txt'
  echo un > "$work/faux/indexe.txt"
  git -C "$work/faux" add indexe.txt
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "une modification de l'index seul fait échouer la suite (messages : $err)"
  assert_contains "a modifié l'état git du dépôt" "$err" "le message nomme la garde"
}

# Commits vides dans le faux dépôt, sans hook ni configuration du poste ; affiche le dernier SHA.
commit_faux() { # $1 = message
  git -C "$work/faux" -c user.name=essai -c user.email=essai@example.invalid -c core.hooksPath=/dev/null \
    -c commit.gpgsign=false commit -q --allow-empty -m "$1"
  git -C "$work/faux" rev-parse HEAD
}

# Lance la suite du faux dépôt et attend l'échec de la garde de l'état git.
attend_refus_etat_git() { # $1 = libellé
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "$1 : la suite échoue (messages : $err)"
  assert_contains "a modifié l'état git du dépôt" "$err" "$1 : le message nomme la garde"
}

# Chacun des cas suivants laisse l'arbre et l'index identiques : seul le relevé de l'historique local
# voit l'écart. Chaque ligne de ce relevé a un cas vu rouge sans elle : branche créée (refs/heads),
# étiquette, remise, passage en HEAD détachée (symbolic-ref), déplacement de HEAD détachée (rev-parse).

case_run_refuse_une_suite_qui_commite() {
  # la branche courante avance : refs/heads
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'git -C "$root" -c user.name=essai -c user.email=essai@example.invalid -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -q --allow-empty -m essai'
  attend_refus_etat_git "un commit"
}

case_run_refuse_un_reset_sur_le_meme_arbre() {
  # la branche recule vers un commit au même arbre : refs/heads
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'git -C "$root" reset -q --hard HEAD~1'
  commit_faux un > /dev/null
  commit_faux deux > /dev/null
  attend_refus_etat_git "un reset"
}

case_run_refuse_une_branche_creee() {
  # HEAD ne bouge pas : seule la liste des branches voit l'écart
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'git -C "$root" branch essai-2'
  commit_faux un > /dev/null
  attend_refus_etat_git "une branche créée"
}

case_run_refuse_une_etiquette() {
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'git -C "$root" tag essai'
  commit_faux un > /dev/null
  attend_refus_etat_git "une étiquette"
}

case_run_refuse_une_remise() {
  # refs/stash écrit directement : un « git stash » complet modifierait aussi l'arbre
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'git -C "$root" update-ref refs/stash HEAD'
  commit_faux un > /dev/null
  attend_refus_etat_git "une remise"
}

case_run_refuse_un_passage_en_head_detachee() {
  # même commit, mais HEAD ne désigne plus la branche : seule la lecture symbolique de HEAD le voit
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'git -C "$root" checkout -q --detach'
  commit_faux un > /dev/null
  attend_refus_etat_git "HEAD détachée"
}

case_run_refuse_un_deplacement_de_head_detachee() {
  # HEAD détachée, déplacée vers un autre commit au même arbre : aucune référence ne bouge
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : « $root » y est celui du cas
  faux_depot 'git -C "$root" checkout -q --detach HEAD~1'
  commit_faux un > /dev/null
  commit_faux deux > /dev/null
  git -C "$work/faux" checkout -q --detach
  attend_refus_etat_git "HEAD détachée déplacée"
}

case_run_curl_reduit_aux_fichiers_locaux() {
  # file_only_curl : le vrai curl pour une URL file://, le faux du lanceur pour toute autre URL.
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : ses « $ » s'y développent à l'exécution
  faux_depot 'echo contenu > "$work/source" && file_only_curl "$work/c" && "$work/c/curl" -s -o "$work/copie" "file://$work/source" && [[ $(cat "$work/copie") == contenu ]]'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "une URL file:// passe par le vrai curl (messages : $err)"
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : ses « $ » s'y développent à l'exécution
  faux_depot 'file_only_curl "$work/c" && { "$work/c/curl" -s https://example.invalid/ || true; }'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "une autre URL est un appel réel (messages : $err)"
  assert_contains "appel réel à curl" "$err" "l'outil est nommé"
  # une adresse sans schéma : curl la lirait en http ; --proto =file la refuse (code 1, « protocole
  # non pris en charge »), avant toute résolution de nom (code 6)
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : ses « $ » s'y développent à l'exécution
  faux_depot 'file_only_curl "$work/c" && code=0 && { "$work/c/curl" -s example.invalid || code=$?; } && [[ $code == 1 ]]'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "une adresse sans schéma est refusée par curl lui-même (messages : $err)"
  # une option --proto du script testé lèverait la restriction : elle est un appel réel
  # shellcheck disable=SC2016 # corps de cas écrit dans le fichier factice : ses « $ » s'y développent à l'exécution
  faux_depot 'file_only_curl "$work/c" && { "$work/c/curl" -s example.invalid --proto =all || true; }'
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 1 "$rc" "--proto du script testé : la suite échoue (messages : $err)"
  assert_contains "appel réel à curl" "$err" "--proto : l'outil est nommé"
}

case_run_etat_git_inchange_accepte() {
  # Un dépôt déjà sale avant la suite n'est pas un échec : seul un écart entre avant et après l'est.
  faux_depot 'true'
  : > "$work/faux/deja-la.txt"
  run bash -c 'cd "$1" && bash tests/run.sh' _ "$work/faux"
  assert_eq 0 "$rc" "état git inchangé : la suite passe (messages : $err)"
}

run_case "$@"
