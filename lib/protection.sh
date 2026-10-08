# shellcheck shell=bash
# La règle commune de protection des branches, et sa comparaison avec ce que la forge rapporte.
#
# À charger par « . lib/protection.sh », après lib/config.sh et un config_load réussi au schéma 7.
# Dépendances : bash 4.3 ou plus, jq. Aucun appel à la forge : ce qui décide lit des fichiers, que le
# script (gitea/check-branch-protection.sh) remplit par l'API et que les tests remplissent à la main.
#
#   protection_expected <fichier>     écrit les valeurs attendues (JSON), tirées de workflow.config :
#                                     0 ; 2 si un champ manque (fichier d'avant le schéma 7)
#   protection_check_shapes <attendu> <dépôt> <règles> <clés>
#                                     0 si les trois réponses ont la forme relue ; 2 sinon, la réponse et
#                                     le champ nommés sur la sortie d'erreur
#   protection_compare <attendu> <dépôt> <règles> <clés>
#                                     affiche le verdict, et sur un écart chaque écart puis la liste des
#                                     réglages à poser dans l'interface, écran par écran : 0 conforme ;
#                                     1 écart ; 2 comparaison impossible
#
# La règle, ses valeurs fixes et leurs motifs : procedures/gitea-branches.md, « La règle commune ». Les
# libellés de l'interface sont ceux de Gitea 1.27.3 en français (options/locale/locale_fr-FR.json et
# templates/repo/settings/{protected_branch,options}.tmpl), recopiés tels quels, coquilles comprises
# (« Désactiver les poussés forcées »), seul le point final de deux cases à cocher ôté : la liste se lit en
# regard de l'écran.

# $1 = fichier à écrire
protection_expected() {
  local out=$1 base release base_push base_force release_push merge contexts outdated style
  config_get base forge.base || return 2
  config_get release forge.release-branch || return 2
  config_get base_push protection.base-push || return 2
  config_get base_force protection.base-force-push || return 2
  config_get release_push protection.release-push || return 2
  config_get merge protection.merge || return 2
  config_get contexts protection.status-contexts || return 2
  config_get outdated protection.block-outdated || return 2
  config_get style protection.release-merge-style || return 2
  jq -n --arg base "$base" --arg release "$release" --arg base_push "$base_push" --arg base_force "$base_force" \
    --arg release_push "$release_push" --arg merge "$merge" --arg contexts "$contexts" \
    --argjson outdated "$outdated" --arg style "$style" '
    def accounts: if . == "none" then null else split(" ") end;
    {
      branches: ([{name: $base, role: "base", push: ($base_push | accounts), force_push: ($base_force | accounts)}]
        + (if $release == "none" then [] else
            [{name: $release, role: "release", push: ($release_push | accounts), force_push: null}] end)),
      merge: ($merge | accounts),
      contexts: (if $contexts == "none" then null
        else $contexts | split(",") | map(gsub("^\\s+|\\s+$"; "")) end),
      block_outdated: $outdated,
      release_style: (if $style == "none" then null else $style end)
    }' > "$out" || return 2
}

# Les champs relus, et leur type JSON : une réponse qui en manque un vient d'une autre version de la forge,
# ou d'autre chose que la forge. Elle est illisible, jamais conforme.
readonly protection_rule_fields='{
  "enable_push": "boolean", "enable_push_whitelist": "boolean", "push_whitelist_usernames": "array",
  "push_whitelist_teams": "array", "push_whitelist_deploy_keys": "boolean",
  "enable_force_push": "boolean", "enable_force_push_allowlist": "boolean",
  "force_push_allowlist_usernames": "array", "force_push_allowlist_teams": "array",
  "force_push_allowlist_deploy_keys": "boolean",
  "enable_merge_whitelist": "boolean", "merge_whitelist_usernames": "array", "merge_whitelist_teams": "array",
  "enable_bypass_allowlist": "boolean", "enable_status_check": "boolean",
  "status_check_contexts": "array-or-null", "required_approvals": "number",
  "block_on_outdated_branch": "boolean", "block_admin_merge_override": "boolean",
  "require_signed_commits": "boolean", "protected_file_patterns": "string", "unprotected_file_patterns": "string"
}'
readonly protection_repo_fields='{
  "allow_merge_commits": "boolean", "allow_rebase": "boolean", "allow_rebase_explicit": "boolean",
  "allow_squash_merge": "boolean", "allow_fast_forward_only_merge": "boolean", "allow_manual_merge": "boolean",
  "default_merge_style": "string"
}'

