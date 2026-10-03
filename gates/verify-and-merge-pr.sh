#!/usr/bin/env bash
# Audite les verrous de fusion d'une PR et, avec --merge, la fusionne en squash vers la base du projet
# (forge.base de workflow.config) si tous passent.
#
#   verify-and-merge-pr.sh <numéro de PR>           audit : affiche chaque verrou, ne fusionne rien
#   verify-and-merge-pr.sh <numéro de PR> --merge   fusion en squash, seulement si tous les verrous passent
#
# Code de sortie : 0 tous les verrous passent (fusion faite avec --merge) ; 1 au moins un verrou bloque ;
# 2 audit impossible, workflow.config refusé compris. Aucune option --force : force_merge et
# merge_when_checks_succeed ne sont jamais envoyés. Le script lit les objets git et l'API, et n'écrit
# jamais dans l'arbre de travail. Un verrou désactivé dans workflow.config s'affiche « inactif » : il
# ne bloque pas, et il ne se fait pas passer pour vert.
# Procédure : procedures/verify-and-merge-pr.md
set -euo pipefail
set +x # même lancé avec bash -x, la trace s'arrête ici, avant la lecture du jeton

script_name=verify-and-merge-pr
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/config.sh
. "$script_dir/../lib/config.sh"
# shellcheck source=../gitea/gitea.sh
. "$script_dir/../gitea/gitea.sh"
# shellcheck source=../lib/sprint.sh
. "$script_dir/../lib/sprint.sh"
# shellcheck source=merge-gates.sh
. "$script_dir/merge-gates.sh"
die() { printf '%s: %b\n' "$script_name" "$*" >&2; exit 2; } # audit impossible : code 2

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

config_project_root root || die "à lancer dans le dépôt."
cd "$root"
config_load "$root/workflow.config" || exit 2
config_get forge_base forge.base
config_get release_branch forge.release-branch
config_get convention sprint.convention
config_get status_file sprint.status-file
config_get stories_dir sprint.stories-dir
config_get exempt_paths review.exempt-paths
config_get review_report review.report
config_get guard_command guard.command
config_get guard_patterns guard.patterns-file
config_get ci_workflow ci.workflow
config_get ci_context ci.status-context
config_get ci_bootstrap ci.bootstrap
config_get checks_command checks.command
config_get forge_env_file forge.env-file
readonly forge_base release_branch convention status_file stories_dir exempt_paths review_report \
  guard_command guard_patterns ci_workflow ci_context ci_bootstrap checks_command forge_env_file
# Une valeur que l'outillage ne sait pas encore servir sort en 2, en nommant la story qui l'apporte.
[[ $review_report == pr-comment ]] \
  || die "review.report = $review_report : rapport de revue que l'outillage ne sait pas encore lire (story 8)."
rc=0
convention_reason=$(sprint_convention_served "$convention") || rc=$?
((rc != 2)) || die "$convention_reason"
gitea_configure
check_origin
[[ -x $script_dir/sprint-consistency.sh ]] || die "sprint-consistency.sh absent ou non exécutable à côté de ce script."
patterns_file=""
if [[ $guard_command != none ]]; then
  [[ -x $root/$guard_command ]] || die "$guard_command absent ou non exécutable (guard.command)."
  patterns_file=${PRIVATE_PATTERNS_FILE:-$root/$guard_patterns}
  require_patterns_file "$patterns_file" "aucune fusion sans audit"
fi

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

load_gitea_env "$root/$forge_env_file"
check_token_owner "$tmp/user.json"

