#!/usr/bin/env bash
# Convention de citation d'un projet dans ce dépôt public (procedures/secrets.md, § « Citer un
# projet ») : une origine s'écrit `<alias>#<clé>`, avec un alias déclaré dans la table de la
# procédure, et plus jamais « projet consommateur » dans le tableau des pièges. Ce fichier vérifie
# l'arbre réel, puis prouve que la vérification refuse chaque écart. Que l'alias passe le contrôle
# « aucun nom de projet », la CI le prouve : ci/check-names.sh y lit l'arbre avec la vraie liste.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# $1 procédure qui déclare les alias, $2 procédure dont le tableau des pièges est vérifié.
# 0 conforme ; 1 écart (nommé sur la sortie d'erreur) ; 2 fichier illisible, table d'alias ou tableau
# des pièges introuvable.
origines_conformes() {
  local declared=$1 table=$2 aliases cells cell rest token alias cited findings=0
  [[ -r $declared && -r $table ]] || { echo "procédure illisible" >&2; return 2; }
  # les alias : première colonne de la table qui suit le titre « Citer un projet », jusqu'au titre suivant
  aliases=$(awk '/^#+ Citer un projet/ { on = 1; next } on && /^#/ { on = 0 }
    on && /^\| `[a-z0-9-]+` \|/ { split($0, c, "`"); print c[2] }' "$declared") \
    || { echo "table des alias illisible" >&2; return 2; }
  [[ -n $aliases ]] || { echo "aucun alias déclaré" >&2; return 2; }
  # la colonne « Trouvé à » (quatrième) de chaque ligne du tableau, hors en-tête ; le séparateur « |---| »
  # ne commence pas par « | », et « \| » est un caractère de la cellule, pas un séparateur
  cells=$(awk '/^## Pièges connus/ { on = 1; next } on && /^## / { on = 0 }
    on && /^\| / { gsub(/\\\|/, "\001"); split($0, c, "|"); n++; if (n > 1) print c[5] }' "$table") \
    || { echo "tableau des pièges illisible" >&2; return 2; }
  [[ -n $cells ]] || { echo "tableau des pièges introuvable" >&2; return 2; }
  while IFS= read -r cell; do
    cell=${cell# }
    if [[ $cell == *"projet consommateur"* ]]; then
      echo "« projet consommateur » : citer <alias>#<clé> — $cell" >&2
      findings=1
      continue
    fi
    cited="" rest=$cell
    while [[ $rest =~ \`([a-z][a-z0-9-]*)#[a-z0-9][a-z0-9.-]*\` ]]; do
      token=${BASH_REMATCH[0]}
      alias=${BASH_REMATCH[1]}
      cited=1
      grep -qxF -- "$alias" <<< "$aliases" || { echo "alias non déclaré : $alias" >&2; findings=1; }
      rest=${rest#*"$token"}
    done
    [[ -n $cited || $cell =~ ^(story|stories|rétrospective)\  ]] \
      || { echo "origine sans <alias>#<clé> ni story du projet source : $cell" >&2; findings=1; }
  done <<< "$cells"
  return "$findings"
}

case_origines_du_tableau_reel_conformes() {
  run origines_conformes "$common/procedures/secrets.md" "$common/procedures/shell-scripts.md"
  assert_eq 0 "$rc" "le tableau des pièges cite ses origines par un alias déclaré ($err)"
}

# un tableau d'essai : la section, l'en-tête, le séparateur, puis les lignes données
tableau() { printf '## Pièges connus\n\n| Piège | Effet | Parade | Trouvé à | Test |\n|---|---|---|---|---|\n' > "$work/table.md"
  printf '%s\n' "$@" >> "$work/table.md"; }

case_origines_refuse_projet_consommateur() {
  cp "$common/procedures/secrets.md" "$work/secrets.md"
  tableau '| piège | effet | parade | projet consommateur, 09/09/2026 | aucun |'
  run origines_conformes "$work/secrets.md" "$work/table.md"
  assert_eq 1 "$rc" "l'ancienne forme est refusée"
  assert_contains "projet consommateur" "$err" "le refus la nomme"
}

case_origines_refuse_un_alias_non_declare() {
  cp "$common/procedures/secrets.md" "$work/secrets.md"
  # shellcheck disable=SC2016 # accents graves du Markdown, pas une substitution de commande
  tableau '| piège | effet | parade | `inconnu#fix-x` (01/10/2026) | aucun |'
  run origines_conformes "$work/secrets.md" "$work/table.md"
  assert_eq 1 "$rc" "un alias absent de la table est refusé"
  assert_contains "alias non déclaré : inconnu" "$err" "le refus nomme l'alias"
}

case_origines_refuse_un_alias_sans_cle() {
  cp "$common/procedures/secrets.md" "$work/secrets.md"
  # shellcheck disable=SC2016 # accents graves du Markdown, pas une substitution de commande
  tableau '| piège | effet | parade | inconnu, 10/10/2026 | aucun |' '| piège | effet | parade | `calculette`, 10/10/2026 | aucun |'
  run origines_conformes "$work/secrets.md" "$work/table.md"
  assert_eq 1 "$rc" "une origine sans clé est refusée, alias déclaré ou non"
  assert_contains "ni story du projet source : inconnu, 10/10/2026" "$err" "le refus nomme la première"
  assert_contains "ni story du projet source : \`calculette\`, 10/10/2026" "$err" "et la seconde"
}

case_origines_accepte_les_formes_admises() {
  cp "$common/procedures/secrets.md" "$work/secrets.md"
  # shellcheck disable=SC2016 # accents graves du Markdown, pas une substitution de commande
  tableau '| piège | effet \| suite | parade | story 0.7 | aucun |' \
    '| piège | effet | parade | rétrospective de l'"'"'epic 2 (F1) ; `calculette#outillage-3` (constat du 09/09/2026) | aucun |'
  run origines_conformes "$work/secrets.md" "$work/table.md"
  assert_eq 0 "$rc" "story du projet source et alias déclaré passent ($err)"
}

case_origines_procedure_illisible_rend_2() {
  run origines_conformes "$work/absente.md" "$common/procedures/shell-scripts.md"
  assert_eq 2 "$rc" "une procédure absente n'est pas « conforme »"
  assert_contains "procédure illisible" "$err" "le refus le dit"
}

case_origines_sans_tableau_rend_2() {
  cp "$common/procedures/secrets.md" "$work/secrets.md"
  printf '# rien\n' > "$work/table.md"
  run origines_conformes "$work/secrets.md" "$work/table.md"
  assert_eq 2 "$rc" "sans tableau des pièges, rien n'est vérifié"
  assert_contains "tableau des pièges introuvable" "$err" "le refus le dit"
}

case_origines_sans_table_d_alias_rend_2() {
  printf '# rien\n' > "$work/secrets.md"
  tableau '| piège | effet | parade | story 0.7 | aucun |'
  run origines_conformes "$work/secrets.md" "$work/table.md"
  assert_eq 2 "$rc" "sans table d'alias, rien n'est vérifiable"
  assert_contains "aucun alias déclaré" "$err" "le refus le dit"
}

run_case "$@"
