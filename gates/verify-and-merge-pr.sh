#!/usr/bin/env bash
# Audite les verrous de fusion d'une PR et, avec --merge, la fusionne en squash vers dev si tous passent.
#
#   verify-and-merge-pr.sh <numéro de PR>           audit : affiche chaque verrou, ne fusionne rien
#   verify-and-merge-pr.sh <numéro de PR> --merge   fusion en squash, seulement si tous les verrous passent
#
# Code de sortie : 0 tous les verrous passent (fusion faite avec --merge) ; 1 au moins un verrou bloque ;
# 2 audit impossible. Aucune option --force : force_merge et merge_when_checks_succeed ne sont jamais
# envoyés. Le script lit les objets git et l'API, et n'écrit jamais dans l'arbre de travail.
# Procédure : docs/procedures/verify-and-merge-pr.md
set -euo pipefail
set +x # même lancé avec bash -x, la trace s'arrête ici, avant la lecture du jeton

script_name=verify-and-merge-pr
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/gitea.sh
. "$script_dir/lib/gitea.sh"
die() { printf '%s: %b\n' "$script_name" "$*" >&2; exit 2; } # audit impossible : code 2

readonly stories_dir="_bmad-output/implementation-artifacts"
readonly status_file="$stories_dir/sprint-status.yaml"
readonly ci_workflow=".gitea/workflows/checks.yaml"
readonly max_timeline_pages=100
readonly usage="usage : verify-and-merge-pr.sh <numéro de PR> [--merge]"

require_tools

pr="" merge=""
while (($#)); do
  case $1 in
    --merge) [[ -z $merge ]] || die "$usage"; merge=1; shift ;;
    *) [[ -z $pr && $1 =~ ^[1-9][0-9]*$ ]] || die "$usage"; pr=$1; shift ;;
  esac
done
[[ -n $pr ]] || die "$usage"

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "à lancer dans le dépôt."
cd "$root"
check_origin
for tool in check-private sprint-consistency; do
  [[ -x $root/scripts/$tool.sh ]] || die "scripts/$tool.sh absent ou non exécutable."
done
patterns_file=${PRIVATE_PATTERNS_FILE:-$root/docs/private/forbidden-patterns.txt}
require_patterns_file "$patterns_file" "aucune fusion sans audit"

