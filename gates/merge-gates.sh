# Décisions des verrous de fusion de verify-and-merge-pr, séparées des appels à la forge pour être testées sur
# des fichiers : pages de timeline, état combiné de la CI, réponse de la PR, commits d'un dépôt git.
#
# À charger par « . scripts/lib/merge-gates.sh ». Dépendances : bash, git, jq.
# Les fonctions ne comptent pas sur set -e : un appel suivi de || le suspend pour toute la fonction,
# donc chaque étape vérifie son résultat.
#
#   timeline_page_count <page>                         nombre d'éléments d'une page, 0 pour null : 0 lu, 2 illisible
#   timeline_page_reports <page> <compte>              première ligne des commentaires « llm-review » du compte : 0, 2 illisible
#   read_timeline_reports <fonction> <compte> <taille> <plafond> <sortie>
#                                                      rapports de toutes les pages : 0 lus, 2 page illisible, 3 plafond atteint
#   last_report <rapports> <SHA> <base>                dernier rapport pour ce SHA et cette base, champs comparés à l'identique
#   status_commit_ok <SHA relu> <SHA de tête> <clé> <suivi> <dossier des stories>
#                                                      règle du commit de statut : 0 respectée, 1 sinon, avec la raison
#   ci_gate <état CI> <workflow sur la base : 0 ou 1> <chemin du workflow>
#                                                      « passe|bloque|amorçage<TAB>détail » : 0, 2 illisible
#   pr_title <PR>                                      titre de la PR, en texte brut : 0, 2 illisible
#   merge_title <PR> <numéro> <sortie>                 titre du commit de fusion, octet pour octet : 0, 2 illisible
#
# Procédure : docs/procedures/verify-and-merge-pr.md

# Au-delà de la dernière page, la forge répond null et non une liste vide.
timeline_page_count() { # $1 page de timeline
  local count
  count=$(jq -e 'if type == "array" then length elif type == "null" then 0 else error end' "$1" 2>/dev/null) || return 2
  [[ $count =~ ^[0-9]+$ ]] || return 2
  printf '%s\n' "$count"
}

timeline_page_reports() { # $1 page de timeline, $2 compte qui publie les rapports
  jq -r --arg u "$2" \
    '(. // [])[] | select(.type == "comment" and .user.login == $u) | ((.body // "") | split("\n")[0]) | select(startswith("llm-review "))' \
    "$1" 2>/dev/null || return 2
}

# La liste des commentaires d'une issue ignore limit et page : les rapports sont lus dans la timeline de la PR,
# page par page. $1 est la fonction qui écrit la page <numéro> dans <fichier> : le script lui fait appeler la
# forge, les tests lui font lire des fixtures.
read_timeline_reports() { # $1 fonction, $2 compte, $3 taille de page, $4 plafond de pages, $5 fichier de sortie
  local fetch=$1 user=$2 size=$3 max=$4 out=$5 page=1 count
  [[ $size =~ ^[1-9][0-9]*$ && $max =~ ^[1-9][0-9]*$ ]] || return 2
  : > "$out" || return 2
  while :; do
    ((page <= max)) || { rm -f "$out.page"; return 3; }
    "$fetch" "$page" "$out.page" || { rm -f "$out.page"; return 2; }
    count=$(timeline_page_count "$out.page") || { rm -f "$out.page"; return 2; }
    timeline_page_reports "$out.page" "$user" >> "$out" || { rm -f "$out.page"; return 2; }
    ((count == size)) || break
    page=$((page + 1))
  done
  rm -f "$out.page"
}

last_report() { # $1 fichier des premières lignes de rapports, $2 SHA, $3 base
  awk -v sha="sha=$2" -v base="base=$3" '
    NF == 5 && $1 == "llm-review" && $2 == sha && $3 == base && $4 ~ /^model=./ && ($5 == "verdict=pass" || $5 == "verdict=block") { last = $0 }
    END { if (last != "") print last }
  ' "$1"
}

# Le commit de tête, seul après le SHA relu, ne change que les lignes de statut (story review → done,
# last_updated, epic → done) et n'ajoute par ailleurs que des lignes au fichier de story et à
# deferred-work.md. Affiche la raison d'un refus.
# Lignes d'un texte qui correspondent, ou avec -v ne correspondent pas, à un motif. grep rend 1 quand il ne
# trouve rien et 2 sur une erreur : « rien trouvé » réussit avec une sortie vide, une erreur échoue.
select_lines() { # $1 options de grep (-E, -vE, -xF…), $2 motif, $3 texte
  local rc=0
  grep "$1" -- "$2" <<< "$3" || rc=$?
  ((rc <= 1))
}

