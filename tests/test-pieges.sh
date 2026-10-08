#!/usr/bin/env bash
# Pièges du tableau « Pièges connus » de procedures/shell-scripts.md qui tiennent au shell lui-même,
# et non à un script de ce dépôt. Chaque cas rejoue le piège (la forme fautive rend ce que le tableau
# annonce) puis sa parade (la forme sûre rend ce qu'on attend) : si un shell changeait de
# comportement, le tableau deviendrait faux, et ce fichier le dirait.
# « set -euo pipefail » vient de tests/lib.sh, comme pour chaque fichier de test.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case_piege_tail_rend_le_code_de_tail() {
  # Sans pipefail (POSIX sh), un pipeline rend le code de sa dernière commande.
  run sh -c 'false | tail -n 1'
  assert_eq 0 "$rc" "piège : « commande | tail » rend 0 quand la commande échoue"
  # Parade : la sortie dans un fichier, le code testé, puis le fichier affiché.
  run sh -c 'f=$(mktemp) || exit 2; false > "$f"; code=$?; tail -n 1 "$f"; rm -f "$f"; exit "$code"'
  assert_eq 1 "$rc" "parade : le code de la commande arrive jusqu'à l'appelant"
}

case_piege_for_sur_une_substitution_avale_l_echec() {
  # « for x in $(cmd) » : la substitution échoue, la boucle ne tourne pas, et rend 0, même sous set -e.
  for shell in sh bash; do
    # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
    run "$shell" -ec 'for x in $(false); do echo "jamais : $x"; done; echo "garde passée"'
    assert_eq 0 "$rc" "piège ($shell) : la boucle sur une substitution en échec rend 0"
    assert_eq "garde passée" "$out" "piège ($shell) : la garde passe sans avoir rien vérifié"
    # Parade : la liste lue dans une variable d'abord, avec son arrêt.
    # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
    run "$shell" -ec 'liste=$(false) || { echo "liste illisible" >&2; exit 2; }; for x in $liste; do :; done; echo "jamais"'
    assert_eq 2 "$rc" "parade ($shell) : l'échec de l'extracteur arrête la garde"
    assert_eq "" "$out" "parade ($shell) : rien ne s'exécute après l'arrêt"
  done
}

case_piege_grep_tue_par_sigpipe_sous_pipefail() {
  # « grep … | head -n 1 » sous pipefail : head sort après la première ligne, grep écrit encore et
  # reçoit SIGPIPE (128 + 13 = 141), et pipefail fait échouer le pipeline. Le fichier dépasse la
  # capacité d'un tube, si bien que grep écrit après la sortie de head : le résultat ne dépend pas de
  # la vitesse de la machine. Sur une entrée plus courte, c'est une course (gagnée ou perdue selon la
  # charge), ce qui rend le piège plus dangereux encore.
  seq 1 200000 > "$work/lignes"
  run bash -c 'set -o pipefail; grep "1" "$1" | head -n 1' _ "$work/lignes"
  assert_eq 141 "$rc" "piège : grep tué par SIGPIPE fait échouer le pipeline, sans un message"
  assert_eq "" "$err" "piège : aucun message d'erreur"
  # Parade : grep s'arrête lui-même à la première correspondance, ou la sortie est lue en entier
  # dans une variable avant d'être filtrée.
  run bash -c 'set -o pipefail; grep -m 1 "1" "$1"' _ "$work/lignes"
  assert_eq 0 "$rc" "parade : grep -m 1 rend 0"
  assert_eq 1 "$out" "parade : la première correspondance"
}

case_piege_dash_sans_sous_chaine() {
  # ${VAR:0:N} n'est pas POSIX : bash et le sh de BusyBox l'acceptent, dash le refuse à l'exécution,
  # et « sh -n » ne le voit pas. Un script POSIX sh essayé sous bash ou BusyBox seulement passe.
  local dash_bin
  dash_bin=$(command -v dash) || skip_case "dash absent de ce poste : le piège ne se rejoue que sous dash"
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run "$dash_bin" -n -c 'v=abcdef; printf "%s\n" "${v:0:2}"'
  assert_eq 0 "$rc" "piège : la vérification de syntaxe ne voit rien"
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run "$dash_bin" -c 'v=abcdef; printf "%s\n" "${v:0:2}"'
  assert_eq 2 "$rc" "piège : dash refuse \${v:0:2} à l'exécution (sortie : $out)"
  assert_contains "Bad substitution" "$err" "piège : dash le refuse à l'exécution"
  # Parade POSIX : retirer le reste plutôt que prendre le début.
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  run "$dash_bin" -c 'v=abcdef; reste=${v#??}; printf "%s\n" "${v%"$reste"}"'
  assert_eq 0 "$rc" "parade : dash l'accepte (messages : $err)"
  assert_eq ab "$out" "parade : les deux premiers caractères"
}

