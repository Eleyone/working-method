#!/usr/bin/env bash
# Vérifie que le suivi de sprint et les fichiers de story disent la même chose.
#
#   sprint-consistency.sh                               contrôle global de l'arbre de travail
#   sprint-consistency.sh --merge <n.m>                 en plus, la story n.m est à done des deux côtés
#   sprint-consistency.sh [--merge <n.m>] --rev <commit>   lit le suivi et les fichiers dans ce commit
#
# Code de sortie : 0 cohérent ; 1 au moins un écart ; 2 contrôle impossible (usage, suivi absent ou vide,
# commit introuvable, liste des fichiers de story illisible).
# Statuts seulement en v1, pas les branches (D-17). Bash seul, sans Python, outil YAML ni option GNU.
# Procédure : docs/procedures/sprint-consistency.md
set -euo pipefail

readonly script_name=sprint-consistency
readonly stories_dir="_bmad-output/implementation-artifacts"
readonly status_file="$stories_dir/sprint-status.yaml"
readonly story_statuses=" backlog ready-for-dev in-progress review done "
readonly epic_statuses=" backlog in-progress done "
readonly usage="usage : sprint-consistency.sh [--merge <n.m>] [--rev <commit>]"

die() { printf '%s: %b\n' "$script_name" "$*" >&2; exit 2; }

