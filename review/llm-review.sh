#!/usr/bin/env bash
# Fait relire la spec d'une story, ou le diff d'une PR, par un LLM d'un autre fournisseur que l'auteur.
#
#   llm-review.sh --story <n.m> [--context <fichier>]    revue de spec, avant l'implémentation
#   llm-review.sh <numéro de PR> [--context <fichier>]   revue du code, verdict publié sur la PR
#
# AUTHOR_LLM=claude (défaut) → relecteur gemini-3.1-pro-high ; AUTHOR_LLM=gemini → claude-opus-4-6-thinking.
# Le relecteur applique le skill bmad-review dans une copie isolée hors du dépôt (worktree git),
# qui ne contient que les fichiers suivis. Son rapport doit citer un jeton de lecture aléatoire.
# Procédure : docs/procedures/llm-review.md
set -euo pipefail
set +x # même lancé avec bash -x, la trace s'arrête ici, avant la lecture du jeton
shopt -u patsub_replacement 2>/dev/null || true

script_name=llm-review
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/gitea.sh
. "$script_dir/lib/gitea.sh"

readonly reviewer_for_claude="gemini-3.1-pro-high"
readonly reviewer_for_gemini="claude-opus-4-6-thinking"
readonly review_timeout=900
readonly stories_dir="_bmad-output/implementation-artifacts"
readonly epics_file="_bmad-output/planning-artifacts/epics.md"
readonly usage="usage : llm-review.sh --story <n.m> [--context <fichier>] | llm-review.sh <numéro de PR> [--context <fichier>]"

require_tools
command -v agy >/dev/null 2>&1 || die "agy est introuvable : prérequis du poste de développement (AD-24)."
command -v timeout >/dev/null 2>&1 || die "timeout est introuvable."

