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

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/sprint.sh
. "$script_dir/lib/sprint.sh"

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

# section development_status : lecture commune de scripts/lib/sprint.sh
entries=$(sprint_entries <<< "$yaml") || die "lecture de $status_file impossible $where."
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
    # le fichier est lu d'abord : une lecture impossible arrête le script au lieu de passer pour « Status: absent »
    content=$(read_file "$path") || die "lecture de $path impossible $where : aucune conclusion sur la cohérence."
    header=$(grep -m 1 -iE '^[[:space:]]*status[[:space:]]*:' <<< "$content" || true)
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

# --- questions ouvertes des rétrospectives -------------------------------------------------------
# La section « open_questions » existe pour qu'une question ne se perde pas dans la prose d'un
# document. Une section que **rien ne lit** se perdrait exactement de la même façon : c'est le constat
# bloquant de la revue de la PR n° 107, et il est juste. Le contrôle la lit donc à chaque passage.
#
# Il ne la lit pas dans « sprint_plan.py » : ce script est installé par BMAD et une réinstallation
# l'écraserait. Le contrôle du projet, lui, tourne au verrou de fusion de chaque PR.
#
# « lands_in » vaut parfois « rien » — c'est une valeur **légitime**, l'aveu qu'aucune story ne
# ramènera la question. La rendre visible est tout l'objet de la section ; la refuser reviendrait à
# forcer une réponse fausse.
readonly question_keys="id epic question state lands_in"
questions=0
declare -A question_ids=()
question_id="" question_line=0
declare -A question_seen=()

close_question() { # vérifie l'entrée en cours, s'il y en a une
  local key
  flush_field   # la dernière valeur de l'entrée n'est close par rien d'autre
  [[ -n $question_id ]] || return 0
  for key in $question_keys; do
    [[ -n ${question_seen[$key]:-} ]] \
      || gap "question ouverte « $question_id » (ligne $question_line) : clé « $key » absente ou vide."
  done
  question_id="" question_line=0
  question_seen=()
}

in_questions=0 line_no=0
# Les motifs vivent dans des variables : une espace échappée juste avant « ]] » rend l'expression
# conditionnelle ambiguë pour bash, qui s'arrête sur « symbole « ; » inattendu » (constaté).
readonly q_entry_id='^  -[[:space:]]+id:[[:space:]]*(.*)$'
readonly q_entry_any='^  -[[:space:]]'
readonly q_field='^    ([a-z_]+):[[:space:]]*(.*)$'
# Une valeur longue est **repliée** sur des lignes de continuation plus indentées : c'est
# « sprint_status.py » qui l'écrit ainsi, et toutes les entrées réelles en portent. Ne lire que la
# première ligne physique marcherait par chance — jusqu'à une valeur dont la première ligne ne
# porterait rien d'utile (constat bloquant de la seconde revue de la PR n° 107). Les continuations
# sont donc recollées avant tout test.
readonly q_cont='^      [^ ]'
field_key="" field_value=""

