# shellcheck shell=bash
# Lecteur de workflow.config, le fichier qui déclare ce qui est propre à un projet consommateur.
#
# À charger par « . lib/config.sh ». Dépendances : bash 4.3 ou plus, git.
#
#   config_load <fichier>            lit et valide le fichier ENTIER : 0 valide ; 2 sinon, avec une ligne
#                                    par problème sur la sortie d'erreur (champ et raison). Rien n'est
#                                    gardé d'un fichier refusé.
#   config_get <variable> <champ>    copie la valeur validée du champ dans la variable : 0 ; 2 si le champ
#                                    n'est pas au schéma ou si aucun fichier n'a été chargé
#   config_enabled <champ>           0 si le champ porte une valeur, 1 s'il vaut « none » (désactivé)
#   config_fields                    les champs du schéma, un par ligne, triés
#   config_project_root <variable>   racine du projet consommateur, vue du dossier courant : 0 ; 2 hors
#                                    d'un dépôt git
#
# Le format est celui de git config, lu par « git config -f <fichier> --no-includes --null --list ».
# Aucun lecteur n'est écrit : git est déjà un prérequis de tout l'outillage, sa syntaxe est vérifiée
# par git, et aucune valeur n'est interprétée par le shell (ni source, ni eval).
#
# ⛔ Aucune valeur par défaut. Un champ absent, inconnu, en double, vide ou mal typé fait refuser le
# fichier entier. « none » est une valeur, pas une absence : sur un champ désactivable, il désactive la
# fonction, et l'outil qui la porte le dit dans sa sortie. Sur un autre champ, c'est une erreur de type.
#
# Les comportements de git config sur lesquels reposent ces règles ont été constatés (git 2.53.0,
# 03/10/2026), pas supposés ; chacun a son cas de test dans tests/test-config.sh :
#   - erreur de syntaxe : code 128, mais une sortie partielle est écrite → la sortie n'est jamais lue
#     si le code n'est pas 0 ;
#   - clé en double : « --get » rend la dernière, en silence → toutes les valeurs sont lues et comptées ;
#   - « [include] path = … » : avec --no-includes, non suivi mais listé → section inconnue, refusée ;
#   - GIT_CONFIG_COUNT, GIT_CONFIG_PARAMETERS : sans effet avec -f → rien à faire, mais sous test ;
#   - une clé sans « = » vaut « vrai », « cle = » vaut une chaîne vide → toutes deux refusées ;
#   - noms de section et de clé insensibles à la casse (git les rend en minuscules), « _ » interdit
#     dans un nom ; valeurs sensibles à la casse ;
#   - « \. » hors guillemets est une erreur de syntaxe : une expression régulière s'écrit sans
#     antislash ([.]md$), et toute valeur qui contient « # », « ; » ou « \ » se met entre guillemets.
#
# Procédure : procedures/workflow-config.md

# Le schéma : champ → type. Un « ? » en tête du type marque un champ désactivable par « none ».
# Deux schémas sont lus (procedures/workflow-config.md, « Changer de schéma ») : le 2 ajoute les trois
# champs de config_since_schema, que la configuration BMAD générée par bin/install demande (story 1).
declare -gA config_schema=(
  [workflow.schema]=schema
  [forge.repo]=repo
  [forge.base]=branch
  [forge.release-branch]=?branch
  [forge.branch-prefixes]=words
  [forge.env-file]=path
  [sprint.convention]=?convention
  [sprint.status-file]=?path
  [sprint.stories-dir]=?path
  [sprint.spec-source]=?path
  [review.exempt-paths]=?regex
  [review.report]=report
  [review.reviewer-for-claude]=model
  [review.reviewer-for-gemini]=model
  [review.timeout]=integer
  [review.project-layer]=path
  [review.private-paths]=paths
  [review.range-exclude]=?paths
  [guard.command]=?path
  [guard.patterns-file]=?path
  [ci.workflow]=?path
  [ci.status-context]=?text
  [ci.bootstrap]=boolean
  [checks.command]=?text
  [checks.dir]=?path
  [tests.protected-outputs]=?paths
  [bmad.version]=semver
  [bmad.modules]=words
  [bmad.project-name]=label
  [bmad.document-output-language]=label
  [bmad.output-folder]=path
  [agents.skill-dirs]=paths
)
# Le schéma à partir duquel un champ existe ; un champ absent de cette table existe depuis le schéma 1.
declare -gA config_since_schema=(
  [bmad.project-name]=2
  [bmad.document-output-language]=2
  [bmad.output-folder]=2
)
declare -gA config_values=()
config_loaded=""
# Racine du dépôt commun, relevée au chargement : un « cd » ultérieur ne la déplace pas.
config_common_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