# Les noms locaux sont préfixés : un script appelant déclare status_file et stories_dir en readonly, et
# « local » sur un nom readonly échoue en gardant la valeur du script.
status_commit_ok() { # $1 SHA relu, $2 SHA de tête, $3 clé de la story, $4 suivi de sprint, $5 dossier des stories
  local reviewed=$1 head=$2 story_key=$3 rule_status_file=$4 rule_stories_dir=$5 count files f diff_out removed added extra found
  count=$(git rev-list --count "$reviewed..$head" 2>/dev/null) || { echo "commits après le SHA relu illisibles"; return 1; }
  [[ $count == 1 ]] || { echo "plus d'un commit après le SHA relu"; return 1; }
  [[ -n $story_key ]] || { echo "aucune story associée à la branche"; return 1; }
  files=$(git diff --name-only "$reviewed" "$head") || { echo "diff du commit de tête illisible"; return 1; }
  while IFS= read -r f; do
    [[ -n $f ]] || continue
    # le diff est lu d'abord : un échec de git diff refuse la règle au lieu de donner une liste vide
    diff_out=$(git diff -U0 "$reviewed" "$head" -- "$f") || { echo "diff de $f illisible"; return 1; }
    removed=$(select_lines -E '^-' "$diff_out") && removed=$(select_lines -vE '^---( |$)' "$removed") \
      || { echo "lecture du diff de $f impossible"; return 1; }
    added=$(select_lines -E '^\+' "$diff_out") && added=$(select_lines -vE '^\+\+\+( |$)' "$added") \
      || { echo "lecture du diff de $f impossible"; return 1; }
    case $f in
      "$rule_status_file")
        extra=$(select_lines -vE "^-[[:space:]]+$story_key: review$|^-last_updated: |^-[[:space:]]+epic-[0-9]+: [a-z-]+$" "$removed") \
          || { echo "lecture du diff de $f impossible"; return 1; }
        [[ -z $extra ]] || { echo "suivi de sprint : suppression hors des lignes de statut"; return 1; }
        extra=$(select_lines -vE "^\+[[:space:]]+$story_key: done$|^\+last_updated: |^\+[[:space:]]+epic-[0-9]+: done$" "$added") \
          || { echo "lecture du diff de $f impossible"; return 1; }
        [[ -z $extra ]] || { echo "suivi de sprint : ajout hors des lignes de statut"; return 1; }
        found=$(select_lines -E "^\+[[:space:]]+$story_key: done$" "$added") || { echo "lecture du diff de $f impossible"; return 1; }
        [[ -n $found ]] || { echo "suivi de sprint : la story ne passe pas à done"; return 1; }
        ;;
      "$rule_stories_dir/$story_key.md")
        [[ $removed == "-Status: review" ]] || { echo "fichier de story : suppression autre que « Status: review »"; return 1; }
        found=$(select_lines -xF "+Status: done" "$added") || { echo "lecture du diff de $f impossible"; return 1; }
        [[ -n $found ]] || { echo "fichier de story : « Status: done » absent"; return 1; }
        ;;
      "$rule_stories_dir/deferred-work.md")
        [[ -z $removed ]] || { echo "deferred-work.md : ligne supprimée ou modifiée"; return 1; }
        ;;
      *)
        echo "fichier $f modifié hors de la règle du commit de statut"; return 1
        ;;
    esac
  done <<< "$files"
  return 0
}

# Une CI qui tourne n'est jamais une CI absente, même pendant l'amorçage. « amorçage » : aucun statut
# du workflow des contrôles sur la tête et aucun workflow sur la base ; le script lance le substitut.
#
# Seuls les statuts du workflow « checks » comptent. Gitea nomme un contexte « <workflow> / <job>
# (<événement>) », par exemple « checks / checks (pull_request) », et la clé de l'état d'un statut est
# « status » — « state » n'existe qu'au niveau combiné (constaté sur un vrai commit, story 3.16).
# Juger l'état combiné reviendrait à laisser n'importe quel autre workflow verrouiller la fusion :
# l'agent de parité (AD-16) commente sans bloquer, et son statut ne doit pas décider d'une fusion.
# La valeur de repli d'un statut sans état s'écrit en un seul mot : la boucle qui nomme les états
# fautifs découpe sur les espaces, et « sans état » y compterait pour deux (revue de la PR n° 52).
ci_gate() { # $1 réponse de l'état combiné de la CI, $2 1 si le workflow existe sur la base, sinon 0, $3 chemin du workflow
  local etats
  etats=$(jq -er '
      [ (.statuses // [])[]
        | select((.context // "") == "checks" or ((.context // "") | startswith("checks /")))
        | (.status // "sans-état") ]
      | join(" ")' "$1" 2>/dev/null) || return 2
  if [[ -z $etats ]]; then
    if [[ $2 == 1 ]]; then
      printf 'bloque\t%s existe sur la base : aucun statut du workflow « checks » sur la tête (story 3.16).\n' "$3"
    else
      printf "amorçage\t%s absent de la base : règle d'amorçage.\n" "$3"
    fi
    return 0
  fi
  if [[ " $etats " == *" pending "* ]]; then
    printf "bloque\ten cours sur la tête : relancer l'audit quand elle est terminée.\n"
  elif [[ $etats =~ ^(success )*success$ ]]; then
    printf 'passe\tverte sur la tête.\n'
  else
    # Les états fautifs sont nommés, les verts écartés : avec deux jobs, « success failure » se lisait
    # mal (constat de la revue de la PR n° 52). « cancelled », « skipped » ou « warning » bloquent
    # comme un échec, et aucun état inconnu n'est traité par omission.
    local fautifs="" etat
    for etat in $etats; do
      [[ $etat != success ]] || continue
      [[ " $fautifs " == *" $etat "* ]] || fautifs+="${fautifs:+ }$etat"
    done
    printf 'bloque\tétat %s sur la tête.\n' "$fautifs"
  fi
}

# jq -r écrit le titre brut : @tsv échapperait l'antislash, que read ne décoderait pas.
pr_title() { # $1 réponse de la PR
  jq -er '.title | strings' "$1" 2>/dev/null || return 2
}

merge_title() { # $1 réponse de la PR, $2 numéro de la PR, $3 fichier de sortie
  local title
  title=$(pr_title "$1") || return 2
  printf '%s (#%s)\n' "$title" "$2" > "$3" || return 2
}
