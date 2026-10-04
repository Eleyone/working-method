#!/usr/bin/env bash
# Enveloppes communes (lib/shell.sh, actions de la rétrospective de l'epic 3 du projet source). Elles sont
# employées par les contrôles, les tests, les scripts et les bibliothèques de décision : leur contrat
# se vérifie ici une fois pour toutes.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Chaque appel tourne dans son propre bash : shell_die s'arrête par « exit », qui terminerait le cas.
enveloppe() { # $1 = corps à exécuter après le chargement
  run bash -c 'script_name=essai; . "$1/lib/shell.sh"; shift; eval "$1"' _ "$common" "$1"
}

case_shell_grep_into_trouve_et_ne_trouve_pas() {
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  enveloppe 'shell_grep_into v -c "shell_grep_into" "'"$common"'/lib/shell.sh"; echo "rc=$? v=$v"'
  assert_eq 0 "$rc" "une correspondance passe (messages : $err)"
  assert_contains "rc=0" "$out" "l'enveloppe rend 0"
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  enveloppe 'shell_grep_into v -F "zzz-motif-absent-zzz" "'"$common"'/lib/shell.sh"; echo "rc=$? v=[$v]"'
  assert_eq 0 "$rc" "rien trouvé n'est pas une erreur"
  assert_contains "rc=0 v=[]" "$out" "l'enveloppe rend 0 et la variable est vide : rendre 1 tuerait un appel nu sous set -e"
}

case_shell_grep_into_erreur_arrete() {
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  enveloppe 'shell_grep_into v -F "x" /fichier/qui/nexiste/pas; echo "jamais atteint"'
  assert_eq 2 "$rc" "une erreur de lecture arrête le script, code 2 (anomalie)"
  assert_contains "recherche impossible (grep, code 2)" "$err" "le message nomme l'outil et son code"
  assert_eq "" "$out" "rien n'est exécuté après l'arrêt"
}

case_shell_grep_into_code_darret_configurable() {
  # Les tests mettent shell_error_exit à 1 : un cas en échec, pas une anomalie.
  run bash -c 'script_name=essai; shell_error_exit=1; . "$1/lib/shell.sh"; shell_grep_into v -F x /fichier/absent' _ "$common"
  assert_eq 1 "$rc" "le code d'arrêt suit shell_error_exit"
}

case_shell_grep_status_ne_quitte_jamais() {
  # Contrat de bibliothèque : répondre par son code, jamais quitter l'appelant.
  enveloppe 'shell_grep_status v -F "x" /fichier/absent; echo "rc=$?"'
  assert_eq 0 "$rc" "l'appelant continue (messages : $err)"
  assert_contains "rc=2" "$out" "le code de grep est rendu tel quel"
  enveloppe 'shell_grep_status v -F "zzz-absent-zzz" "'"$common"'/lib/shell.sh"; echo "rc=$?"'
  assert_contains "rc=1" "$out" "rien trouvé se distingue d'une erreur"
}

case_shell_grep_sur_la_sortie_standard() {
  enveloppe 'printf "a\nb\n" | shell_grep -x b'
  assert_eq 0 "$rc" "la forme pipeline rend le résultat (messages : $err)"
  assert_eq "b" "$out" "la ligne trouvée"
  enveloppe 'printf "a\n" | shell_grep -x zzz; echo "rc=$?"'
  assert_contains "rc=1" "$out" "rien trouvé rend 1, pour un test dans une condition"
}

case_shell_grep_jamais_en_tete_de_pipeline() {
  # « shell_grep » promet d'arrêter le script sur une erreur de lecture. En tête d'un pipeline, son
  # « exit » ne quitte que son sous-shell : la promesse y serait fausse. La règle est vérifiée plutôt
  # qu'écrite en note (constat de la première revue de plage, 21/09/2026).
  #
  # Le motif cherche un tube précédé d'autre chose qu'un tube et suivi d'une commande, l'espace
  # étant facultative — « shell_grep x|wc » se cache sinon (constat de la revue de la PR n° 56).
  # Ni « || », ni un « | » d'alternative dans une expression régulière n'en sont.
  # La liste des scripts vient de find : le grep de BusyBox (runner de la forge) ne connaît pas --include.
  local trouves scripts=()
  mapfile -t scripts < <(find "$common" -name '*.sh' -not -path '*/.git/*' | LC_ALL=C sort)
  ((${#scripts[@]} > 0)) || { echo "aucun script trouvé : la règle ne vérifierait rien" >&2; exit 1; }
  shell_grep_into trouves -nHE 'shell_grep[[:space:]].*[^|]\|[[:space:]]*[a-z]' "${scripts[@]}"
  local restants="" ligne code
  while IFS= read -r ligne; do
    [[ -n $ligne ]] || continue
    # la bibliothèque et ce cas parlent de la règle ; un commentaire n'est pas un appel
    case $ligne in
      */lib/shell.sh:*|*test-shell-lib.sh:*) continue ;;
    esac
    code=${ligne#*:*:}
    [[ ${code#"${code%%[![:space:]]*}"} != \#* ]] || continue
    restants+="$ligne"$'\n'
  done <<< "$trouves"
  assert_eq "" "${restants%$'\n'}" "aucun « shell_grep … | commande » : dans un pipeline, lire d'abord dans une variable"
}

run_case "$@"