merge="" rev=""
while (($#)); do
  case $1 in
    --merge) (($# >= 2)) && [[ -z $merge ]] || die "$usage"; merge=$2; shift 2 ;;
    --rev) (($# >= 2)) && [[ -z $rev ]] || die "$usage"; rev=$2; shift 2 ;;
    *) die "$usage" ;;
  esac
done
[[ -z $merge || $merge =~ ^[0-9]+\.[0-9]+[a-z]?$ ]] || die "numéro de story attendu après --merge, par exemple 0.6."

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "à lancer dans le dépôt."
cd "$root"

# --- lecture : arbre de travail, ou commit donné par --rev -------------------------------------
if [[ -n $rev ]]; then
  commit=$(git rev-parse --verify --quiet "$rev^{commit}") || die "commit introuvable : $rev."
  where="dans le commit ${commit:0:7}"
  file_exists() { [[ $(git cat-file -t "$commit:$1" 2>/dev/null) == blob ]]; } # un dossier n'est pas un fichier
  read_file() { git show "$commit:$1" 2>/dev/null; }
  list_names() { # fichiers seulement (blob), comme [[ -f ]] dans l'arbre de travail
    git ls-tree "$commit" -- "$stories_dir/" 2>/dev/null | awk -F '\t' '$1 ~ / blob / { print $2 }' | sed 's#.*/##'
  }
else
  where="dans l'arbre de travail"
  file_exists() { [[ -f $1 ]]; }
  read_file() { cat -- "$1" 2>/dev/null; }
  list_names() { # joker du shell : aucun outil externe ; un dossier illisible est une erreur, pas une liste vide
    local f
    [[ -d $stories_dir && -r $stories_dir && -x $stories_dir ]] || return 1
    for f in "$stories_dir"/*.md; do
      [[ -f $f ]] && printf '%s\n' "${f##*/}"
    done
    return 0
  }
fi

file_exists "$status_file" || die "$status_file absent $where : aucune conclusion sur la cohérence."
yaml=$(read_file "$status_file") || die "lecture de $status_file impossible $where."

# section development_status : lignes « clé: valeur » indentées, quelle que soit l'indentation
entries=$(awk '
  /^development_status:[[:space:]]*$/ { inside = 1; next }
  inside && /^[^[:space:]#]/ { exit }
  inside && /^[[:space:]]+[^[:space:]#][^:]*:/ {
    line = $0; sub(/^[[:space:]]+/, "", line)
    key = line; sub(/:.*$/, "", key)
    value = line; sub(/^[^:]*:[[:space:]]*/, "", value); sub(/[[:space:]]+#.*$/, "", value)
    gsub(/["\047]/, "", value); sub(/[[:space:]]+$/, "", value)
    print key "\t" value
  }
' <<< "$yaml")
[[ -n $entries ]] || die "section development_status vide ou absente de $status_file $where : aucune conclusion sur la cohérence."

# --- contrôles ---------------------------------------------------------------------------------
gaps=()
gap() { gaps+=("$1"); }

declare -A story_status epic_status epic_total epic_waiting epic_done
stories=0 epics=0 files=0
while IFS=$'\t' read -r key value; do
  if [[ $key =~ ^epic-([0-9]+)$ ]]; then
    epics=$((epics + 1))
    epic_status[${BASH_REMATCH[1]}]=$value
    [[ $epic_statuses == *" $value "* ]] || gap "epic $key : statut « $value » hors vocabulaire (backlog, in-progress, done)."
  elif [[ $key =~ ^epic-[0-9]+-retrospective$ ]]; then
    : # rétrospectives non vérifiées
  elif [[ $key =~ ^([0-9]+)-[0-9]+[a-z]?-[a-z0-9-]+$ ]]; then
    stories=$((stories + 1))
    number=${BASH_REMATCH[1]}
    story_status[$key]=$value
    epic_total[$number]=$(( ${epic_total[$number]:-0} + 1 ))
    case $value in
      backlog|ready-for-dev) epic_waiting[$number]=$(( ${epic_waiting[$number]:-0} + 1 )) ;;
      done) epic_done[$number]=$(( ${epic_done[$number]:-0} + 1 )) ;;
    esac
    if [[ $story_statuses != *" $value "* ]]; then
      gap "story $key : statut « $value » hors vocabulaire dans le suivi."
      continue
    fi
    path="$stories_dir/$key.md"
    if ! file_exists "$path"; then
      [[ $value == backlog ]] || gap "story $key à $value sans fichier de story ($path)."
      continue
    fi
    files=$((files + 1))
    # seule la première ligne « status: » compte, quelle que soit sa casse, pour détecter une ligne mal écrite
    header=$(read_file "$path" | grep -m 1 -iE '^[[:space:]]*status[[:space:]]*:' || true)
    header=${header%$'\r'}
    if [[ -z $header ]]; then
      gap "story $key : ligne « Status: » absente de $path."
    elif [[ ! $header =~ ^Status:\ ([a-z-]+)$ ]]; then
      gap "story $key : ligne « Status: » mal écrite dans $path (« $header »)."
    elif [[ $story_statuses != *" ${BASH_REMATCH[1]} "* ]]; then
      gap "story $key : statut « ${BASH_REMATCH[1]} » hors vocabulaire dans $path."
    elif [[ ${BASH_REMATCH[1]} != "$value" ]]; then
      gap "story $key : ${BASH_REMATCH[1]} dans le fichier de story, $value dans le suivi."
    fi
  else
    gap "clé « $key » non reconnue dans development_status."
  fi
done <<< "$entries"

# fichiers de story sans entrée dans le suivi ; la liste est lue d'abord, pour qu'un échec arrête le script
names=$(list_names) || die "lecture de la liste des fichiers de story impossible $where : aucune conclusion sur la cohérence."
while IFS= read -r name; do
  [[ -n $name ]] || continue
  key=${name%.md}
  [[ $key =~ ^[0-9]+-[0-9]+[a-z]?-[a-z0-9-]+$ ]] || continue
  [[ -n ${story_status[$key]+x} ]] || gap "fichier de story $stories_dir/$name sans entrée dans le suivi."
done <<< "$names"

# statut de chaque epic d'après ses stories
for number in "${!epic_status[@]}"; do
  total=${epic_total[$number]:-0}
  if ((total == 0)); then
    gap "epic-$number sans story dans le suivi."
    continue
  fi
  # un statut hors vocabulaire est déjà signalé : pas de second écart pour la même cause
  [[ $epic_statuses == *" ${epic_status[$number]} "* ]] || continue
  if (( ${epic_waiting[$number]:-0} == total )); then
    expected=backlog
  elif (( ${epic_done[$number]:-0} == total )); then
    expected=done
  else
    expected=in-progress
  fi
  [[ ${epic_status[$number]} == "$expected" ]] \
    || gap "epic-$number à ${epic_status[$number]} alors que ses stories le placent à $expected."
done

# stories dont l'epic n'a pas de ligne dans le suivi
for number in "${!epic_total[@]}"; do
  [[ -n ${epic_status[$number]+x} ]] || gap "stories de l'epic $number sans ligne epic-$number dans le suivi."
done

if [[ -n $merge ]]; then
  prefix="${merge//./-}-"
  merge_keys=()
  for key in "${!story_status[@]}"; do
    if [[ $key == "$prefix"* ]]; then merge_keys+=("$key"); fi
  done
  merge_key=${merge_keys[0]:-}
  if ((${#merge_keys[@]} == 0)); then
    gap "story $merge absente du suivi : fusion refusée."
  elif ((${#merge_keys[@]} > 1)); then
    gap "plusieurs stories correspondent à $merge dans le suivi (${merge_keys[*]}) : fusion refusée."
  elif [[ ${story_status[$merge_key]} != done ]]; then
    gap "story $merge_key à ${story_status[$merge_key]} dans le suivi : fusion refusée tant qu'elle n'est pas à done."
  elif ! file_exists "$stories_dir/$merge_key.md"; then
    gap "story $merge_key sans fichier de story : fusion refusée."
  fi
fi

# --- résultat ----------------------------------------------------------------------------------
if ((${#gaps[@]})); then
  printf '%s: %d écart(s) %s :\n' "$script_name" "${#gaps[@]}" "$where"
  printf '  - %s\n' "${gaps[@]}" | sort
  exit 1
fi
printf '%s: cohérent %s (%d stories, %d epics, %d fichiers de story)%s.\n' "$script_name" "$where" \
  "$stories" "$epics" "$files" "${merge:+ ; story $merge à done, fusion admise}"
