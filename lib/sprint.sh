# shellcheck shell=bash
# Lecture du suivi de sprint (le fichier que désigne sprint.status-file dans workflow.config), en bash
# et awk seuls, sans jq ni outil YAML : sprint-consistency.sh tourne aussi en CI.
#
# À charger par « . lib/sprint.sh ». Le texte du suivi est lu sur l'entrée standard.
# Les fonctions ne comptent pas sur set -e : un appel suivi de || le suspend pour toute la fonction,
# donc chaque étape vérifie son résultat. En cas d'erreur, rien n'est écrit sur la sortie standard.
#
#   sprint_entries                      « clé<TAB>valeur » pour chaque ligne de development_status
#   sprint_block <nom>                  idem pour la section <nom> (development_status, aliases) : 0
#   sprint_story_key <n.m>              clé de la story n.m : 0 trouvée, 1 absente, 2 plusieurs clés ou numéro illisible
#   sprint_story_status <clé>           statut de la story : 0 trouvé, 1 absente, 2 illisible ou clé en double
#   story_number_from_branch <branche>  numéro n.m tiré du nom de branche : 0 trouvé, 1 aucun numéro
#   sprint_convention_served <convention>   0 numbered ou keyed, servies ici ; 1 none, suivi désactivé ;
#                                       2 convention inconnue (raison écrite)
#
# Convention « keyed » (calculette#outillage-5) — clés kebab-case libres, epics « epic-<nom> », bloc
# « aliases: » qui rattache un nom de fichier de story à sa clé :
#   sprint_keyed_resolve <nom> <entrées> <alias>   clé d'un fichier de story (nom sans « .md ») : 0 trouvée,
#                                       1 ni clé ni alias, 2 clé directe ET alias (ambigu)
#   sprint_keyed_header_status          statut de l'en-tête d'un fichier de story lu sur l'entrée standard :
#                                       0 trouvé, 1 aucun en-tête lisible
#   sprint_is_non_story <nom> <motifs|none>   0 le fichier n'est pas une story (sprint.non-story-files), 1 sinon
#   sprint_keyed_story_from_branch <branche>  « clé<TAB>nom du fichier » de la story de la branche : 0 trouvée,
#                                       1 aucune, 2 ambiguë ou suivi illisible
#
# Les fonctions sans « keyed » dans leur nom servent la convention « numbered » (clés « n-m-titre »,
# epics « epic-n ») ; sprint_entries et sprint_block servent les deux. C'est sprint.convention qui dit
# laquelle un projet suit.
#
# Procédures : procedures/sprint-consistency.md, procedures/shell-scripts.md

# Une section de premier niveau : lignes « clé: valeur » indentées, quelle que soit l'indentation. La valeur
# perd un commentaire « # … » précédé d'une espace, ses guillemets, ses espaces et son retour chariot de fin.
sprint_entries() {
  sprint_block development_status
}

sprint_block() { # $1 nom de la section ; texte du suivi sur l'entrée standard
  [[ ${1:-} =~ ^[a-z_]+$ ]] || return 2
  awk -v section="$1" '
    $0 ~ ("^" section ":[[:space:]]*$") { inside = 1; next }
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

# Une convention que l'outillage ne sait pas servir sort en 2 en nommant la story qui l'apportera :
# jamais un repli silencieux sur la lecture « numbered », qui conclurait sur des clés qu'elle ignore.
sprint_convention_served() { # $1 valeur de sprint.convention
  case ${1:-} in
    numbered|keyed) return 0 ;;
    none) return 1 ;;
    *) echo "sprint.convention = « ${1:-} » : convention inconnue."; return 2 ;;
  esac
}

# --- convention keyed ----------------------------------------------------------------------------
# Les règles sont reprises sans changement du contrôle d'origine (calculette#outillage-5) :
# le suivi fait foi, un alias est un rattachement décidé à la main, et un nom qui serait à la fois une clé
# et un alias est une contradiction que le contrôle ne tranche pas.

# $2 et $3 : « clé<TAB>valeur » de development_status et du bloc aliases, tels que sprint_block les écrit.
sprint_keyed_resolve() { # $1 nom du fichier sans « .md », $2 entrées du suivi, $3 alias
  local name=${1:-} key value direct="" target=""
  [[ -n $name ]] || return 1
  while IFS=$'\t' read -r key value; do
    [[ -n $key && $key == "$name" ]] || continue
    direct=1
    break
  done <<< "${2:-}"
  while IFS=$'\t' read -r key value; do
    [[ -n $key && $key == "$name" ]] || continue
    target=$value
    break
  done <<< "${3:-}"
  if [[ -n $direct && -n $target ]]; then return 2; fi
  if [[ -n $direct ]]; then printf '%s\n' "$name"; return 0; fi
  if [[ -n $target ]]; then printf '%s\n' "$target"; return 0; fi
  return 1
}

# La première ligne d'en-tête lisible : « Status: x », « status: 'x' », « **Status**: x », un commentaire de
# fin de ligne admis. Une ligne « Status: » dont la valeur ne se lit pas est passée, comme dans le contrôle
# d'origine (sed … | head -1) : c'est la suivante qui compte.
sprint_keyed_header_status() {
  local line
  local -r header_re='^\*{0,2}[Ss]tatus\*{0,2}[[:space:]]*:[[:space:]]*['"'"'"]?([a-z-]+)'
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ $header_re ]] || continue
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  done
  return 1
}

sprint_is_non_story() { # $1 nom du fichier sans « .md », $2 motifs de sprint.non-story-files, ou none
  local pattern
  local -a patterns=()
  [[ ${2:-} != none ]] || return 1
  # découpage par read, jamais par « for p in $2 » : un motif ne doit pas s'étendre aux fichiers du
  # dossier courant avant d'être comparé (un « spec-* » deviendrait « spec-autre »)
  read -r -a patterns <<< "${2:-}"
  for pattern in ${patterns[@]+"${patterns[@]}"}; do
    # shellcheck disable=SC2053 # le motif est un joker de nom de fichier, comparé sans citation exprès
    [[ ${1:-} == $pattern ]] && return 0
  done
  return 1
}

# Le nom de la branche, préfixe ôté (« fix/plafond » → « plafond ») ou recollé (→ « fix-plafond ») : les
# deux formes servent dans les projets keyed. Chacune est résolue comme un nom de fichier de story ; une
# seule doit aboutir. Une branche sans story (Renovate, documentation) n'en a aucune : le contrôle global
# s'applique.
sprint_keyed_story_from_branch() { # $1 nom de branche ; texte du suivi sur l'entrée standard
  local yaml entries aliases candidate key rc found=""
  [[ ${1:-} =~ ^([a-z]+)/([a-z0-9]+(-[a-z0-9]+)*)$ ]] || return 1
  local -r prefix=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]}
  yaml=$(cat) || return 2
  entries=$(sprint_entries <<< "$yaml") || return 2
  aliases=$(sprint_block aliases <<< "$yaml") || return 2
  for candidate in "$prefix-$rest" "$rest"; do
    rc=0
    key=$(sprint_keyed_resolve "$candidate" "$entries" "$aliases") || rc=$?
    ((rc != 2)) || return 2
    ((rc == 0)) || continue
    # une branche ne désigne qu'une story : une clé d'epic ou de rétrospective n'en est pas une, et la
    # branche passe alors par le contrôle global, comme une branche sans numéro en numbered
    [[ $key != epic-* && $key != *-retrospective ]] || continue
    [[ -z $found ]] || return 2
    found="$key"$'\t'"$candidate"
  done
  [[ -n $found ]] || return 1
  printf '%s\n' "$found"
}
