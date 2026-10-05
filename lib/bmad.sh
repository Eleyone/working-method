# shellcheck shell=bash
# BMAD dans le dépôt commun : lecture de la version déclarée, et génération de la configuration BMAD
# d'un projet. Chargé par bin/install.bash et bmad/update.sh.
#
# À charger par « . lib/bmad.sh ». Dépendances : bash 4.3 ou plus, git.
#
#   bmad_declared_load <fichier>       lit bmad/bmad.config ENTIER (format git config) : 0 valide ; 2 sinon,
#                                      une ligne par problème. Remplit bmad_declared_version,
#                                      bmad_declared_modules, bmad_declared_shims et bmad_declared_pins.
#   bmad_user_load <fichier>           lit _bmad/config.user.toml (sous-ensemble strict de TOML, ci-dessous) :
#                                      0 ; 2 si absent, illisible ou hors du sous-ensemble. Remplit
#                                      bmad_user_values[« section.clé »].
#   bmad_safe_value <valeur>           0 si la valeur peut entrer telle quelle dans un fichier TOML ou YAML
#                                      généré ; 1 sinon, la raison sur la sortie standard.
#   bmad_render <modèle> <sortie>      remplace chaque « @champ@ » du modèle par bmad_placeholders[champ] :
#                                      0 ; 2 si un champ du modèle n'a pas de valeur, ou si l'écriture échoue.
#   bmad_config_toml <modèle> <sortie> <modules>
#                                      ne garde, du modèle de config.toml, que les blocs des modules donnés
#                                      (marqueurs « #@module <m> » posés par bmad/update.sh) : 0 ; 2 sinon.
#   bmad_apply_overrides <yaml> <toml> <module>
#                                      applique au config.yaml et au config.toml rendus les surcharges
#                                      du module déclarées dans workflow.config : 0 ; 2 sinon.
#   bmad_skill_manifest_load <fichier> lit skill-manifest.csv (table skill → module de l'installeur) :
#                                      0 ; 2 si une ligne n'est pas lue. Remplit bmad_skill_module[skill].
#   bmad_help_catalog <catalogue> <dossier des modules> <sortie> <modules>
#                                      ne garde, du catalogue d'aide de l'union, que les lignes des modules
#                                      donnés, dans le même ordre : 0 ; 2 sinon.
#
# Pourquoi la configuration est générée ici et pas par l'installeur BMAD : l'installeur ne tourne que
# dans le dépôt commun (décision 6.2 du 30/09/2026) ; lancé dans un projet, il écrirait à travers les
# liens, donc dans le sous-module. Et le relevé du 04/10/2026 l'a montré : réinstallé en place, il
# réécrit des dates, perd une édition sans la signaler, et altère une valeur.
# Procédure : procedures/bmad.md

# shellcheck source=config.sh
. "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# Modules intégrés au paquet bmad-method : ils portent la version de BMAD et n'ont pas d'épinglage.
readonly bmad_builtin_modules="core bmm"

declare -g bmad_declared_version="" bmad_declared_modules="" bmad_declared_shims=""
declare -gA bmad_declared_pins=()
declare -gA bmad_user_values=()
declare -gA bmad_placeholders=()
declare -gA bmad_skill_module=()

bmad_is_builtin() { [[ " $bmad_builtin_modules " == *" $1 "* ]]; }