# $1 attendu, $2 dépôt, $3 règles, $4 clés
protection_check_shapes() {
  local problems rc=0
  problems=$(jq -nr --slurpfile exp "$1" --slurpfile repo "$2" --slurpfile rules "$3" --slurpfile keys "$4" \
    --argjson rf "$protection_rule_fields" --argjson pf "$protection_repo_fields" '
    def typed($t): if $t == "array-or-null" then (type == "array" or type == "null") else type == $t end;
    def missing($obj; $fields): [$fields | to_entries[] | .key as $k | .value as $t
      | select(($obj | has($k) and (.[$k] | typed($t))) | not) | $k]
      | select(length > 0) | join(", ");
    ($exp[0].branches | map(.name)) as $names
    | if ($repo | length) != 1 or ($repo[0] | type) != "object" then "dépôt (GET /repos/<dépôt>) : un objet JSON attendu"
      else (missing($repo[0]; $pf) | "dépôt (GET /repos/<dépôt>) : champ absent ou mal typé : \(.)") end,
      if ($rules | length) != 1 or ($rules[0] | type) != "array" then "règles (GET /branch_protections) : une liste JSON attendue"
      else ($rules[0][] | if type != "object" or (.rule_name | type) != "string" then "règles : une entrée sans rule_name"
        elif (.rule_name as $n | $names | index($n)) then
          (.rule_name as $n | missing(.; $rf) | "règle « \($n) » : champ absent ou mal typé : \(.)")
        else empty end) end,
      if ($keys | length) != 1 or ($keys[0] | type) != "array" then "clés de déploiement (GET /keys) : une liste JSON attendue"
      else ($keys[0][] | select(type != "object" or (.id | type) != "number" or (.read_only | type) != "boolean")
        | "clés de déploiement : une entrée sans id ni read_only") end
    ' 2>/dev/null) || rc=$?
  if ((rc != 0)); then
    printf '%s\n' "réponse illisible : une des trois réponses n'est pas du JSON."
    return 2
  fi
  if [[ -n $problems ]]; then
    printf 'réponse illisible : %s\n' "$problems"
    return 2
  fi
  return 0
}

# Le programme de comparaison, à côté de cette bibliothèque.
protection_program=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protection.jq
readonly protection_program

# $1 attendu, $2 dépôt, $3 règles, $4 clés ; les réponses ont déjà passé protection_check_shapes
protection_compare() {
  local report rc=0
  report=$(jq -nr --slurpfile exp "$1" --slurpfile repo "$2" --slurpfile rules "$3" --slurpfile keys "$4" \
    -f "$protection_program") || rc=$?
  ((rc == 0)) || { printf 'comparaison impossible (jq, code %s).\n' "$rc"; return 2; }
  local verdict=${report%%$'\n'*}
  printf '%s\n' "${report#*$'\n'}"
  printf '%s\n' "limites : les protections d'étiquettes (tags) ne sont pas relues ; une autre branche durable sans règle n'est pas détectée ; la branche par défaut, les styles de mise à jour et les approbations au-delà du minimum ne sont pas jugés."
  case $verdict in
    CONFORME) return 0 ;;
    ECART) return 1 ;;
    *) printf 'comparaison impossible : verdict illisible.\n'; return 2 ;;
  esac
}