story="" pr="" context_file=""
while (($#)); do
  case $1 in
    --story) (($# >= 2)) && [[ -z $story ]] || die "$usage"; story=$2; shift 2 ;;
    --context) (($# >= 2)) && [[ -z $context_file ]] || die "$usage"; context_file=$2; shift 2 ;;
    *) [[ -z $pr && $1 =~ ^[1-9][0-9]*$ ]] || die "$usage"; pr=$1; shift ;;
  esac
done
[[ -n $story || -n $pr ]] || die "$usage"
[[ -z $story || -z $pr ]] || die "$usage"
[[ -z $story || $story =~ ^[0-9]+\.[0-9]+[a-z]?$ ]] || die "numéro de story attendu, par exemple 0.6."
if [[ -n $context_file ]]; then
  [[ $context_file == /* ]] || context_file="$PWD/$context_file"
  [[ -s $context_file ]] || die "fichier de contexte absent ou vide : $context_file."
fi

case ${AUTHOR_LLM:-claude} in
  claude) model=$reviewer_for_claude ;;
  gemini) model=$reviewer_for_gemini ;;
  *) die "AUTHOR_LLM doit valoir claude ou gemini : le relecteur vient toujours d'un autre fournisseur." ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "à lancer dans le dépôt."
cd "$root"
check_origin

patterns_file=${PRIVATE_PATTERNS_FILE:-$root/docs/private/forbidden-patterns.txt}
[[ -f $patterns_file ]] || die "fichier de motifs absent : aucun envoi sans audit (docs/procedures/check-private.md)."

tmp=$(mktemp -d)
case "$tmp/" in
  "$root"/*) rm -rf "$tmp"; die "le dossier temporaire est dans le dépôt : définir TMPDIR hors du dépôt." ;;
esac
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

grep -vE '^[[:space:]]*(#|$)' "$patterns_file" > "$tmp/patterns" || true
contains_private() { # réussit si un des fichiers contient un motif privé
  [[ -s $tmp/patterns ]] || return 1
  local rc=0
  grep -qiF -f "$tmp/patterns" "$@" || rc=$?
  ((rc <= 1)) || die "vérification des motifs impossible."
  return "$rc"
}
if [[ -n $context_file ]] && contains_private "$context_file"; then
  die "le fichier de contexte contient un motif privé (contenu masqué) : rien n'est envoyé."
fi

# --- ce qui est relu -------------------------------------------------------------------------
base="" branch="" base_sha="" head_sha="" story_num=""
if [[ -n $pr ]]; then
  load_gitea_env "$root/.env"
  check_token_owner "$tmp/user.json"
  code=$(gitea_api GET "/repos/$gitea_canonical_repo/pulls/$pr" "$tmp/pr.json")
  [[ $code == 200 ]] || die "PR n° $pr illisible (HTTP $code) : $(forge_message "$tmp/pr.json")"
  pr_fields=$(jq -er '[.state, .base.ref, .head.ref, .head.sha] | @tsv' "$tmp/pr.json" 2>/dev/null) \
    || die "réponse de la forge illisible pour la PR n° $pr."
  IFS=$'\t' read -r pr_state base branch head_sha <<< "$pr_fields"
  [[ $pr_state == open ]] || die "la PR n° $pr n'est pas ouverte."
  [[ $head_sha =~ ^[0-9a-f]{40}$ ]] || die "SHA de tête de la PR n° $pr illisible."
  git fetch --quiet origin "$base" "$branch" 2>/dev/null || die "lecture des branches de la PR sur la forge impossible."
  base_sha=$(git rev-parse --verify --quiet "refs/remotes/origin/$base^{commit}") \
    || die "branche $base introuvable après lecture sur la forge."
  [[ $(git rev-parse --verify --quiet "refs/remotes/origin/$branch^{commit}" || true) == "$head_sha" ]] \
    || die "la branche $branch a bougé depuis la lecture de la PR : relancer la revue."
  changed=$(git diff --name-only "$base_sha...$head_sha") || die "liste des fichiers de la PR impossible."
  if grep -qvE '\.md$' <<< "$changed"; then
    lenses="edge-case-hunter, verification-gap"
  else
    lenses="structure, prose"
  fi
  content_name=REVIEW-DIFF.patch
  template="$root/scripts/llm-review-prompt.md"
  audit_range=("$base_sha..$head_sha")
  if [[ $branch =~ ^[a-z]+/([0-9]+)-([0-9]+[a-z]?)- ]]; then
    story_num="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  fi
else
  git fetch --quiet origin dev 2>/dev/null || die "lecture de dev sur la forge impossible."
  head_sha=$(git rev-parse --verify --quiet "refs/remotes/origin/dev^{commit}") || die "branche dev introuvable."
  lenses="adversarial, structure, prose"
  content_name=REVIEW-SPEC.md
  template="$root/scripts/llm-review-spec-prompt.md"
  audit_range=(-1 "$head_sha")
  story_num=$story
fi
[[ -s $template ]] || die "consigne absente : ${template#"$root"/}."

story_key=""
if [[ -n $story_num ]]; then
  story_key=$(grep -oE "^  ${story_num//./-}-[a-z0-9-]+:" "$root/$stories_dir/sprint-status.yaml" \
    | head -n 1 | tr -d ' :' || true)
fi
[[ -z $story || -n $story_key ]] || die "story $story absente du suivi de sprint."

# --- copie isolée, garde-fou, jeton de lecture -------------------------------------------------
worktree="$tmp/copie"
git worktree add --quiet --detach "$worktree" "$head_sha" 2>/dev/null || die "création de la copie isolée impossible."
for private in .env docs/private .pr-body.md; do
  [[ ! -e $worktree/$private ]] || die "la copie isolée contient $private : rien n'est envoyé."
done

PRIVATE_PATTERNS_FILE=$patterns_file "$root/scripts/check-private.sh" history "${audit_range[@]}" \
  || die "le garde-fou public/privé refuse le périmètre relu : rien n'est envoyé."

canary=$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')
[[ ${#canary} == 24 ]] || die "création du jeton de lecture impossible."
if [[ -n $pr ]]; then
  printf '# jeton-de-lecture: %s\n' "$canary" > "$worktree/$content_name"
  git diff "$base_sha...$head_sha" >> "$worktree/$content_name" || die "diff de la PR impossible."
else
  awk -v h="### Story $story :" 'index($0, h) == 1 { f = 1; print; next } f && /^##/ { exit } f { print }' \
    "$worktree/$epics_file" > "$tmp/spec.md"
  [[ -s $tmp/spec.md ]] || die "story $story introuvable dans epics.md sur dev."
  { printf '<!-- jeton-de-lecture: %s -->\n\n' "$canary"; cat "$tmp/spec.md"; } > "$worktree/$content_name"
fi

prompt=$(<"$template")
prompt=${prompt//'{{WORKTREE}}'/$worktree}
prompt=${prompt//'{{CONTENT}}'/$content_name}
prompt=${prompt//'{{SHA}}'/$head_sha}
prompt=${prompt//'{{LENSES}}'/$lenses}
prompt=${prompt//'{{PR}}'/$pr}
prompt=${prompt//'{{BRANCH}}'/$branch}
prompt=${prompt//'{{BASE}}'/$base}
prompt=${prompt//'{{STORY}}'/$story_num}
if [[ -n $context_file ]]; then
  printf -v prompt '%s\n\nPrécisions de l’auteur de la PR :\n%s\n' "$prompt" "$(<"$context_file")"
fi

# --- relecture ---------------------------------------------------------------------------------
printf '%s: relecture par %s (angles : %s), jusqu’à %s min…\n' "$script_name" "$model" "$lenses" "$((review_timeout / 60))" >&2
rc=0
(cd "$worktree" && timeout "$review_timeout" agy --print "$prompt" --add-dir "$worktree" --mode plan \
  --model "$model" --dangerously-skip-permissions --print-timeout 14m) > "$tmp/brut.md" 2> "$tmp/agy.err" || rc=$?
((rc == 0)) || die "le relecteur n'a pas abouti (code $rc, 124 = délai dépassé) : rien n'est publié."

status_out=$(git -C "$worktree" status --porcelain --untracked-files=all 2>/dev/null) \
  || die "lecture de l'état de la copie isolée impossible."
written=$(grep -vxF "?? $content_name" <<< "$status_out" | sed '/^$/d' || true)
if [[ -n $written ]]; then
  written_label=$(cut -c4- <<< "$written" | paste -sd ',' - | sed 's/,/, /g')
  printf '%s: fichiers créés ou modifiés par le relecteur dans la copie : %s\n' "$script_name" "$written_label" >&2
else
  written_label="aucun"
fi

jeton_line=$(grep -n -m 1 -F "JETON: $canary" "$tmp/brut.md" | cut -d: -f1 || true)
[[ -n $jeton_line ]] || die "le rapport ne cite pas le jeton de lecture : ce n'est pas une revue, rien n'est publié."
tail -n "+$jeton_line" "$tmp/brut.md" | tr -d '\r' > "$tmp/rapport.md"

verdict=""
if [[ -n $pr ]]; then
  last=$(grep -v '^[[:space:]]*$' "$tmp/rapport.md" | tail -n 1 || true)
  last=${last#"${last%%[![:space:]]*}"}
  case $last in
    "VERDICT: NON BLOQUANT"*) verdict=pass ;;
    "VERDICT: BLOQUANT"*) verdict=block ;;
    *) die "la dernière ligne du rapport n'est pas un verdict lisible : rien n'est publié." ;;
  esac
fi

if contains_private "$tmp/rapport.md"; then
  die "le rapport contient un motif privé (contenu masqué) : rien n'est publié ni écrit."
fi

# --- publication et trace ----------------------------------------------------------------------
# titres du rapport abaissés de deux niveaux, pour rester sous la section du fichier de story
sed -E 's/^(#{1,4}) /\1## /' "$tmp/rapport.md" > "$tmp/rapport-abaisse.md"

if [[ -n $pr ]]; then
  {
    printf 'llm-review sha=%s base=%s model=%s verdict=%s\n\n' "$head_sha" "$base" "$model" "$verdict"
    printf '_Revue par `scripts/llm-review.sh` : `agy --mode plan`, copie isolée hors du dépôt au SHA relu, sans `.env` ni `docs/private/` ; skill `bmad-review` appliqué par le relecteur (angles : %s, plus la couche propre au projet). Fichiers créés ou modifiés par le relecteur dans la copie : %s._\n\n' "$lenses" "$written_label"
    cat "$tmp/rapport.md"
  } > "$tmp/commentaire.md"
  jq -n --rawfile body "$tmp/commentaire.md" '{body: $body}' > "$tmp/commentaire.json" \
    || die "rapport illisible : texte UTF-8 attendu."
  code=$(gitea_api POST "/repos/$gitea_canonical_repo/issues/$pr/comments" "$tmp/publie.json" "$tmp/commentaire.json")
  [[ $code == 201 ]] || die "la forge refuse le commentaire (HTTP $code) : $(forge_message "$tmp/publie.json")"
  printf '%s: revue publiée sur la PR n° %s : verdict %s (%s, SHA %s)\n' "$script_name" "$pr" "$verdict" "$model" "${head_sha:0:7}"
  section="## Revue du code"
  {
    printf '### %s — `%s` — `%s` — verdict `%s`\n\n' "$(date +%d/%m/%Y)" "${head_sha:0:7}" "$model" "$verdict"
    printf 'Rapport publié en commentaire de la PR n° %s. Angles : %s, plus la couche propre au projet. Fichiers créés ou modifiés par le relecteur : %s.\n\n' "$pr" "$lenses" "$written_label"
    cat "$tmp/rapport-abaisse.md"
    printf '\n'
  } > "$tmp/bloc.md"
else
  cat "$tmp/rapport.md"
  section="## Revue de spec"
  {
    printf '### %s — `%s`, `bmad-review` (angles : %s), `dev` à `%s`\n\n' "$(date +%d/%m/%Y)" "$model" "$lenses" "${head_sha:0:7}"
    printf 'Fichiers créés ou modifiés par le relecteur : %s.\n\n' "$written_label"
    cat "$tmp/rapport-abaisse.md"
    printf '\n'
  } > "$tmp/bloc.md"
fi

story_file=""
[[ -z $story_key ]] || story_file="$root/$stories_dir/$story_key.md"
current_branch=$(git symbolic-ref --quiet --short HEAD || true)
if [[ -z $story_file ]]; then
  printf '%s: aucune story associée : fichier de story non mis à jour.\n' "$script_name" >&2
elif [[ -n $pr && $current_branch != "$branch" ]]; then
  printf '%s: la branche courante n’est pas %s : fichier de story non mis à jour.\n' "$script_name" "$branch" >&2
else
  if [[ ! -f $story_file ]]; then
    if [[ -n $pr ]]; then
      printf '%s: %s absent : fichier de story non mis à jour.\n' "$script_name" "${story_file#"$root"/}" >&2
      exit 0
    fi
    status=$(grep -E "^  $story_key:" "$root/$stories_dir/sprint-status.yaml" | head -n 1 | sed -E 's/^[^:]+:[[:space:]]*//' || true)
    title=$(head -n 1 "$tmp/spec.md" | sed 's/^### //')
    printf '# %s\n\nStatus: %s\n\nSpec : `%s`, story %s.\n\n## Revue de spec\n\n## Revue du code\n\n## Reporté\n' \
      "$title" "${status:-backlog}" "$epics_file" "$story" > "$story_file"
  fi
  grep -qxF "$section" "$story_file" || die "section « $section » absente de ${story_file#"$root"/}."
  # le rapport est inséré à la fin de la section, sans modifier ni supprimer de ligne existante :
  # le commit de statut done n'admet que des lignes ajoutées au fichier de story
  awk -v section="$section" -v block="$tmp/bloc.md" '
    function flush(  l) { if (last != "") print ""; while ((getline l < block) > 0) print l; close(block); done = 1 }
    $0 == section { inside = 1; print; last = $0; next }
    inside && /^## / { if (!done) flush(); inside = 0 }
    { print; last = $0 }
    END { if (inside && !done) flush() }
  ' "$story_file" > "$tmp/story.md" || die "mise à jour du fichier de story impossible."
  if { diff "$story_file" "$tmp/story.md" || true; } | grep -q '^<'; then
    die "la mise à jour supprimerait des lignes de ${story_file#"$root"/} : fichier inchangé."
  fi
  cat "$tmp/story.md" > "$story_file"
  printf '%s: rapport ajouté à %s, section « %s ».\n' "$script_name" "${story_file#"$root"/}" "${section#\#\# }" >&2
fi