config_fields() {
  printf '%s\n' "${!config_schema[@]}" | LC_ALL=C sort
}

# $1 = valeur, $2 = type sans « ? » ; rend 0 si la valeur a ce type, 1 sinon, et écrit la raison
config_check_type() {
  local value=$1 type=$2 word
  case $type in
    schema) [[ $value == 1 || $value == 2 ]] || { echo "schéma « $value » inconnu de cet outillage (schémas connus : 1, 2)"; return 1; } ;;
    repo) [[ $value =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "« propriétaire/nom » attendu"; return 1; } ;;
    branch)
      { [[ $value =~ ^[A-Za-z0-9._/-]+$ && $value != -* ]] \
        && git check-ref-format --branch "$value" >/dev/null 2>&1; } \
        || { echo "nom de branche invalide"; return 1; }
      ;;
    words)
      [[ $value =~ ^[a-z0-9][a-z0-9.-]*( [a-z0-9][a-z0-9.-]*)*$ ]] \
        || { echo "liste de mots attendue (minuscules, chiffres, « . », « - »), séparés par une espace"; return 1; }
      config_check_unique "$value" || return 1
      ;;
    path) config_check_path "$value" || return 1 ;;
    paths)
      [[ $value =~ ^[^[:space:]]+( [^[:space:]]+)*$ ]] \
        || { echo "liste de chemins attendue, séparés par une espace"; return 1; }
      for word in $value; do
        config_check_path "$word" || return 1
      done
      config_check_unique "$value" || return 1
      ;;
    convention)
      case $value in
        numbered|keyed) ;;
        *) echo "« numbered » ou « keyed » attendu (ou « none »)"; return 1 ;;
      esac
      ;;
    report)
      case $value in
        pr-comment|file) ;;
        *) echo "« pr-comment » ou « file » attendu"; return 1 ;;
      esac
      ;;
    model) [[ $value =~ ^[a-z0-9][a-z0-9.-]*$ ]] || { echo "nom de modèle attendu (minuscules, chiffres, « . », « - »)"; return 1; } ;;
    integer) [[ $value =~ ^[1-9][0-9]{0,5}$ ]] || { echo "entier positif attendu"; return 1; } ;;
    boolean)
      # « true » ou « false » seulement : git accepte aussi yes, on, 1…, que ce lecteur ne lit pas
      [[ $value == true || $value == false ]] || { echo "« true » ou « false » attendu"; return 1; }
      ;;
    semver) [[ $value =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version X.Y.Z attendue"; return 1; } ;;
    regex)
      # bash, pas grep : le grep de BusyBox (runner de la forge) rend 1 — « aucune correspondance » —
      # sur une expression invalide, là où GNU grep rend 2. « [[ =~ ]] » rend 2 sur les deux libc.
      local regex_code=0
      # shellcheck disable=SC2319 # le code voulu est celui du test [[ =~ ]] : 2 dit une expression invalide
      [[ x =~ $value ]] 2>/dev/null || regex_code=$?
      ((regex_code <= 1)) || { echo "expression régulière étendue invalide"; return 1; }
      ;;
    text)
      [[ $value =~ ^[^[:space:]](.*[^[:space:]])?$ ]] \
        || { echo "texte sans espace en tête ni en fin attendu"; return 1; }
      ;;
    label)
      # Un libellé recopié tel quel, sans citation, dans un fichier TOML (« "…" ») et dans une valeur
      # YAML nue (configuration BMAD générée) : rien qui y change le sens d'une ligne.
      [[ ! $value =~ [[:cntrl:]] ]] || { echo "caractère de contrôle refusé"; return 1; }
      [[ $value =~ ^[^[:space:]](.*[^[:space:]])?$ ]] || { echo "libellé sans espace en tête ni en fin attendu"; return 1; }
      case $value in
        *[\"\\\'\`#:{}\[\],\&\*\!\|\>%@]*)
          echo "caractère refusé dans un libellé (aucun de \" \\ ' \` # : { } [ ] , & * ! | > % @)"
          return 1
          ;;
      esac
      ;;
    *) echo "type « $type » inconnu du lecteur"; return 1 ;;
  esac
  return 0
}

