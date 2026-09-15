# Lecture du suivi de sprint (_bmad-output/implementation-artifacts/sprint-status.yaml), en bash et awk seuls,
# sans jq ni outil YAML : sprint-consistency.sh tourne aussi en CI.
#
# À charger par « . scripts/lib/sprint.sh ». Le texte du suivi est lu sur l'entrée standard.
# Les fonctions ne comptent pas sur set -e : un appel suivi de || le suspend pour toute la fonction,
# donc chaque étape vérifie son résultat. En cas d'erreur, rien n'est écrit sur la sortie standard.
#
#   sprint_entries                      « clé<TAB>valeur » pour chaque ligne de development_status
#   sprint_story_key <n.m>              clé de la story n.m : 0 trouvée, 1 absente, 2 plusieurs clés ou numéro illisible
#   sprint_story_status <clé>           statut de la story : 0 trouvé, 1 absente, 2 illisible ou clé en double
#   story_number_from_branch <branche>  numéro n.m tiré du nom de branche : 0 trouvé, 1 aucun numéro
#
# Procédures : docs/procedures/sprint-consistency.md, docs/procedures/shell-scripts.md

# Section development_status : lignes « clé: valeur » indentées, quelle que soit l'indentation. La valeur perd
# un commentaire « # … » précédé d'une espace, ses guillemets, ses espaces et son retour chariot de fin.
sprint_entries() {
  awk '
    /^development_status:[[:space:]]*$/ { inside = 1; next }
    inside && /^[^[:space:]#]/ { exit }
    inside && /^[[:space:]]+[^[:space:]#][^:]*:/ {
      line = $0; sub(/^[[:space:]]+/, "", line)
      key = line; sub(/:.*$/, "", key)
      value = line; sub(/^[^:]*:[[:space:]]*/, "", value); sub(/[[:space:]]+#.*$/, "", value)
      gsub(/["\047]/, "", value); sub(/[[:space:]]+$/, "", value)
      print key "\t" value
    }
  '
}

sprint_story_key() { # $1 numéro n.m ; texte du suivi sur l'entrée standard
  local entries prefix key value found="" count=0
  [[ ${1:-} =~ ^[0-9]+\.[0-9]+[a-z]?$ ]] || return 2
  entries=$(sprint_entries) || return 2
  prefix="${1//./-}-"
  while IFS=$'\t' read -r key value; do
    [[ $key == "$prefix"* && $key =~ ^[0-9]+-[0-9]+[a-z]?-[a-z0-9-]+$ ]] || continue
    found=$key
    count=$((count + 1))
  done <<< "$entries"
  ((count > 0)) || return 1
  ((count == 1)) || return 2
  printf '%s\n' "$found"
}

# Un statut simple tient sur la ligne de sa clé : une valeur vide ou un bloc YAML (« | », « > ») est illisible.
sprint_story_status() { # $1 clé de story ; texte du suivi sur l'entrée standard
  local entries key value status="" count=0
  entries=$(sprint_entries) || return 2
  while IFS=$'\t' read -r key value; do
    [[ -n $key && $key == "${1:-}" ]] || continue
    status=$value
    count=$((count + 1))
  done <<< "$entries"
  ((count > 0)) || return 1
  ((count == 1)) || return 2
  [[ $status =~ ^[a-z][a-z-]*$ ]] || return 2
  printf '%s\n' "$status"
}

story_number_from_branch() { # $1 nom de branche : chore/0-7-verify-and-merge-pr-skill → 0.7
  [[ ${1:-} =~ ^[a-z]+/([0-9]+)-([0-9]+[a-z]?)- ]] || return 1
  printf '%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}
