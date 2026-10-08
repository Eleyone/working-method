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
# Les schémas 3 à 7 sont lus (procedures/workflow-config.md, « Changer de schéma »). Le 3 remplace les
# deux relecteurs nommés des schémas 1 et 2 par la table review.reviewers, ouverte à tout fournisseur. Un
# fichier au schéma 1 ou 2 est refusé avec ce qu'il faut changer, jamais lu « au mieux » : il porterait
# les anciennes clés, que plus aucun outil ne lit. Le 4 ajoute sprint.non-story-files, que la convention
# keyed exige : un projet numbered reste au 3 sans rien changer. Le 5 ajoute ci.statuses et ci.wait, l'étendue
# et l'attente du verrou CI (calculette#outillage-8) : verify-and-merge-pr les exige, aucun repli n'existe. Le 6
# ajoute review.agent-paths, les fichiers qui dirigent les agents et lèvent l'exception documentaire
# (calculette#outillage-22) ; comme le 4, il n'impose aucune migration : un fichier au schéma 5 reste valide
# pour tous les outils, et le verrou de revue dit qu'il ne contrôle pas ces fichiers. Le 7 ajoute la section
# [protection], les valeurs propres au projet de la règle commune de protection des branches
# (calculette#fix-protection-branches-dev-master) ; comme le 6, il n'impose aucune migration : seul
# gitea/check-branch-protection.sh l'exige.
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
  [sprint.non-story-files]=?globs
  [review.exempt-paths]=?regex
  [review.agent-paths]=?regex
  [review.report]=report
  [review.reviewers]=reviewers
  [review.timeout]=integer
  [review.project-layer]=path
  [review.private-paths]=paths
  [review.range-exclude]=?paths
  [guard.command]=?path
  [guard.patterns-file]=?path
  [ci.workflow]=?path
  [ci.status-context]=?text
  [ci.statuses]=?ci-statuses
  [ci.wait]=?seconds
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
  [protection.base-push]=?accounts
  [protection.base-force-push]=?accounts
  [protection.release-push]=?accounts
  [protection.merge]=accounts
  [protection.status-contexts]=?contexts
  [protection.block-outdated]=boolean
)
# Le schéma à partir duquel un champ existe ; un champ absent de cette table existe depuis le schéma 1.
# Il sert aux messages : un fichier d'un schéma ancien est refusé, mais chaque écart y est nommé.
declare -gA config_since_schema=(
  [bmad.project-name]=2
  [bmad.document-output-language]=2
  [bmad.output-folder]=2
  [review.reviewers]=3
  [sprint.non-story-files]=4
  [ci.statuses]=5
  [ci.wait]=5
  [review.agent-paths]=6
  [protection.base-push]=7
  [protection.base-force-push]=7
  [protection.release-push]=7
  [protection.merge]=7
  [protection.status-contexts]=7
  [protection.block-outdated]=7
)
# Les champs retirés, et ce qui les remplace : présents, ils font refuser le fichier avec la nouvelle
# forme, quel que soit le schéma déclaré — jamais une clé ignorée en silence.
declare -gA config_removed=(
  [review.reviewer-for-claude]="retiré au schéma 3 : la table review.reviewers le remplace, une entrée « auteur=modèle » par fournisseur d'auteur (« reviewers = claude=gemini-3.1-pro-high gemini=claude-opus-5-5-high »)"
  [protection.release-merge-style]="retiré du schéma 7 le 08/10/2026 : les styles de fusion ne sont plus un choix du projet — squash vers forge.base, avance rapide uniquement vers forge.release-branch, fixés par la règle commune (procedures/gitea-branches.md) ; supprimer la ligne"
  [review.reviewer-for-gemini]="retiré au schéma 3 : la table review.reviewers le remplace, une entrée « auteur=modèle » par fournisseur d'auteur (« reviewers = claude=gemini-3.1-pro-high gemini=claude-opus-5-5-high »)"
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
    schema)
      case $value in
        3|4|5|6|7) ;;
        1|2)
          local added=""
          [[ $value == 2 ]] || added=", et bmad.project-name, bmad.document-output-language, bmad.output-folder s'ajoutent"
          echo "schéma $value retiré : le schéma 3 est attendu — review.reviewer-for-claude et review.reviewer-for-gemini y sont remplacés par la table review.reviewers$added (procedures/workflow-config.md, « Changer de schéma »)"
          return 1
          ;;
        *) echo "schéma « $value » inconnu de cet outillage (schémas lus : 3 à 7)"; return 1 ;;
      esac
      ;;
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
        pr-comment) ;;
        # « file » (rapport en fichier local) a été retiré par calculette#outillage-8 : aucun outil ne le sert
        *) echo "« pr-comment » attendu (le rapport de revue est un commentaire de la PR ; « file » est retiré)"; return 1 ;;
      esac
      ;;
    reviewers) config_check_reviewers "$value" || return 1 ;;
    integer) [[ $value =~ ^[1-9][0-9]{0,5}$ ]] || { echo "entier positif attendu"; return 1; } ;;
    seconds)
      # une durée en secondes, 0 compris (0 : aucune attente) ; ni unité, ni zéro en tête, au plus 99999
      [[ $value =~ ^(0|[1-9][0-9]{0,4})$ ]] || { echo "durée en secondes attendue (entier de 0 à 99999, sans unité)"; return 1; }
      ;;
    ci-statuses)
      case $value in
        context|all) ;;
        *) echo "« context » (statuts de ci.status-context seuls) ou « all » (tous les statuts de la tête) attendu"; return 1 ;;
      esac
      ;;
    boolean)
      # « true » ou « false » seulement : git accepte aussi yes, on, 1…, que ce lecteur ne lit pas
      [[ $value == true || $value == false ]] || { echo "« true » ou « false » attendu"; return 1; }
      ;;
    semver) [[ $value =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version X.Y.Z attendue"; return 1; } ;;
    globs)
      # Motifs de noms de fichier, comparés au nom sans « .md » : lettres, chiffres, « . _ - » et les
      # jokers « * » et « ? ». Ni « / » (un nom, pas un chemin), ni crochet, ni « .md », ni point en tête.
      [[ $value =~ ^[^[:space:]]+( [^[:space:]]+)*$ ]] \
        || { echo "liste de motifs attendue, séparés par une espace"; return 1; }
      # découpage par read, jamais par « for w in $value » : un motif ne s'étend pas aux fichiers du
      # dossier courant (config_check_unique découpe par le shell : les doublons sont comptés ici)
      local -a globs=()
      local -A seen_globs=()
      read -r -a globs <<< "$value"
      for word in "${globs[@]}"; do
        [[ $word =~ ^[A-Za-z0-9_*?-][A-Za-z0-9._*?-]*$ && $word != *.md ]] \
          || { echo "« $word » : motif de nom attendu (lettres, chiffres, « . _ - », jokers « * ? », sans « / » ni « .md » ni point en tête)"; return 1; }
        [[ -z ${seen_globs[$word]+x} ]] || { echo "« $word » écrit deux fois dans la liste"; return 1; }
        seen_globs[$word]=1
      done
      ;;
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
    accounts)
      # comptes de la forge, séparés par une espace : la forge ne distingue pas la casse d'un nom de
      # compte, un doublon se compte donc sans elle
      [[ $value =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*( [A-Za-z0-9][A-Za-z0-9_.-]*)*$ ]] \
        || { echo "comptes de la forge attendus (lettres, chiffres, « _ . - », sans « - » en tête), séparés par une espace"; return 1; }
      config_check_unique "${value,,}" || return 1
      # « None » ou « NONE » ne désactive rien : seul « none » le fait ; écrit autrement, il serait lu
      # comme un compte de ce nom
      [[ " ${value,,} " != *" none "* ]] || { echo "« none » n'est pas un compte : seul « none », en minuscules et seul, désactive un champ désactivable"; return 1; }
      ;;
    contexts)
      # motifs de contextes de statut, tels que la forge les exige (« checks / checks* ») : ils
      # contiennent des espaces, d'où la virgule entre deux motifs ; les blancs autour d'elle sont ôtés
      local -a contexts=()
      local -A seen_contexts=()
      local context
      [[ $value != *, && $value != ,* ]] || { echo "motif vide autour d'une virgule"; return 1; }
      IFS=, read -r -a contexts <<< "$value"
      for context in "${contexts[@]}"; do
        context=${context#"${context%%[![:space:]]*}"}
        context=${context%"${context##*[![:space:]]}"}
        [[ -n $context ]] || { echo "motif vide autour d'une virgule"; return 1; }
        [[ ! $context =~ [[:cntrl:]] ]] || { echo "caractère de contrôle refusé"; return 1; }
        [[ -z ${seen_contexts[$context]+x} ]] || { echo "« $context » écrit deux fois dans la liste"; return 1; }
        seen_contexts[$context]=1
      done
      ;;
    *) echo "type « $type » inconnu du lecteur"; return 1 ;;
  esac
  return 0
}