bmad_declared_load() { # $1 = fichier bmad.config
  local file=$1 raw entry key value problems=() module
  local -A seen=() values=()
  bmad_declared_version="" bmad_declared_modules="" bmad_declared_shims=""
  bmad_declared_pins=()
  if [[ ! -f $file || ! -r $file ]]; then
    printf '%s : fichier absent ou illisible.\n' "$file" >&2
    return 2
  fi
  raw=$(mktemp) || { printf '%s : fichier temporaire impossible.\n' "$file" >&2; return 2; }
  local git_code=0
  git config -f "$file" --no-includes --null --list > "$raw" 2> /dev/null || git_code=$?
  if [[ $git_code != 0 ]]; then
    rm -f "$raw"
    printf "%s : syntaxe refusée par git config (code %s) ; rien n’est lu.\n" "$file" "$git_code" >&2
    return 2
  fi
  while IFS= read -r -d '' entry || [[ -n $entry ]]; do
    if [[ $entry != *$'\n'* ]]; then
      problems+=("$entry : écrit sans « = » ; une valeur est attendue.")
      continue
    fi
    key=${entry%%$'\n'*}
    value=${entry#*$'\n'}
    seen[$key]=$(( ${seen[$key]:-0} + 1 ))
    values[$key]=$value
  done < "$raw"
  rm -f "$raw"
  for key in "${!seen[@]}"; do
    ((${seen[$key]} == 1)) || problems+=("$key : écrit ${seen[$key]} fois ; une seule valeur est admise.")
    [[ -n ${values[$key]} ]] || problems+=("$key : valeur vide.")
    case $key in
      bmad.version | bmad.modules | bmad.shims | pin.*) ;;
      *) problems+=("$key : champ inconnu (admis : bmad.version, bmad.modules, bmad.shims, pin.<module>).") ;;
    esac
  done
  for key in bmad.version bmad.modules bmad.shims; do
    [[ -n ${seen[$key]+x} ]] || problems+=("$key : champ absent ; aucune valeur par défaut n'existe.")
  done
  if ((${#problems[@]} == 0)); then
    [[ ${values[bmad.version]} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || problems+=("bmad.version : version X.Y.Z attendue.")
    [[ ${values[bmad.modules]} =~ ^[a-z0-9][a-z0-9-]*( [a-z0-9][a-z0-9-]*)*$ ]] \
      || problems+=("bmad.modules : liste de codes de modules attendue, séparés par une espace.")
    [[ ${values[bmad.shims]} == true || ${values[bmad.shims]} == false ]] \
      || problems+=("bmad.shims : « true » ou « false » attendu.")
    for module in $bmad_builtin_modules; do
      [[ " ${values[bmad.modules]} " == *" $module "* ]] \
        || problems+=("bmad.modules : le module intégré « $module » manque.")
    done
    for module in ${values[bmad.modules]}; do
      if bmad_is_builtin "$module"; then
        [[ -z ${values[pin.$module]+x} ]] \
          || problems+=("pin.$module : un module intégré porte la version de BMAD, pas d'épinglage.")
      elif [[ -z ${values[pin.$module]+x} ]]; then
        problems+=("pin.$module : module externe sans version épinglée ; aucune valeur par défaut n'existe.")
      elif [[ ! ${values[pin.$module]} =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        problems+=("pin.$module : étiquette de version attendue (v1.2.3 ou 1.2.3).")
      fi
    done
    for key in "${!values[@]}"; do
      [[ $key == pin.* ]] || continue
      [[ " ${values[bmad.modules]} " == *" ${key#pin.} "* ]] \
        || problems+=("$key : épinglage d'un module absent de bmad.modules.")
    done
  fi
  if ((${#problems[@]})); then
    printf '%s : refusé.\n' "$file" >&2
    printf '  - %s\n' "${problems[@]}" | LC_ALL=C sort >&2
    return 2
  fi
  # shellcheck disable=SC2034 # globale de la bibliothèque, lue par bin/install.bash et bmad/update.sh
  bmad_declared_version=${values[bmad.version]}
  # shellcheck disable=SC2034 # globale de la bibliothèque, lue par bin/install.bash et bmad/update.sh
  bmad_declared_modules=${values[bmad.modules]}
  # shellcheck disable=SC2034 # globale de la bibliothèque, lue par bin/install.bash et bmad/update.sh
  bmad_declared_shims=${values[bmad.shims]}
  for key in "${!values[@]}"; do
    # shellcheck disable=SC2034 # globale de la bibliothèque, lue par bin/install.bash et bmad/update.sh
    [[ $key == pin.* ]] && bmad_declared_pins[${key#pin.}]=${values[$key]}
  done
  return 0
}

# Une valeur qui entre telle quelle dans un fichier généré : la règle est celle du type « label » du
# lecteur de workflow.config, écrite une seule fois (lib/config.sh, config_check_type).
bmad_safe_value() { # $1 = valeur
  [[ -n $1 ]] || { echo "valeur vide"; return 1; }
  config_check_type "$1" label
}

# Sous-ensemble de TOML lu : lignes vides, commentaires « # … », sections « [a.b] », et
# « clé = "valeur" » (chaîne simple, sans antislash ni guillemet intérieur). Tout le reste est refusé,
# avec son numéro de ligne : un fichier qu'on ne sait pas lire n'est jamais lu « au mieux ».
bmad_user_load() { # $1 = fichier
  local file=$1 line number=0 section="" key value problems=() reason
  local -A seen=()
  bmad_user_values=()
  if [[ ! -f $file || ! -r $file ]]; then
    printf '%s : fichier absent ou illisible.\n' "$file" >&2
    return 2
  fi
  while IFS= read -r line || [[ -n $line ]]; do
    number=$((number + 1))
    line=${line%$'\r'}
    if [[ $line =~ ^[[:space:]]*(#.*)?$ ]]; then
      continue
    elif [[ $line =~ ^\[([a-z0-9_.-]+)\][[:space:]]*$ ]]; then
      section=${BASH_REMATCH[1]}
    elif [[ $line =~ ^([a-z0-9_-]+)[[:space:]]*=[[:space:]]*\"([^\"\\]*)\"[[:space:]]*$ ]]; then
      key=${BASH_REMATCH[1]}
      value=${BASH_REMATCH[2]}
      if [[ -z $section ]]; then
        problems+=("ligne $number : clé « $key » hors de toute section.")
        continue
      fi
      if [[ -n ${seen[$section.$key]+x} ]]; then
        problems+=("ligne $number : « $section.$key » écrit deux fois.")
        continue
      fi
      seen[$section.$key]=1
      if ! reason=$(bmad_safe_value "$value"); then
        problems+=("ligne $number : « $section.$key » : $reason.")
        continue
      fi
      # shellcheck disable=SC2034 # globale de la bibliothèque, lue par bin/install.bash
      bmad_user_values[$section.$key]=$value
    else
      problems+=("ligne $number : forme non lue (admis : commentaire, [section], clé = \"valeur\").")
    fi
  done < "$file"
  if ((${#problems[@]})); then
    printf '%s : refusé.\n' "$file" >&2
    printf '  - %s\n' "${problems[@]}" >&2
    # shellcheck disable=SC2034 # globale de la bibliothèque, lue par bin/install.bash
    bmad_user_values=()
    return 2
  fi
  return 0
}

bmad_render() { # $1 = modèle, $2 = sortie
  local template=$1 output=$2 content field missing=()
  content=$(<"$template") || { printf '%s : modèle illisible.\n' "$template" >&2; return 2; }
  while [[ $content =~ @((bmad\.|user:)[a-z0-9_.-]+)@ ]]; do
    field=${BASH_REMATCH[1]}
    if [[ -z ${bmad_placeholders[$field]+x} ]]; then
      missing+=("$field")
      content=${content//"@$field@"/}
      continue
    fi
    content=${content//"@$field@"/${bmad_placeholders[$field]}}
  done
  if ((${#missing[@]})); then
    printf '%s : aucune valeur pour : %s.\n' "$template" "${missing[*]}" >&2
    return 2
  fi
  printf '%s\n' "$content" > "$output" || { printf '%s : écriture impossible.\n' "$output" >&2; return 2; }
}

bmad_config_toml() { # $1 = modèle, $2 = sortie, $3 = modules à garder
  local template=$1 output=$2 modules=" $3 " line keep="" seen_marker=""
  : > "$output" || { printf '%s : écriture impossible.\n' "$output" >&2; return 2; }
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ ^#@module\ ([a-z0-9-]+)$ ]]; then
      seen_marker=1
      [[ $modules == *" ${BASH_REMATCH[1]} "* ]] && keep=1 || keep=""
      continue
    fi
    if [[ -z $seen_marker ]]; then
      printf '%s : contenu avant le premier marqueur « #@module » : modèle incohérent.\n' "$template" >&2
      return 2
    fi
    [[ -z $keep ]] || printf '%s\n' "$line" >> "$output" || return 2
  done < "$template"
  [[ -n $seen_marker ]] || { printf '%s : aucun marqueur « #@module » : modèle incohérent.\n' "$template" >&2; return 2; }
}

# Applique les surcharges du module (« [module "<nom>"] » de workflow.config, déjà validées par
# config_load) à son config.yaml rendu et au bloc [modules.<nom>] du config.toml rendu. Une valeur
# booléenne du modèle reste nue ; toute autre est écrite entre guillemets doubles, forme que YAML et
# TOML lisent toutes deux comme une chaîne (les guillemets, antislashs et « @ » sont refusés en amont).
# Chaque clé surchargée doit se trouver exactement une fois dans chacun des deux fichiers : sinon le
# modèle et la validation ne concordent plus, et rien n'est écrit (2). L'écriture passe par
# « <fichier>.surcharge » puis mv : un échec laisse le fichier rendu tel qu'il était.
bmad_apply_overrides() { # $1 = config.yaml rendu, $2 = config.toml rendu, $3 = module
  local yaml=$1 toml=$2 module=$3 name value overrides line out hits section current rendered
  overrides=$(config_module_overrides "$module") || return 2
  [[ -n $overrides ]] || return 0
  while IFS=$'\t' read -r name value; do
    # config.yaml : « <clé>: <valeur> » en début de ligne
    out="" hits=0 rendered=""
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line =~ ^${name}:\ (.*)$ ]]; then
        current=${BASH_REMATCH[1]}
        hits=$((hits + 1))
        if [[ $current == true || $current == false ]]; then rendered=$value; else rendered="\"$value\""; fi
        line="$name: $rendered"
      fi
      out+=$line$'\n'
    done < "$yaml"
    ((hits == 1)) || { printf '%s : clé « %s » trouvée %s fois dans la configuration de %s ; une attendue.\n' "$yaml" "$name" "$hits" "$module" >&2; return 2; }
    { printf '%s' "$out" > "$yaml.surcharge" && mv -f "$yaml.surcharge" "$yaml"; } \
      || { printf '%s : écriture impossible.\n' "$yaml" >&2; return 2; }
    # config.toml : « <clé> = <valeur> » dans le bloc [modules.<module>]
    out="" hits=0 section=""
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line =~ ^\[(.*)\]$ ]]; then
        section=${BASH_REMATCH[1]}
      elif [[ $section == "modules.$module" && $line =~ ^${name}\ =\ (.*)$ ]]; then
        hits=$((hits + 1))
        line="$name = $rendered"
      fi
      out+=$line$'\n'
    done < "$toml"
    ((hits == 1)) || { printf '%s : clé « %s » trouvée %s fois dans [modules.%s] ; une attendue.\n' "$toml" "$name" "$hits" "$module" >&2; return 2; }
    { printf '%s' "$out" > "$toml.surcharge" && mv -f "$toml.surcharge" "$toml"; } \
      || { printf '%s : écriture impossible.\n' "$toml" >&2; return 2; }
  done <<< "$overrides"
  return 0
}

# Le catalogue est celui que l'installeur a assemblé pour l'union, déjà trié par module puis par
# phase : en garder les lignes de certains modules, dans le même ordre, donne ce qu'il assemblerait
# pour ces modules seuls. La première colonne de chaque ligne nomme le module par son libellé, lu dans
# le module-help.csv de chaque module ; une ligne d'un libellé inconnu rend 2.
bmad_help_catalog() { # $1 = catalogue, $2 = dossier des modules, $3 = sortie, $4 = modules à garder
  local catalog=$1 modules_dir=$2 output=$3 module line label header="" first=1 out=""
  local -A label_of=() keep=()
  for module in "$modules_dir"/*/; do
    module=${module%/}
    module=${module##*/}
    [[ -f $modules_dir/$module/module-help.csv ]] || continue
    label=$(tail -n +2 "$modules_dir/$module/module-help.csv" | cut -d, -f1 | LC_ALL=C sort -u) \
      || { printf '%s : catalogue du module illisible.\n' "$module" >&2; return 2; }
    if [[ -z $label || $label == *$'\n'* || $label == \"* ]]; then
      printf '%s/module-help.csv : un seul libellé de module attendu en première colonne.\n' "$module" >&2
      return 2
    fi
    label_of[$label]=$module
  done
  for module in $4; do keep[$module]=1; done
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ -z $header ]]; then
      header=$line
      out=$line
      continue
    fi
    label=${line%%,*}
    module=${label_of[$label]:-}
    if [[ -z $module ]]; then
      printf "%s : ligne d’un module inconnu (« %s »).\n" "$catalog" "$label" >&2
      return 2
    fi
    [[ -z ${keep[$module]+x} ]] || out+=$'\n'"$line"
    first=""
  done < "$catalog"
  [[ $header == module,* && -z $first ]] || { printf '%s : catalogue vide ou sans en-tête.\n' "$catalog" >&2; return 2; }
  # sans retour à la ligne final : c'est la forme qu'écrit l'installeur
  printf '%s' "$out" > "$output" || { printf '%s : écriture impossible.\n' "$output" >&2; return 2; }
}

# Chaque ligne : « "canonicalId","name","description","module","chemin" », tous les champs cités. La
# description peut contenir des virgules et des guillemets doublés : le module se lit en fin de ligne.
bmad_skill_manifest_load() { # $1 = fichier
  local file=$1 line number=0
  bmad_skill_module=()
  [[ -f $file && -r $file ]] || { printf '%s : fichier absent ou illisible.\n' "$file" >&2; return 2; }
  while IFS= read -r line || [[ -n $line ]]; do
    number=$((number + 1))
    [[ $number == 1 && $line == canonicalId,* ]] && continue
    if [[ ! $line =~ ^\"([a-z0-9][a-z0-9-]*)\",.*,\"([a-z0-9-]+)\",\"[^\"]*\"$ ]]; then
      printf '%s : ligne %s non lue.\n' "$file" "$number" >&2
      bmad_skill_module=()
      return 2
    fi
    bmad_skill_module[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
  done < "$file"
  ((${#bmad_skill_module[@]})) || { printf '%s : aucune skill.\n' "$file" >&2; return 2; }
}