tmp=$(mktemp -d)
worktree=""
cleanup() {
  if [[ -n $worktree ]]; then
    git -C "$root" worktree remove --force "$worktree" >/dev/null 2>&1 || true
    git -C "$root" worktree prune >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

load_gitea_env "$root/.env"
check_token_owner "$tmp/user.json"

blocked=0
report() { # état (passe, absent, bloque), verrou, détail
  printf '  %-7s %-16s %b\n' "$1" "$2" "$3"
  [[ $1 != bloque ]] || blocked=1
}
indent() { sed 's/^/            /'; }

# --- lecture de la PR ------------------------------------------------------------------------
read_pr() { # $1 fichier de réponse
  local code
  code=$(gitea_api GET "/repos/$gitea_canonical_repo/pulls/$pr" "$1")
  [[ $code == 200 ]] || die "PR n° $pr illisible (HTTP $code) : $(forge_message "$1")"
}
read_pr "$tmp/pr.json"
fields=$(jq -er '[.state, (.draft | tostring), (.mergeable | tostring), (.merged | tostring), .base.ref, .head.ref, .head.sha] | @tsv' "$tmp/pr.json" 2>/dev/null) \
  || die "réponse de la forge illisible pour la PR n° $pr."
IFS=$'\t' read -r state draft mergeable merged base branch head_sha <<< "$fields"
# le titre est lu seul, en texte brut : @tsv échapperait l'antislash, que read ne décoderait pas
title=$(jq -er '.title | strings' "$tmp/pr.json" 2>/dev/null) || die "titre de la PR n° $pr illisible."
[[ $head_sha =~ ^[0-9a-f]{40}$ ]] || die "SHA de tête de la PR n° $pr illisible."

printf '%s: PR n° %s « %s », %s → %s, tête %s\n' "$script_name" "$pr" "$title" "$branch" "$base" "${head_sha:0:7}"

# --- verrou 1 : PR fusionnable ---------------------------------------------------------------
if [[ $merged == true || $state != open ]]; then
  report bloque "PR fusionnable" "PR $([[ $merged == true ]] && echo "déjà fusionnée" || echo "fermée") : rien à fusionner."
  printf '%s: au moins un verrou bloque.\n' "$script_name"
  exit 1
fi
if [[ $base == main ]]; then
  report bloque "PR fusionnable" "base main : la publication passe par le skill release, un correctif de production par le skill hotfix."
elif [[ $base != dev ]]; then
  report bloque "PR fusionnable" "base $base refusée : seule dev est admise."
elif [[ $draft == true ]]; then
  report bloque "PR fusionnable" "PR en brouillon."
elif [[ $mergeable != true ]]; then
  report bloque "PR fusionnable" "PR non fusionnable (conflit, ou branche en retard sur dev)."
else
  report passe "PR fusionnable" "ouverte, pas en brouillon, fusionnable, base dev."
fi

git fetch --quiet origin "$base" "$branch" 2>/dev/null || die "lecture des branches $base et $branch sur la forge impossible."
base_sha=$(git rev-parse --verify --quiet "refs/remotes/origin/$base^{commit}") || die "branche $base introuvable après lecture sur la forge."
[[ $(git rev-parse --verify --quiet "refs/remotes/origin/$branch^{commit}" || true) == "$head_sha" ]] \
  || die "la branche $branch a bougé depuis la lecture de la PR : relancer l'audit."
changed=$(git diff --name-only "$base_sha...$head_sha") || die "liste des fichiers de la PR impossible."
[[ -n $changed ]] || die "la PR n° $pr ne modifie aucun fichier."

story_num="" story_key=""
if [[ $branch =~ ^[a-z]+/([0-9]+)-([0-9]+[a-z]?)- ]]; then
  story_num="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  story_key=$(git show "$head_sha:$status_file" 2>/dev/null \
    | grep -oE "^[[:space:]]+${story_num//./-}-[a-z0-9-]+:" | head -n 1 | tr -d ' \t:' || true)
fi

# --- règle du commit de statut ---------------------------------------------------------------
# Le commit de tête, seul après le SHA relu, ne change que les lignes de statut (story review → done,
# last_updated, epic → done) et n'ajoute par ailleurs que des lignes au fichier de story et à
# deferred-work.md. Affiche la raison d'un refus.
status_commit_ok() { # $1 SHA relu, $2 SHA de tête
  local reviewed=$1 head=$2 files f diff_out removed added
  [[ $(git rev-list --count "$reviewed..$head") == 1 ]] || { echo "plus d'un commit après le SHA relu"; return 1; }
  [[ -n $story_key ]] || { echo "aucune story associée à la branche"; return 1; }
  files=$(git diff --name-only "$reviewed" "$head") || { echo "diff du commit de tête illisible"; return 1; }
  while IFS= read -r f; do
    [[ -n $f ]] || continue
    # le diff est lu d'abord : un échec de git diff refuse la règle au lieu de donner une liste vide
    diff_out=$(git diff -U0 "$reviewed" "$head" -- "$f") || { echo "diff de $f illisible"; return 1; }
    removed=$(grep -E '^-' <<< "$diff_out" | grep -vE '^---( |$)' || true)
    added=$(grep -E '^\+' <<< "$diff_out" | grep -vE '^\+\+\+( |$)' || true)
    case $f in
      "$status_file")
        if grep -vE "^-[[:space:]]+$story_key: review$|^-last_updated: |^-[[:space:]]+epic-[0-9]+: [a-z-]+$" <<< "$removed" | grep -q .; then
          echo "suivi de sprint : suppression hors des lignes de statut"; return 1
        fi
        if grep -vE "^\+[[:space:]]+$story_key: done$|^\+last_updated: |^\+[[:space:]]+epic-[0-9]+: done$" <<< "$added" | grep -q .; then
          echo "suivi de sprint : ajout hors des lignes de statut"; return 1
        fi
        grep -qE "^\+[[:space:]]+$story_key: done$" <<< "$added" || { echo "suivi de sprint : la story ne passe pas à done"; return 1; }
        ;;
      "$stories_dir/$story_key.md")
        [[ $removed == "-Status: review" ]] || { echo "fichier de story : suppression autre que « Status: review »"; return 1; }
        grep -qxF "+Status: done" <<< "$added" || { echo "fichier de story : « Status: done » absent"; return 1; }
        ;;
      "$stories_dir/deferred-work.md")
        [[ -z $removed ]] || { echo "deferred-work.md : ligne supprimée ou modifiée"; return 1; }
        ;;
      *)
        echo "fichier $f modifié hors de la règle du commit de statut"; return 1
        ;;
    esac
  done <<< "$files"
  return 0
}