# La table « fournisseur de l'auteur → relecteur » : des entrées « auteur=modèle », séparées par une
# espace. L'auteur est nommé par son fournisseur (claude, gemini, gpt…) ; le fournisseur d'un modèle est
# le premier segment de son nom dans « agy models » (gemini-3.1-pro-high → gemini). ⛔ Une entrée dont
# le relecteur est du même fournisseur que l'auteur est refusée : c'est la règle de la revue croisée, et
# la configuration ne doit pas pouvoir la contourner. Un fournisseur s'ajoute par une entrée, jamais
# par du code.
config_check_reviewers() { # $1 = valeur
  local entry author model
  local -A authors=()
  [[ $1 =~ ^[^[:space:]]+( [^[:space:]]+)*$ ]] \
    || { echo "entrées « auteur=modèle » attendues, séparées par une espace"; return 1; }
  for entry in $1; do
    [[ $entry =~ ^([a-z][a-z0-9]*)=([a-z0-9][a-z0-9.-]*)$ ]] \
      || { echo "« $entry » : entrée « auteur=modèle » attendue (auteur : son fournisseur en minuscules, par exemple claude ; modèle : un nom de « agy models »)"; return 1; }
    author=${BASH_REMATCH[1]} model=${BASH_REMATCH[2]}
    [[ -z ${authors[$author]+x} ]] || { echo "« $author » a deux entrées ; un seul relecteur par fournisseur d'auteur"; return 1; }
    authors[$author]=1
    [[ ${model%%-*} != "$author" ]] \
      || { echo "« $entry » : le relecteur est du même fournisseur que l'auteur ($author) ; la revue croisée exige un autre fournisseur"; return 1; }
  done
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
  local file=$1 raw entry key value type count problems=() field reason
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
  # type ci-dessous, et les champs sont comptés au schéma 3 : un fichier sans schéma lisible n'est pas
  # présumé keyed.
  local level=3
  case ${values[workflow.schema]:-} in
    1|2|4|5|6|7) level=${values[workflow.schema]} ;;
  esac
  for key in "${!seen[@]}"; do
    if [[ -n ${config_removed[$key]+x} ]]; then
      problems+=("$key : ${config_removed[$key]}.")
      continue
    fi
    if [[ $key == module.* ]]; then
      # surcharge optionnelle d'une valeur de module BMAD (config_check_module_override)
      count=${seen[$key]}
      if ((count != 1)); then
        problems+=("$key : écrit $count fois ; une seule valeur est admise.")
      elif ! reason=$(config_check_module_override "$key" "${values[$key]-}" "${values[bmad.modules]-}"); then
        problems+=("$key : $reason.")
      fi
      continue
    fi
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
    # keyed lit sprint.non-story-files, que seul le schéma 4 porte ; ailleurs, le champ ne veut rien dire
    if [[ ${values[sprint.convention]} == keyed ]] && ((level < 4)); then
      problems+=("sprint.convention : « keyed » exige le schéma 4 (champ sprint.non-story-files) ; workflow.schema vaut $level.")
    fi
    if ((level >= 4)) && [[ ${values[sprint.convention]} != keyed && ${values[sprint.non-story-files]} != none ]]; then
      problems+=("sprint.non-story-files : doit valoir « none » quand sprint.convention ne vaut pas « keyed ».")
    fi
    if ((level >= 5)); then
      config_pair_rule problems values ci.workflow ci.status-context ci.statuses ci.wait
    else
      config_pair_rule problems values ci.workflow ci.status-context
    fi
    if ((level >= 7)); then
      config_protection_rules problems values
    fi
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

