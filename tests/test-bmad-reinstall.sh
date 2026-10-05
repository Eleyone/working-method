#!/usr/bin/env bash
# ci/bmad-reinstall.sh, le test de réinstallation de BMAD (story 1, AC 4 à 6), éprouvé hors ligne :
# la réinstallation réelle (bmad/update.sh, réseau) est remplacée par une commande d'essai, qui
# injecte une régénération fautive. ⛔ Un test qui ne peut pas échouer ne prouve rien (AC 6) : chaque
# couche projet a son cas, et le sous-module sali le sien.
# La réinstallation réelle tourne dans la CI (ci/checks-job.sh, étape « réinstallation BMAD »).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# $1 = corps de la réinstallation d'essai, lancé avec « $1 = sous-module, $2 = projet »
reinstalle() {
  printf '#!/usr/bin/env bash\nset -eu\n%s\n' "$1" > "$work/reinstall.sh"
  run bash "$common/ci/bmad-reinstall.sh" --reinstall "bash $work/reinstall.sh"
}

case_reinstallation_fidele_passe() {
  reinstalle 'true'
  assert_eq 0 "$rc" "une réinstallation qui ne change rien passe (messages : $err)"
  assert_contains "fichier(s) des couches projet intacts" "$out" "et le test dit ce qu'il a prouvé"
}

case_couche_projet_regeneree_echoue() {
  local fichier
  for fichier in workflow.config _bmad/config.user.toml _bmad/custom/config.toml \
    _bmad-output/implementation-artifacts/sprint-status.yaml; do
    reinstalle "printf '# régénéré\\n' >> \"\$2/$fichier\""
    assert_eq 1 "$rc" "une régénération de $fichier fait échouer le test (messages : $err)"
    assert_contains "$fichier" "$err" "le fichier régénéré est nommé"
  done
}

case_fichier_ajoute_dans_une_couche_projet_echoue() {
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  reinstalle 'printf "x = 1\n" > "$2/_bmad/custom/ajout.toml"'
  assert_eq 1 "$rc" "un fichier ajouté dans _bmad/custom/ fait échouer le test"
  assert_contains "_bmad/custom/ajout.toml" "$err" "le fichier ajouté est nommé"
}

case_methode_regeneree_autrement_echoue() {
  # Le défaut constaté le 04/10/2026 : l'installeur 6.12.0, réinstallé, change une valeur. Dans le
  # dépôt commun, il se voit comme un sous-module qui n'est plus propre.
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  reinstalle 'sed -i "s/intermediate/expert/" "$1/bmad/method/templates/config.toml"'
  assert_eq 1 "$rc" "une méthode régénérée autrement fait échouer le test"
  assert_contains "le sous-module n'est plus propre après la réinstallation" "$err" "le moment est nommé"
  assert_contains "bmad/method/templates/config.toml" "$err" "et le fichier"
}

case_sous_module_sali_echoue() {
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  reinstalle 'printf "x\n" > "$1/trace.txt"'
  assert_eq 1 "$rc" "un fichier écrit dans le sous-module fait échouer le test"
  assert_contains "trace.txt" "$err" "le fichier est nommé"
}

case_configuration_generee_editee_est_reecrite() {
  # Une régénération de la configuration GÉNÉRÉE du projet n'est pas une perte : bin/install, relancé,
  # la réécrit depuis workflow.config — et le dit. Le test passe, et la configuration est vérifiée.
  # shellcheck disable=SC2016 # script passé à un autre shell : ses « $ » s'y développent, pas ici
  reinstalle 'printf "# édité\n" >> "$2/_bmad/config.toml"; printf "x: 1\n" >> "$2/_bmad/bmm/config.yaml"'
  assert_eq 0 "$rc" "la configuration générée est réécrite par bin/install (messages : $err)"
}

case_reinstallation_impossible_rend_2() {
  reinstalle 'exit 2'
  assert_eq 2 "$rc" "une réinstallation en échec (réseau…) ne prouve rien : 2, jamais 0"
  assert_contains "rien n'est prouvé" "$err" "et le test le dit"
}

case_option_inconnue_rend_2() {
  run bash "$common/ci/bmad-reinstall.sh" --force
  assert_eq 2 "$rc" "option inconnue"
  run bash "$common/ci/bmad-reinstall.sh" --reinstall
  assert_eq 2 "$rc" "--reinstall sans commande"
}

run_case "$@"
