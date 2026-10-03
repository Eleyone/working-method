#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob
scripts=()
for candidate in "$root"/scripts/checks/*.sh; do
  [[ $(basename "$candidate") != lib.sh ]] || continue
  scripts+=("$candidate")
done
shopt -u nullglob

failed=()
anomaly=0
# Chaque contrôle tourne **sous le chargeur unique** (AD-9). Sans lui, aucun contrôle ne voit un
# « HUGO_LEGAL_* » : « scripts/env.sh » n'enveloppait que hugo, appelé par build.sh, et check.sh
# était lancé nu. C23, qui doit chercher dans la sortie la **valeur** de l'adresse de l'éditeur,
# aurait cherché une chaîne vide et ne se serait jamais déclenché — un garde-fou qui ne garde rien,
# dans la story dont c'est l'objet (constat de la revue de spec de la story 9.1).
#
# Le chargeur plutôt qu'une lecture propre à C23 : AD-9 veut « un seul chargeur », et une deuxième
# lecture de .env aurait été une deuxième vérité. Il n'exporte que les huit variables légales ; les
# jetons du même .env n'entrent jamais dans l'environnement d'un contrôle.
chargeur="$root/scripts/env.sh"
[[ -x $chargeur ]] \
  || { printf '%s: chargeur des valeurs légales absent ou non exécutable (%s) : les contrôles ne verraient aucun HUGO_LEGAL_* (AD-9).\n' \
       "$script_name" "${chargeur#"$root"/}" >&2; exit 2; }

for candidate in "${scripts[@]}"; do
  name=$(basename "$candidate" .sh)
  rc=0
  "$chargeur" bash "$candidate" || rc=$?
  case $rc in
    0) ;;
    1) failed+=("$name") ;;
    *) failed+=("$name (code $rc)"); anomaly=1 ;;
  esac
done

if ((${#scripts[@]} == 0)); then
  printf '%s: aucun script de contrôle dans scripts/checks/ ; builds seuls, niveau %s.\n' "$script_name" "$level"
  exit 0
fi

if ((${#failed[@]})); then
  printf '%s: %s contrôle(s) en échec sur %s : %s\n' \
    "$script_name" "${#failed[@]}" "${#scripts[@]}" "${failed[*]}" >&2
  ((anomaly == 0)) || exit 2
  exit 1
fi

printf '%s: %s contrôle(s) passés, niveau %s.\n' "$script_name" "${#scripts[@]}" "$level"