# Surcharges des modules BMAD : « [module "<nom>"] <clé> = <valeur> », lue « module.<nom>.<clé> ».
# Optionnelles : sans surcharge, la valeur est celle du modèle de configuration du module, que porte le
# sous-module (bmad/method/templates/<nom>.config.yaml) — une valeur écrite et versionnée, pas un
# défaut du lecteur. La clé s'écrit avec des tirets (git config refuse « _ ») et désigne la clé du
# modèle écrite avec des « _ ». Seule une valeur LITTÉRALE du modèle se surcharge : une valeur dérivée
# d'un champ (« @bmad.…@ », « @user:…@ ») a déjà son champ. Une valeur « true » ou « false » du modèle
# n'admet que « true » ou « false ». Procédure : procedures/workflow-config.md
config_module_template() { # $1 = module ; affiche le chemin de son modèle de config.yaml
  printf '%s/bmad/method/templates/%s.config.yaml\n' "$config_common_root" "$1"
}

# $1 = clé « module.<nom>.<clé> », $2 = valeur, $3 = bmad.modules ; 0 valide, 1 sinon (raison écrite)
config_check_module_override() {
  local key=$1 value=$2 modules=$3 module name template line found="" literal="" keys=""
  [[ $key =~ ^module\.([a-z0-9-]+)\.([a-z0-9-]+)$ ]] \
    || { echo "forme « [module \"<nom>\"] <clé> = <valeur> » attendue (nom et clé : minuscules, chiffres, tirets)"; return 1; }
  module=${BASH_REMATCH[1]}
  name=${BASH_REMATCH[2]//-/_}
  template=$(config_module_template "$module")
  [[ -f $template ]] || { echo "module « $module » sans modèle de configuration dans le dépôt commun"; return 1; }
  [[ " $modules " == *" $module "* ]] \
    || { echo "module « $module » absent de bmad.modules : sa configuration n'est pas générée"; return 1; }
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^([a-z0-9_]+):\ (.*)$ ]] || continue
    if [[ ${BASH_REMATCH[2]} == *@* ]]; then
      [[ ${BASH_REMATCH[1]} != "$name" ]] || found=derived
      continue
    fi
    keys+=" ${BASH_REMATCH[1]//_/-}"
    if [[ ${BASH_REMATCH[1]} == "$name" ]]; then
      found=literal
      literal=${BASH_REMATCH[2]}
    fi
  done < "$template"
  case $found in
    literal) ;;
    derived)
      echo "valeur dérivée d'un champ de workflow.config ou de _bmad/config.user.toml : elle ne se surcharge pas ici"
      return 1
      ;;
    *) echo "clé inconnue du modèle de $module (clés surchargeables :${keys:- aucune})"; return 1 ;;
  esac
  [[ -n $value ]] || { echo "valeur vide"; return 1; }
  if [[ $literal == true || $literal == false ]]; then
    [[ $value == true || $value == false ]] \
      || { echo "« true » ou « false » attendu (valeur du modèle : $literal)"; return 1; }
    return 0
  fi
  [[ ! $value =~ [[:cntrl:]] ]] || { echo "caractère de contrôle refusé"; return 1; }
  [[ $value =~ ^[^[:space:]](.*[^[:space:]])?$ ]] || { echo "valeur sans espace en tête ni en fin attendue"; return 1; }
  case $value in
    *[\"\\\`@]*) echo "caractère refusé dans une surcharge (aucun de \" \\ \` @)"; return 1 ;;
  esac
  return 0
}

# Les surcharges d'un module, une fois le fichier chargé : une ligne « <clé du modèle><TAB><valeur> »
# par surcharge, triées. Rien si le module n'en a pas.
config_module_overrides() { # $1 = module
  local key name
  [[ -n $config_loaded ]] || { printf 'config_module_overrides : aucun workflow.config chargé.\n' >&2; return 2; }
  for key in "${!config_values[@]}"; do
    [[ $key == "module.$1."* ]] || continue
    name=${key#"module.$1."}
    printf '%s\t%s\n' "${name//-/_}" "${config_values[$key]}"
  done | LC_ALL=C sort
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

# Règles de la section [protection] (schéma 7). $1 = tableau des problèmes, $2 = tableau des valeurs.
config_protection_rules() {
  local -n prot_problems=$1 prot_values=$2
  local account missing=""
  local -A pushers=()
  # la forge n'admet un push forcé qu'à un compte qui peut déjà pousser
  if [[ ${prot_values[protection.base-force-push]} != none ]]; then
    if [[ ${prot_values[protection.base-push]} != none ]]; then
      for account in ${prot_values[protection.base-push]}; do pushers[${account,,}]=1; done
    fi
    for account in ${prot_values[protection.base-force-push]}; do
      [[ -n ${pushers[${account,,}]+x} ]] || missing+=" $account"
    done
    [[ -z $missing ]] \
      || prot_problems+=("protection.base-force-push : chaque compte doit aussi figurer dans protection.base-push (absents :$missing).")
  fi
  # un dépôt sans branche de publication ne déclare rien pour elle
  if [[ ${prot_values[forge.release-branch]} == none ]]; then
    [[ ${prot_values[protection.release-push]} == none ]] \
      || prot_problems+=("protection.release-push : doit valoir « none » quand forge.release-branch vaut « none ».")
  fi
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