blocked=0
report() { # état (passe, absent, inactif, bloque), verrou, détail
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
title=$(pr_title "$tmp/pr.json") || die "titre de la PR n° $pr illisible."
[[ $head_sha =~ ^[0-9a-f]{40}$ ]] || die "SHA de tête de la PR n° $pr illisible."

printf '%s: PR n° %s « %s », %s → %s, tête %s\n' "$script_name" "$pr" "$title" "$branch" "$base" "${head_sha:0:7}"

# --- verrou 1 : PR fusionnable ---------------------------------------------------------------
if [[ $merged == true || $state != open ]]; then
  report bloque "PR fusionnable" "PR $([[ $merged == true ]] && echo "déjà fusionnée" || echo "fermée") : rien à fusionner."
  printf '%s: au moins un verrou bloque.\n' "$script_name"
  exit 1
fi
base_out=$(base_gate "$base" "$forge_base" "$release_branch")
if [[ ${base_out%%$'\t'*} == bloque ]]; then
  report bloque "PR fusionnable" "${base_out#*$'\t'}"
elif [[ $draft == true ]]; then
  report bloque "PR fusionnable" "PR en brouillon."
elif [[ $mergeable != true ]]; then
  report bloque "PR fusionnable" "PR non fusionnable (conflit, ou branche en retard sur $forge_base)."
else
  report passe "PR fusionnable" "ouverte, pas en brouillon, fusionnable, base $forge_base."
fi

git fetch --quiet origin "$base" "$branch" 2>/dev/null || die "lecture des branches $base et $branch sur la forge impossible."
base_sha=$(git rev-parse --verify --quiet "refs/remotes/origin/$base^{commit}") || die "branche $base introuvable après lecture sur la forge."
[[ $(git rev-parse --verify --quiet "refs/remotes/origin/$branch^{commit}" || true) == "$head_sha" ]] \
  || die "la branche $branch a bougé depuis la lecture de la PR : relancer l'audit."
changed=$(git diff --name-only "$base_sha...$head_sha") || die "liste des fichiers de la PR impossible."
[[ -n $changed ]] || die "la PR n° $pr ne modifie aucun fichier."

story_num="" story_key=""
if [[ $convention == none ]]; then
  story_num=""
elif story_num=$(story_number_from_branch "$branch"); then
  # story absente, en double ou suivi illisible : pas de clé ; le verrou de suivi en donne la raison
  story_key=$(git show "$head_sha:$status_file" 2>/dev/null | sprint_story_key "$story_num") || story_key=""
else
  story_num=""
fi

# --- verrou 2 : revue LLM ---------------------------------------------------------------------
rc=0
review_exemption "$exempt_paths" "$changed" || rc=$?
((rc != 2)) || die "review.exempt-paths illisible par grep : exception documentaire indécidable."
if ((rc == 0)); then
  report passe "revue LLM" "exception documentaire : tous les fichiers correspondent à review.exempt-paths ($exempt_paths), revue non exigée."
else
  # la liste des commentaires d'une issue ignore limit et page (bogue connu de Gitea) : les rapports
  # sont lus dans la timeline de la PR, qui pagine, par pages de la taille maximale admise par la forge
  code=$(gitea_api GET "/settings/api" "$tmp/settings.json")
  [[ $code == 200 ]] || die "lecture des réglages de l'API impossible (HTTP $code) : $(forge_message "$tmp/settings.json")"
  page_size=$(jq -er '.max_response_items' "$tmp/settings.json" 2>/dev/null) || die "réglages de l'API illisibles."
  [[ $page_size =~ ^[1-9][0-9]*$ ]] || die "réglages de l'API illisibles."
  fetch_timeline_page() { # $1 numéro de page, $2 fichier de réponse
    local code
    code=$(gitea_api GET "/repos/$gitea_canonical_repo/issues/$pr/timeline?limit=$page_size&page=$1" "$2")
    [[ $code == 200 ]] || die "lecture de la timeline de la PR impossible (HTTP $code) : $(forge_message "$2")"
  }
  rc=0
  read_timeline_reports fetch_timeline_page "$gitea_user" "$page_size" "$max_timeline_pages" "$tmp/reviews.tsv" || rc=$?
  ((rc != 3)) || die "timeline de la PR plus longue que $max_timeline_pages pages : lecture des rapports incomplète."
  ((rc == 0)) || die "page de la timeline de la PR illisible."
  head_report=$(last_report "$tmp/reviews.tsv" "$head_sha" "$base") || die "lecture des rapports de revue impossible."
  parent_sha=$(git rev-parse --verify --quiet "$head_sha^" || true)
  parent_report=""
  if [[ -n $parent_sha ]]; then
    parent_report=$(last_report "$tmp/reviews.tsv" "$parent_sha" "$base") || die "lecture des rapports de revue impossible."
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
    elif reason=$(status_commit_ok "$parent_sha" "$head_sha" "$story_key" "$status_file" "$stories_dir"); then
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
if [[ $guard_command == none ]]; then
  report inactif "garde-fou" "désactivé (guard.command = none) : aucun garde-fou public/privé n'est lancé."
elif guard_out=$(PRIVATE_PATTERNS_FILE=$patterns_file "$root/$guard_command" history "$base_sha..$head_sha" 2>&1); then
  guard_ok=1
  report passe "garde-fou" "$guard_command history sur les commits de la PR, avec la liste des motifs."
else
  report bloque "garde-fou" "$guard_command refuse la PR :"
  indent <<< "$guard_out"
fi

# --- verrou 4 : CI ------------------------------------------------------------------------------
if [[ $ci_workflow == none ]]; then
  report inactif "CI" "désactivée (ci.workflow = none) : aucun statut de CI n'est exigé — ce n'est pas une CI verte."
else
  code=$(gitea_api GET "/repos/$gitea_canonical_repo/commits/$head_sha/status" "$tmp/status.json")
  [[ $code == 200 ]] || die "lecture de l'état de la CI impossible (HTTP $code) : $(forge_message "$tmp/status.json")"
  ci_on_base=0
  if git cat-file -e "$base_sha:$ci_workflow" 2>/dev/null; then ci_on_base=1; fi
  ci_out=$(ci_gate "$tmp/status.json" "$ci_on_base" "$ci_workflow" "$ci_context") || die "état de la CI illisible."
  ci_decision=${ci_out%%$'\t'*}
  ci_detail=${ci_out#*$'\t'}
  if [[ $ci_decision == passe || $ci_decision == bloque ]]; then
    report "$ci_decision" "CI" "$ci_detail"
  elif [[ $ci_bootstrap != true ]]; then
    # sans règle d'amorçage (ci.bootstrap = false), une CI absente n'a pas de substitut : elle bloque
    report bloque "CI" "$ci_workflow absent de la base et aucun statut sur la tête : ci.bootstrap = false, pas de substitut."
  else
    # règle d'amorçage : le substitut est le garde-fou déjà lancé, puis checks.command sur la tête
    substitute="garde-fou (verrou 3)"
    substitute_ok=$guard_ok
    [[ $guard_command != none ]] || { substitute="aucun garde-fou (guard.command = none)"; substitute_ok=1; }
    check_out=""
    if [[ $checks_command != none ]]; then
      checks_entry=${checks_command%% *}
      if git cat-file -e "$head_sha:$checks_entry" 2>/dev/null; then
        substitute="$substitute, $checks_command sur la tête"
        worktree="$tmp/copie"
        git worktree add --quiet --detach "$worktree" "$head_sha" 2>/dev/null || die "création de la copie de la tête impossible."
        # La copie n'a ni .tools/ ni .env, tous deux ignorés par git : les binaires épinglés viennent du
        # dépôt de travail (TOOLS_LOCAL_DIR), et les valeurs du projet de ses propres fichiers commités.
        # Sans cela, les contrôles n'y trouveraient pas leurs outils et le substitut bloquerait toute PR
        # (entrée reportée de la story 0.7 du projet source). La commande est découpée sur les espaces,
        # jamais évaluée par le shell.
        read -r -a checks_argv <<< "$checks_command"
        if ! check_out=$(cd "$worktree" && TOOLS_LOCAL_DIR="$root/.tools" "${checks_argv[@]}" 2>&1); then
          substitute_ok=0
        fi
      else
        substitute="$substitute ($checks_entry absent de la tête)"
      fi
    else
      substitute="$substitute, aucun contrôle (checks.command = none)"
    fi
    if ((substitute_ok)); then
      report absent "CI" "$ci_workflow absent de la base : règle d'amorçage, substitut réussi ($substitute)."
    else
      report bloque "CI" "$ci_workflow absent de la base : substitut d'amorçage en échec ($substitute)."
      [[ -z $check_out ]] || indent <<< "$check_out"
    fi
  fi
fi

# --- verrou 5 : suivi de sprint ---------------------------------------------------------------
if [[ $convention == none ]]; then
  report inactif "suivi de sprint" "désactivé (sprint.convention = none) : aucun suivi de sprint n'est contrôlé."
elif ! git cat-file -e "$base_sha:$status_file" 2>/dev/null && git cat-file -e "$head_sha:$status_file" 2>/dev/null; then
  report passe "suivi de sprint" "exemption d'amorçage : cette PR ajoute $status_file."
else
  consistency=("$script_dir/sprint-consistency.sh" --rev "$head_sha")
  label="contrôle global (branche sans numéro de story)"
  if [[ -n $story_num ]]; then
    consistency=("$script_dir/sprint-consistency.sh" --merge "$story_num" --rev "$head_sha")
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
merge_title "$tmp/pr-avant-fusion.json" "$pr" "$tmp/titre.txt" || die "titre de la PR n° $pr illisible."
: > "$tmp/patterns"
if [[ -n $patterns_file ]]; then
  rc=0
  grep -vE '^[[:space:]]*(#|$)' "$patterns_file" > "$tmp/patterns" 2>/dev/null || rc=$?
  ((rc <= 1)) || die "lecture du fichier de motifs impossible : rien n'est fusionné."
fi
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