case_piege_diff_de_busybox_unifie_par_defaut() {
  # Le diff de BusyBox écrit le format unifié par défaut (« -a », « +c ») là où GNU diff écrit le
  # format classique (« < a », « > c ») : chercher « ^< » ne trouve jamais rien sous BusyBox, et une
  # garde « aucune ligne supprimée » passe sans avoir rien vu (constat de la CI, 06/10/2026).
  local bb
  bb=$(command -v busybox) || skip_case "busybox absent de ce poste : le piège ne se rejoue qu'avec son diff"
  printf 'a\nb\n' > "$work/avant"
  printf 'b\nc\n' > "$work/apres"
  run "$bb" diff "$work/avant" "$work/apres"
  assert_eq 1 "$rc" "piège : les fichiers diffèrent"
  [[ $'\n'$out != *$'\n<'* ]] || { echo "piège : le diff de BusyBox écrit le format classique, le piège n'existe plus" >&2; exit 1; }
  assert_contains $'\n-a' "$out" "piège : la ligne supprimée s'écrit « -a »"
  # Parade : demander le format unifié, que GNU et BusyBox écrivent tous deux ; après les deux lignes
  # d'en-tête, une ligne en « - » est une ligne supprimée.
  local outil
  for outil in diff "$bb diff"; do
    # shellcheck disable=SC2086 # découpage voulu : « busybox diff »
    run $outil -U0 "$work/avant" "$work/apres"
    assert_eq 1 "$rc" "parade ($outil) : les fichiers diffèrent"
    assert_eq "-a" "$(sed -n 4p <<< "$out")" "parade ($outil) : la ligne supprimée, après les en-têtes et le premier bloc"
  done
}

case_piege_point_de_regex_traverse_les_lignes() {
  # Le « . » de [[ =~ ]] (expression étendue de la libc, sans REG_NEWLINE) traverse « \n » : ancrée par
  # ^ et $, une expression qui finit par « .* » accepte une ligne suivie de n'importe quelles autres.
  local texte=$'-Status: review  # x\n-## une autre ligne retirée'
  local -r motif='^-Status: review( +#.*)?$'
  [[ $texte =~ $motif ]] || { echo "constat attendu : le motif accepte les deux lignes" >&2; exit 1; }
  # Parade : une seule ligne, vérifiée avant la comparaison.
  if [[ $texte != *$'\n'* && $texte =~ $motif ]]; then
    echo "parade : deux lignes ne passent plus pour une" >&2; exit 1
  fi
  local -r une=$'-Status: review  # x'
  [[ $une != *$'\n'* && $une =~ $motif ]] || { echo "parade : une ligne seule passe" >&2; exit 1; }
}