# Le retrait des guillemets vit **ici et nulle part ailleurs**. Il a d'abord été écrit deux fois —
# une pour l'identifiant, une pour les autres valeurs — et les deux copies ne retiraient pas les
# mêmes caractères : l'identifiant gardait ses apostrophes (constat de la septième revue de la
# PR n° 107). Deux copies qui divergent, c'est le point 19 d'AGENTS.md sur son plus petit objet.
denuder() { # $1 = valeur brute ; affiche la valeur sans ses guillemets ni ses apostrophes
  local value=$1
  value=${value%\"} value=${value#\"}
  value=${value%\'} value=${value#\'}
  printf '%s' "$value"
}

flush_field() { # clôt la valeur en cours et la compte si elle porte quelque chose
  local value
  [[ -n $field_key ]] || return 0
  value=$(denuder "$field_value")
  # les blancs de recollement ne sont pas une valeur
  value=${value//[$' \t']/}
  [[ -z $value ]] || question_seen[$field_key]=1
  field_key="" field_value=""
}
while IFS= read -r line; do
  line_no=$((line_no + 1))
  line=${line%$'\r'}
  # une clé de premier niveau ferme la section courante
  # Le **nom** de la clé est capturé, jamais la ligne entière comparée : « open_questions: » suivi
  # d'une espace, d'une tabulation ou d'un commentaire n'est plus la même chaîne, et l'égalité
  # stricte faisait sauter toute la section **en silence** — le contrôle annonçait alors zéro
  # question et laissait tout passer (constat bloquant de la huitième revue de la PR n° 107).
  if [[ $line =~ ^([a-zA-Z_][a-zA-Z0-9_]*): ]]; then
    close_question
    if [[ ${BASH_REMATCH[1]} == open_questions ]]; then in_questions=1; else in_questions=0; fi
    continue
  fi
  ((in_questions == 1)) || continue
  if [[ $line =~ $q_entry_id ]]; then
    close_question
    question_id=${BASH_REMATCH[1]}
    question_id=$(denuder "$question_id")
    question_line=$line_no
    questions=$((questions + 1))
    # « id » est vu dès qu'il porte une valeur, y compris quand cette valeur est un doublon : sinon
    # la fermeture de l'entrée signalait en plus « clé « id » absente ou vide », ce qui est faux —
    # elle est présente, elle est seulement répétée. Deux écarts pour une faute, dont un mensonger
    # (constat de la quatrième revue de la PR n° 107).
    [[ -z $question_id ]] || question_seen[id]=1
    if [[ -z $question_id ]]; then
      gap "question ouverte ligne $line_no : « id » vide."
    elif [[ -n ${question_ids[$question_id]+x} ]]; then
      gap "question ouverte « $question_id » : identifiant répété (lignes ${question_ids[$question_id]} et $line_no)."
    else
      question_ids[$question_id]=$line_no
    fi
    continue
  fi
  # une entrée qui ne commence pas par « id » n'est pas lisible par ce contrôle : elle est signalée
  # plutôt que silencieusement ignorée, faute de quoi ses clés manquantes ne seraient jamais vues
  if [[ $line =~ $q_entry_any ]]; then
    close_question
    gap "question ouverte ligne $line_no : l'entrée doit commencer par « - id: »."
    continue
  fi
  if [[ $line =~ $q_field ]]; then
    flush_field
    [[ -n $question_id ]] || continue
    [[ " $question_keys " == *" ${BASH_REMATCH[1]} "* ]] || continue
    field_key=${BASH_REMATCH[1]} field_value=${BASH_REMATCH[2]}
    continue
  fi
  # ligne de continuation d'une valeur repliée
  if [[ -n $field_key && $line =~ $q_cont ]]; then
    field_value+=" ${line#"${line%%[![:space:]]*}"}"
    continue
  fi
  # Pas de traitement des lignes vides : une ligne vide au milieu d'une valeur repliée ne l'interrompt
  # déjà pas, puisque rien ici ne réinitialise « field_key » — seules la clé, l'entrée ou la section
  # suivantes le font, et elles sont traitées plus haut. La quatrième revue de la PR n° 107 annonçait
  # le contraire ; le cas de test écrit pour la garde est passé **sans** elle, ce qui l'a réfutée et
  # a évité d'ajouter une sixième garde qui ne garde rien (rétrospective de l'epic 5).
done <<< "$yaml"
close_question

if [[ -n $merge ]]; then
  rc=0
  merge_key=$(sprint_story_key "$merge" <<< "$yaml") || rc=$?
  if ((rc == 1)); then
    gap "story $merge absente du suivi : fusion refusée."
  elif ((rc != 0)); then
    gap "plusieurs stories correspondent à $merge dans le suivi : fusion refusée."
  elif [[ ${story_status[$merge_key]:-} != done ]]; then
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
printf '%s: cohérent %s (%d stories, %d epics, %d fichiers de story, %d question(s) ouverte(s))%s.\n' \
  "$script_name" "$where" "$stories" "$epics" "$files" "$questions" \
  "${merge:+ ; story $merge à done, fusion admise}"