# Une liste sans doublon : un mot écrit deux fois serait traité deux fois (bin/install poserait deux
# fois le même lien, et échouerait au second, après d'autres écritures).
config_check_unique() { # $1 = liste séparée par des espaces
  local word
  local -A seen=()
  for word in $1; do
    [[ -z ${seen[$word]+x} ]] || { echo "« $word » écrit deux fois dans la liste"; return 1; }
    seen[$word]=1
  done
  return 0
}

# Un chemin relatif à la racine du projet, qui n'en sort pas : ni absolu, ni « .. », ni blanc.
config_check_path() {
  local value=$1
  [[ $value != /* ]] || { echo "chemin relatif à la racine du projet attendu, pas un chemin absolu"; return 1; }
  [[ $value =~ ^[A-Za-z0-9._/+-]+$ ]] || { echo "chemin attendu (lettres, chiffres, « . _ / + - »)"; return 1; }
  [[ /$value/ != */../* && /$value/ != */./* && $value != */ ]] \
    || { echo "chemin sans « . », « .. » ni « / » final attendu"; return 1; }
  return 0
}

config_load() { # $1 = fichier
  local file=$1 raw entry key value type count problems=() field
  local -A seen=() values=()
  config_values=()
  config_loaded=""
  if [[ ! -f $file || ! -r $file ]]; then
    printf '%s : fichier absent ou illisible.\n' "$file" >&2
    return 2
  fi
  # La liste passe par un fichier : une substitution « $(…) » perdrait les octets nuls qui séparent
  # les entrées. Le code de git est lu AVANT la sortie : sur une erreur de syntaxe, git écrit quand
  # même les clés qui précèdent l'erreur. Le fichier lui-même est lu par git, jamais par le shell.
  raw=$(mktemp) || { printf '%s : fichier temporaire impossible.\n' "$file" >&2; return 2; }
  local git_code=0
  git config -f "$file" --no-includes --null --list > "$raw" 2> /dev/null || git_code=$?
  if [[ $git_code != 0 ]]; then
    rm -f "$raw"
    printf "%s : syntaxe refusée par git config (code %s) ; rien n’est lu.\n" "$file" "$git_code" >&2
    return 2
  fi
  # Chaque entrée est « clé<LF>valeur<NUL> », ou « clé<NUL> » pour une clé écrite sans « = ».
  while IFS= read -r -d '' entry || [[ -n $entry ]]; do
    if [[ $entry != *$'\n'* ]]; then
      problems+=("$entry : écrit sans « = » (git le lirait comme « vrai ») ; une valeur est attendue.")
      seen[$entry]=$(( ${seen[$entry]:-0} + 1 ))
      continue
    fi
    key=${entry%%$'\n'*}
    value=${entry#*$'\n'}
    seen[$key]=$(( ${seen[$key]:-0} + 1 ))
    values[$key]=$value
  done < "$raw"
  rm -f "$raw"
  # Le schéma du fichier décide des champs attendus. Illisible, il est signalé par la vérification de
  # type ci-dessous, et les champs sont comptés au dernier schéma.
  local level=2
  [[ ${values[workflow.schema]:-} == 1 ]] && level=1
  for key in "${!seen[@]}"; do
    if [[ -z ${config_schema[$key]+x} ]]; then
      problems+=("$key : champ inconnu du schéma $level (section ou clé hors schéma, sous-section ou include compris).")
      continue
    fi
    if ((${config_since_schema[$key]:-1} > level)); then
      problems+=("$key : champ du schéma ${config_since_schema[$key]}, inconnu du schéma $level déclaré par workflow.schema.")
      continue
    fi
    count=${seen[$key]}
    ((count == 1)) || problems+=("$key : écrit $count fois ; une seule valeur est admise.")
  done
  for field in "${!config_schema[@]}"; do
    ((${config_since_schema[$field]:-1} <= level)) || continue
    [[ -n ${seen[$field]+x} ]] || problems+=("$field : champ absent ; aucune valeur par défaut n'existe.")
  done
  for key in "${!values[@]}"; do
    type=${config_schema[$key]:-}
    [[ -n $type && ${seen[$key]} == 1 ]] || continue
    ((${config_since_schema[$key]:-1} <= level)) || continue
    value=${values[$key]}
    if [[ -z $value ]]; then
      problems+=("$key : valeur vide.")
      continue
    fi
    if [[ $value == none ]]; then
      [[ $type == \?* ]] || problems+=("$key : « none » refusé, ce champ n'est pas désactivable.")
      continue
    fi
    local reason
    reason=$(config_check_type "$value" "${type#\?}") || problems+=("$key : $reason.")
  done
  # Règles entre champs : un champ qui n'a de sens qu'avec un autre ne se désactive pas seul.
  if ((${#problems[@]} == 0)); then
    config_pair_rule problems values sprint.convention sprint.status-file sprint.stories-dir
    if [[ ${values[sprint.convention]} == none && ${values[sprint.spec-source]} != none ]]; then
      problems+=("sprint.spec-source : doit valoir « none » quand sprint.convention vaut « none ».")
    fi
    if [[ ${values[guard.patterns-file]} == none && ${values[guard.command]} != none ]]; then
      problems+=("guard.patterns-file : « none » exige guard.command = none (un garde-fou sans motif ne garde rien).")
    fi
    config_pair_rule problems values ci.workflow ci.status-context
    if [[ ${values[forge.release-branch]} == "${values[forge.base]}" ]]; then
      problems+=("forge.release-branch : identique à forge.base.")
    fi
  fi
  if ((${#problems[@]})); then
    printf '%s : refusé.\n' "$file" >&2
    printf '  - %s\n' "${problems[@]}" | LC_ALL=C sort >&2
    return 2
  fi
  for key in "${!values[@]}"; do
    config_values[$key]=${values[$key]}
  done
  config_loaded=$file
  return 0
}

# Le premier champ commande les suivants : « none » sur l'un exige « none » sur tous, et une valeur
# sur l'un exige une valeur sur tous. $1 = tableau des problèmes, $2 = tableau des valeurs, $3… = champs.
config_pair_rule() {
  local -n pair_problems=$1 pair_values=$2
  shift 2
  local lead=$1 field
  shift
  for field in "$@"; do
    if [[ ${pair_values[$lead]} == none && ${pair_values[$field]} != none ]]; then
      pair_problems+=("$field : doit valoir « none » quand $lead vaut « none ».")
    elif [[ ${pair_values[$lead]} != none && ${pair_values[$field]} == none ]]; then
      pair_problems+=("$field : « none » refusé tant que $lead porte une valeur.")
    fi
  done
}

config_get() { # $1 = variable à remplir, $2 = champ
  local -n config_destination=$1
  [[ -n $config_loaded ]] || { printf 'config_get %s : aucun workflow.config chargé.\n' "$2" >&2; return 2; }
  [[ -n ${config_schema[$2]+x} ]] || { printf 'config_get : champ « %s » hors schéma.\n' "$2" >&2; return 2; }
  [[ -n ${config_values[$2]+x} ]] \
    || { printf 'config_get : champ « %s » du schéma %s, absent de %s (schéma %s).\n' "$2" \
      "${config_since_schema[$2]:-1}" "$config_loaded" "${config_values[workflow.schema]}" >&2; return 2; }
  # shellcheck disable=SC2034 # référence (local -n) : cette affectation remplit la variable de l'appelant
  config_destination=${config_values[$2]}
}

config_enabled() { # $1 = champ
  local value
  config_get value "$1" || return 2
  [[ $value != none ]]
}

# La racine du projet est le dépôt git du dossier courant. Si ce dépôt est le dépôt commun lui-même,
# consommé en sous-module, la racine est le projet qui le contient : un outil lancé depuis le
# sous-module agit sur le projet, jamais sur le dépôt commun par mégarde.
config_project_root() { # $1 = variable à remplir
  local -n config_root_destination=$1
  local top super
  [[ -n $config_common_root ]] || return 2
  top=$(git rev-parse --show-toplevel 2> /dev/null) || return 2
  top=$(cd "$top" && pwd -P) || return 2
  if [[ $top == "$config_common_root" ]]; then
    super=$(git rev-parse --show-superproject-working-tree 2> /dev/null) || return 2
    [[ -z $super ]] || top=$(cd "$super" && pwd -P) || return 2
  fi
  # shellcheck disable=SC2034 # référence (local -n) : cette affectation remplit la variable de l'appelant
  config_root_destination=$top
}