case_piege_processus_git_detache_apres_un_commit() {
  # Un commit lance « git maintenance run --auto --detach », qui survit à la commande : ce processus
  # peut encore écrire dans le dépôt d'essai pendant le « rm -rf » de fin de cas.
  new_repo
  printf 'a\n' > "$work/depot/a"
  git -C "$work/depot" add a
  # Constat, sans la parade de tests/lib.sh : GIT_CONFIG_COUNT=0 retire la configuration injectée.
  # La maintenance est seulement gardée au premier plan (autoDetach), pour que ce constat ne laisse
  # lui-même aucun processus derrière lui.
  local lance
  GIT_CONFIG_COUNT=0 GIT_TRACE2_EVENT="$work/trace-sans" \
    git -C "$work/depot" -c maintenance.autoDetach=false commit -q -m sans
  shell_grep_into lance -c '"child_start".*"maintenance","run","--auto"' "$work/trace-sans"
  assert_eq 1 "$lance" "constat : sans la parade, le commit lance une maintenance automatique"
  # Parade : la configuration injectée par tests/lib.sh vaut pour chaque dépôt d'essai, qu'il soit
  # créé par new_repo, par un « git init » direct ou cloné en sous-module.
  local depot cle
  git -C "$work" init -q nu
  git -C "$work/nu" -c user.name=essai -c user.email=essai@example.invalid -c core.hooksPath=/dev/null \
    commit -q --allow-empty -m nu
  git -C "$work/depot" -c protocol.file.allow=always submodule add -q "$work/nu" sous-module
  for depot in depot nu depot/sous-module; do
    for cle in maintenance.auto=false gc.auto=0 core.fsmonitor=false; do
      assert_eq "${cle#*=}" "$(git -C "$work/$depot" config --get "${cle%%=*}")" "parade : ${cle%%=*} dans $depot"
    done
  done
  printf 'b\n' > "$work/depot/b"
  git -C "$work/depot" add b
  GIT_TRACE2_EVENT="$work/trace-avec" git -C "$work/depot" commit -q -m avec
  shell_grep_into lance -c '"child_start".*"maintenance"' "$work/trace-avec"
  assert_eq 0 "$lance" "parade : le commit ne lance plus aucune maintenance"
}

# Un fichier de test minimal, dans un dépôt d'essai, qui charge tests/lib.sh et affiche la configuration
# injectée : la parade s'éprouve au chargement de la bibliothèque, comme dans un vrai fichier de test.
charge_lib() { # $1 = valeur de GIT_CONFIG_COUNT (« - » : absente), $2… = variables d'environnement
  local compte=$1
  shift
  new_repo
  {
    printf '. %s\n' "$(sh_quote "$tests_dir/lib.sh")"
    cat <<'FIN'
case_affiche() {
  git -C "$work" config --get-regexp '^(essai\.cle|maintenance\.auto|gc\.auto|core\.fsmonitor)$' | LC_ALL=C sort
  echo "compte=$GIT_CONFIG_COUNT"
}
run_case "$@"
FIN
  } > "$work/depot/test-essai.sh"
  if [[ $compte == - ]]; then
    run env -u GIT_CONFIG_COUNT "$@" bash "$work/depot/test-essai.sh" affiche
  else
    run env GIT_CONFIG_COUNT="$compte" "$@" bash "$work/depot/test-essai.sh" affiche
  fi
}

case_piege_processus_git_detache_configuration_ajoutee() {
  # Une configuration déjà injectée par l'appelant est gardée : la parade s'ajoute après elle.
  charge_lib 1 GIT_CONFIG_KEY_0=essai.cle GIT_CONFIG_VALUE_0=gardee
  assert_eq 0 "$rc" "chargement (messages : $err)"
  assert_eq $'core.fsmonitor false\nessai.cle gardee\ngc.auto 0\nmaintenance.auto false\ncompte=4' "$out" \
    "la clé de l'appelant est gardée, les trois de la parade viennent après"
  # Un zéro de tête se lit en base 10, comme git le lit : « 08 » n'est pas un octal invalide.
  local -a huit=()
  local i
  for i in 0 1 2 3 4 5 6 7; do huit+=("GIT_CONFIG_KEY_$i=essai.cle" "GIT_CONFIG_VALUE_$i=cle$i"); done
  charge_lib 08 "${huit[@]}"
  assert_eq 0 "$rc" "chargement d'un compte à zéro de tête (messages : $err)"
  assert_contains $'essai.cle cle7\ngc.auto 0' "$out" "la dernière clé de l'appelant est gardée"
  assert_contains "compte=11" "$out" "les trois clés de la parade viennent après la huitième"
  charge_lib -
  assert_eq 0 "$rc" "chargement sans configuration injectée (messages : $err)"
  assert_eq $'core.fsmonitor false\ngc.auto 0\nmaintenance.auto false\ncompte=3' "$out" "sans configuration injectée"
}

case_piege_processus_git_detache_compte_illisible() {
  # Un GIT_CONFIG_COUNT illisible arrête le fichier de test en 2 au chargement, avant tout cas.
  charge_lib x
  assert_eq 2 "$rc" "un compte illisible est une anomalie"
  assert_contains "GIT_CONFIG_COUNT illisible : x" "$err" "le message nomme la valeur"
  assert_eq "" "$out" "aucun cas ne tourne"
}

run_case "$@"