# --- verrou 2 : revue LLM ---------------------------------------------------------------------
if ! grep -qv '^_bmad-output/' <<< "$changed"; then
  report passe "revue LLM" "exception documentaire : tous les fichiers sont sous _bmad-output/, revue non exigée."
else
  # la liste des commentaires d'une issue ignore limit et page (bogue connu de Gitea) : les rapports
  # sont lus dans la timeline de la PR, qui pagine, par pages de la taille maximale admise par la forge
  code=$(gitea_api GET "/settings/api" "$tmp/settings.json")
  [[ $code == 200 ]] || die "lecture des réglages de l'API impossible (HTTP $code) : $(forge_message "$tmp/settings.json")"
  page_size=$(jq -er '.max_response_items' "$tmp/settings.json" 2>/dev/null) || die "réglages de l'API illisibles."
  [[ $page_size =~ ^[1-9][0-9]*$ ]] || die "réglages de l'API illisibles."
  : > "$tmp/reviews.tsv"
  page=1
  while :; do
    ((page <= max_timeline_pages)) \
      || die "timeline de la PR plus longue que $max_timeline_pages pages : lecture des rapports incomplète."
    code=$(gitea_api GET "/repos/$gitea_canonical_repo/issues/$pr/timeline?limit=$page_size&page=$page" "$tmp/timeline.json")
    [[ $code == 200 ]] || die "lecture de la timeline de la PR impossible (HTTP $code) : $(forge_message "$tmp/timeline.json")"
    # au-delà de la dernière page, la forge répond null et non une liste vide
    count=$(jq -e 'if type == "array" then length elif type == "null" then 0 else error end' "$tmp/timeline.json" 2>/dev/null) \
      || die "page de la timeline de la PR illisible."
    jq -r --arg u "$gitea_user" \
      '(. // [])[] | select(.type == "comment" and .user.login == $u) | ((.body // "") | split("\n")[0]) | select(startswith("llm-review "))' \
      "$tmp/timeline.json" >> "$tmp/reviews.tsv" || die "timeline de la PR illisible."
    ((count == page_size)) || break
    page=$((page + 1))
  done
  last_report() { # $1 SHA : dernière ligne llm-review pour ce SHA et cette base, champs comparés à l'identique
    awk -v sha="sha=$1" -v base="base=$base" '
      NF == 5 && $1 == "llm-review" && $2 == sha && $3 == base && $4 ~ /^model=./ && ($5 == "verdict=pass" || $5 == "verdict=block") { last = $0 }
      END { if (last != "") print last }
    ' "$tmp/reviews.tsv"
  }
  head_report=$(last_report "$head_sha") || die "lecture des rapports de revue impossible."
  parent_sha=$(git rev-parse --verify --quiet "$head_sha^" || true)
  parent_report=""
  if [[ -n $parent_sha ]]; then
    parent_report=$(last_report "$parent_sha") || die "lecture des rapports de revue impossible."
  fi
  if [[ -n $head_report ]]; then
    model=${head_report#*model=}; model=${model%% *}
    if [[ $head_report == *verdict=pass ]]; then
      report passe "revue LLM" "rapport pass sur la tête ($model)."
    else
      report bloque "revue LLM" "dernier rapport sur la tête : block ($model)."
    fi
  elif [[ -n $parent_report ]]; then
    model=${parent_report#*model=}; model=${model%% *}
    if [[ $parent_report != *verdict=pass ]]; then
      report bloque "revue LLM" "dernier rapport sur le parent de la tête : block ($model)."
    elif reason=$(status_commit_ok "$parent_sha" "$head_sha"); then
      report passe "revue LLM" "rapport pass sur ${parent_sha:0:7} ($model) ; le commit de tête respecte la règle du commit de statut."
    else
      report bloque "revue LLM" "rapport pass sur ${parent_sha:0:7}, mais le commit de tête sort de la règle du commit de statut ($reason) : nouvelle revue exigée."
    fi
  else
    report bloque "revue LLM" "aucun rapport llm-review sur la tête ${head_sha:0:7} ni sur son parent."
  fi
fi

# --- verrou 3 : garde-fou public/privé --------------------------------------------------------
guard_ok=0
if guard_out=$(PRIVATE_PATTERNS_FILE=$patterns_file "$root/scripts/check-private.sh" history "$base_sha..$head_sha" 2>&1); then
  guard_ok=1
  report passe "garde-fou" "check-private.sh history sur les commits de la PR, avec la liste des motifs."
else
  report bloque "garde-fou" "check-private.sh refuse la PR :"
  indent <<< "$guard_out"
fi

# --- verrou 4 : CI ------------------------------------------------------------------------------
code=$(gitea_api GET "/repos/$gitea_canonical_repo/commits/$head_sha/status" "$tmp/status.json")
[[ $code == 200 ]] || die "lecture de l'état de la CI impossible (HTTP $code) : $(forge_message "$tmp/status.json")"
ci_fields=$(jq -er '[.state // "", (.total_count // 0 | tostring)] | @tsv' "$tmp/status.json" 2>/dev/null) \
  || die "état de la CI illisible."
IFS=$'\t' read -r ci_state ci_total <<< "$ci_fields"
if ((ci_total > 0)) && [[ $ci_state == success ]]; then
  report passe "CI" "verte sur la tête."
elif ((ci_total > 0)) && [[ $ci_state == pending ]]; then
  # même pendant l'amorçage : une CI qui tourne n'est pas une CI absente
  report bloque "CI" "en cours sur la tête : relancer l'audit quand elle est terminée."
elif ((ci_total > 0)); then
  report bloque "CI" "état $ci_state sur la tête."
elif git cat-file -e "$base_sha:$ci_workflow" 2>/dev/null; then
  report bloque "CI" "$ci_workflow existe sur la base : CI absente sur la tête, absent bloque (story 3.16)."
else
  # règle d'amorçage : le substitut est le garde-fou déjà lancé, puis scripts/check.sh sur la tête s'il existe
  substitute="check-private.sh history (verrou garde-fou)"
  substitute_ok=$guard_ok
  check_out=""
  if git cat-file -e "$head_sha:scripts/check.sh" 2>/dev/null; then
    substitute="$substitute, scripts/check.sh sur la tête"
    worktree="$tmp/copie"
    git worktree add --quiet --detach "$worktree" "$head_sha" 2>/dev/null || die "création de la copie de la tête impossible."
    if ! check_out=$(cd "$worktree" && scripts/check.sh 2>&1); then
      substitute_ok=0
    fi
  fi
  if ((substitute_ok)); then
    report absent "CI" "$ci_workflow absent de la base : règle d'amorçage, substitut réussi ($substitute)."
  else
    report bloque "CI" "$ci_workflow absent de la base : substitut d'amorçage en échec ($substitute)."
    [[ -z $check_out ]] || indent <<< "$check_out"
  fi
fi

# --- verrou 5 : suivi de sprint ---------------------------------------------------------------
if ! git cat-file -e "$base_sha:$status_file" 2>/dev/null && git cat-file -e "$head_sha:$status_file" 2>/dev/null; then
  report passe "suivi de sprint" "exemption d'amorçage : cette PR ajoute $status_file."
else
  consistency=("$root/scripts/sprint-consistency.sh" --rev "$head_sha")
  label="contrôle global (branche sans numéro de story)"
  if [[ -n $story_num ]]; then
    consistency=("$root/scripts/sprint-consistency.sh" --merge "$story_num" --rev "$head_sha")
    label="story $story_num à done"
  fi
  if sprint_out=$("${consistency[@]}" 2>&1); then
    report passe "suivi de sprint" "$label : cohérent."
  else
    report bloque "suivi de sprint" "$label :"
    indent <<< "$sprint_out"
  fi
fi

# --- résultat et fusion -----------------------------------------------------------------------
if ((blocked)); then
  refusal=""
  [[ -z $merge ]] || refusal=" : rien n'est fusionné"
  printf '%s: au moins un verrou bloque%s.\n' "$script_name" "$refusal"
  exit 1
fi
if [[ -z $merge ]]; then
  printf '%s: tous les verrous passent. Fusion possible avec --merge.\n' "$script_name"
  exit 0
fi

# la tête n'a pas bougé pendant l'audit
read_pr "$tmp/pr-avant-fusion.json"
[[ $(jq -r '.head.sha' "$tmp/pr-avant-fusion.json") == "$head_sha" ]] || die "la tête de la PR a bougé pendant l'audit : relancer."

# chaque commande a son propre arrêt : un bloc { … } || die suspendrait set -e pour tout le bloc
subjects=$(git log --reverse --format='- %s' "$base_sha..$head_sha") || die "lecture des commits de la PR impossible."
[[ -n $subjects ]] || die "aucun commit à fusionner entre la base et la tête."
trailers=$(git log --format='%(trailers:key=Co-Authored-By)' "$base_sha..$head_sha") || die "lecture des lignes Co-Authored-By impossible."
trailers=$(sed '/^$/d' <<< "$trailers" | sort -u)
printf '%s\n' "$subjects" > "$tmp/message.txt"
if [[ -n $trailers ]]; then printf '\n%s\n' "$trailers" >> "$tmp/message.txt"; fi
printf '%s (#%s)\n' "$title" "$pr" > "$tmp/titre.txt"
grep -vE '^[[:space:]]*(#|$)' "$patterns_file" > "$tmp/patterns" || true
if [[ -s $tmp/patterns ]]; then
  rc=0
  grep -qiF -f "$tmp/patterns" "$tmp/titre.txt" "$tmp/message.txt" || rc=$?
  ((rc != 0)) || { printf '%s: le message de fusion contient un motif privé (contenu masqué) : rien n'"'"'est fusionné.\n' "$script_name"; exit 1; }
  ((rc == 1)) || die "vérification du message de fusion impossible."
fi

jq -n --arg h "$head_sha" --rawfile titre "$tmp/titre.txt" --rawfile message "$tmp/message.txt" \
  '{Do: "squash", head_commit_id: $h, MergeTitleField: ($titre | rtrimstr("\n")), MergeMessageField: $message, delete_branch_after_merge: true}' \
  > "$tmp/fusion.json" || die "préparation de la fusion impossible."
code=$(gitea_api POST "/repos/$gitea_canonical_repo/pulls/$pr/merge" "$tmp/fusion-reponse.json" "$tmp/fusion.json")
[[ $code == 200 ]] || { printf '%s: la forge refuse la fusion (HTTP %s) : %s\n' "$script_name" "$code" "$(forge_message "$tmp/fusion-reponse.json")"; exit 1; }
read_pr "$tmp/pr-apres-fusion.json"
[[ $(jq -r '.merged' "$tmp/pr-apres-fusion.json") == true ]] || die "fusion annoncée mais la PR n'apparaît pas fusionnée : vérifier sur la forge."
printf '%s: PR n° %s fusionnée en squash vers %s : %s ; branche %s supprimée.\n' "$script_name" "$pr" "$base" \
  "$(jq -r '.merge_commit_sha // "" | .[0:7]' "$tmp/pr-apres-fusion.json")" "$branch"
