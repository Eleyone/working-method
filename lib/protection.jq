# Comparaison de la règle commune de protection des branches avec ce que la forge rapporte : le programme
# jq de protection_compare (lib/protection.sh), dans son propre fichier pour que les apostrophes des
# libellés de l'interface s'y écrivent telles quelles.
#
# Entrées (--slurpfile) : exp, les valeurs attendues (protection_expected) ; repo, GET /repos/<dépôt> ;
# rules, GET /repos/<dépôt>/branch_protections ; keys, GET /repos/<dépôt>/keys (toutes les pages).
# Sortie : une première ligne CONFORME ou ECART, lue par protection_compare, puis le rapport.
$exp[0] as $e | $repo[0] as $repo | $rules[0] as $rules | $keys[0] as $keys
| def users: (. // []) | map(ascii_downcase) | sort;
  def lst: if length == 0 then "(vide)" else join(", ") end;
  def show: if type == "array" then lst elif . == "" then "(vide)" elif . == null then "(absent)" else tostring end;
  def box: if . then "cochée" else "décochée" end;
  def q: "« " + . + " »";
  def push_mode($on; $list): (if ($on | not) then "Désactiver la soumission"
    elif $list then "Soumissions sur autorisation uniquement" else "Activer la soumission" end) | q;
  def force_mode($on; $list): (if ($on | not) then "Désactiver les poussés forcées"
    elif $list then "Soumission forcée sur autorisation uniquement" else "Activer les poussées forcées" end) | q;
  def merge_mode($list): (if $list then "Fusion sur autorisation uniquement" else "Activer la fusion" end) | q;
  def style_label: {merge: "Créer une révision de fusion", rebase: "Rebaser puis rattraper",
    "rebase-merge": "Rebaser puis créer une révision de fusion", squash: "Créer une révision de concaténation",
    "fast-forward-only": "Avance rapide uniquement", manual: "Fusionner manuellement"}[.] // .;
  # une vérification : champ de l'API, valeurs affichées, valeurs comparées
  def chk($field; $exp; $got; $ce; $cg): {field: $field, exp: ($exp | show), got: ($got | show), ok: ($ce == $cg)};
  def same($field; $exp; $got): chk($field; $exp; $got; $exp; $got);
  def item($label; $exp; $got; $checks): {label: $label, exp: $exp, got: $got, checks: $checks};
  # les réglages d'une règle, dans l'ordre de l'écran ; $r vaut null pour une règle absente
  def rule_items($b; $r):
    ($b.push != null) as $push | ($b.force_push != null) as $force | ($e.contexts != null) as $ctx
    | ($r // {}) as $g
    | [ (if $r == null then item("Motif de nom de branche protégé"; $b.name; null; []) else empty end),
        item("Liste des fichiers et motifs protégés"; "(vide)"; ($g.protected_file_patterns | show);
          [same("protected_file_patterns"; ""; $g.protected_file_patterns)]),
        item("Liste des fichiers et motifs exclus"; "(vide)"; ($g.unprotected_file_patterns | show);
          [same("unprotected_file_patterns"; ""; $g.unprotected_file_patterns)]),
        item("Soumission"; push_mode($push; $push); push_mode($g.enable_push; $g.enable_push_whitelist);
          [same("enable_push"; $push; $g.enable_push), same("enable_push_whitelist"; $push; $g.enable_push_whitelist)]),
        (if $push then
          item("Utilisateurs autorisés à pousser"; ($b.push | lst); ($g.push_whitelist_usernames // [] | lst);
            [chk("push_whitelist_usernames"; $b.push; $g.push_whitelist_usernames; ($b.push | users); ($g.push_whitelist_usernames | users))]),
          item("Équipes autorisées à pousser"; "(vide)"; ($g.push_whitelist_teams // [] | lst);
            [same("push_whitelist_teams"; []; $g.push_whitelist_teams // [])]),
          item("Clés de déploiement pouvant écrire autorisées à pousser"; "décochée"; ($g.push_whitelist_deploy_keys | box);
            [same("push_whitelist_deploy_keys"; false; $g.push_whitelist_deploy_keys)])
         else empty end),
        item("Exiger des révisions signées"; "décochée"; ($g.require_signed_commits | box);
          [same("require_signed_commits"; false; $g.require_signed_commits)]),
        item("Poussée forcée"; force_mode($force; $force); force_mode($g.enable_force_push; $g.enable_force_push_allowlist);
          [same("enable_force_push"; $force; $g.enable_force_push), same("enable_force_push_allowlist"; $force; $g.enable_force_push_allowlist)]),
        (if $force then
          item("Utilisateurs autorisés à pousser en force"; ($b.force_push | lst); ($g.force_push_allowlist_usernames // [] | lst);
            [chk("force_push_allowlist_usernames"; $b.force_push; $g.force_push_allowlist_usernames; ($b.force_push | users); ($g.force_push_allowlist_usernames | users))]),
          item("Équipes autorisées à pousser en force"; "(vide)"; ($g.force_push_allowlist_teams // [] | lst);
            [same("force_push_allowlist_teams"; []; $g.force_push_allowlist_teams // [])]),
          item("Clés de déploiement pouvant pousser autorisées à pousser en force"; "décochée"; ($g.force_push_allowlist_deploy_keys | box);
            [same("force_push_allowlist_deploy_keys"; false; $g.force_push_allowlist_deploy_keys)])
         else empty end),
        item("Minimum d'approbations requis"; "0"; ($g.required_approvals | show);
          [same("required_approvals"; 0; $g.required_approvals)]),
        item("Activer le Contrôle Qualité"; ($ctx | box); ($g.enable_status_check | box);
          [same("enable_status_check"; $ctx; $g.enable_status_check)]),
        (if $ctx then
          item("Motifs de vérification des statuts (un par ligne)"; ($e.contexts | join(" ; ")); ($g.status_check_contexts // [] | join(" ; ") | show);
            [chk("status_check_contexts"; $e.contexts; $g.status_check_contexts; ($e.contexts | sort); ($g.status_check_contexts // [] | sort))])
         else empty end),
        item("Fusion de demande d'ajout"; merge_mode(true); merge_mode($g.enable_merge_whitelist);
          [same("enable_merge_whitelist"; true; $g.enable_merge_whitelist)]),
        item("Utilisateurs autorisés à fusionner"; ($e.merge | lst); ($g.merge_whitelist_usernames // [] | lst);
          [chk("merge_whitelist_usernames"; $e.merge; $g.merge_whitelist_usernames; ($e.merge | users); ($g.merge_whitelist_usernames | users))]),
        item("Équipes autorisées à fusionner"; "(vide)"; ($g.merge_whitelist_teams // [] | lst);
          [same("merge_whitelist_teams"; []; $g.merge_whitelist_teams // [])]),
        item("Autoriser des utilisateurs et des équipes à contourner les restrictions de branche"; "décochée"; ($g.enable_bypass_allowlist | box);
          [same("enable_bypass_allowlist"; false; $g.enable_bypass_allowlist)]),
        item("Bloquer la fusion si la demande d'ajout est obsolète"; ($e.block_outdated | box); ($g.block_on_outdated_branch | box);
          [same("block_on_outdated_branch"; $e.block_outdated; $g.block_on_outdated_branch)]),
        item("Les administrateurs doivent respecter les règles de protection des branches"; "décochée"; ($g.block_admin_merge_override | box);
          [same("block_admin_merge_override"; false; $g.block_admin_merge_override)])
      ];
  def repo_items:
    ($e.release_style) as $s
    | [ ( [["allow_merge_commits", "merge"], ["allow_rebase", "rebase"], ["allow_rebase_explicit", "rebase-merge"],
           ["allow_squash_merge", "squash"], ["allow_fast_forward_only_merge", "fast-forward-only"],
           ["allow_manual_merge", "manual"]][]
          | .[0] as $f | .[1] as $style | ($style == "squash" or $style == $s) as $want
          | item("Styles de fusion — " + ($style | style_label); ($want | box); ($repo[$f] | box);
              [same($f; $want; $repo[$f])]) ),
        item("Méthode de fusion par défaut"; ("squash" | style_label | q); ($repo.default_merge_style | style_label | q);
          [same("default_merge_style"; "squash"; $repo.default_merge_style)])
      ];
  def ecarts($who; $items): [$items[].checks[] | select(.ok | not) | "\($who) : \(.field) : lu \(.got), attendu \(.exp)"];
  def lines($items; $marks): [$items[] | "  - \(.label) : \(.exp)"
    + (if $marks and ([.checks[] | select(.ok | not)] | length) > 0 then "  ← à changer (lu : \(.got))" else "" end)];

  ($e.branches | map(.name)) as $names
  | [ ( $e.branches[] as $b
      | ([$rules[] | select(.rule_name == $b.name)] | first) as $r
      | if $r == null then
          {ecarts: ["règle « \($b.name) » : absente"],
           screen: (["Paramètres → Branches → Protection de branche → « Ajouter une nouvelle règle »"]
             + lines(rule_items($b; null); false) + ["  → « Enregistrer la règle »"])}
        else rule_items($b; $r) as $items | ecarts("règle « \($b.name) »"; $items) as $ec
          | if ($ec | length) == 0 then empty else
              {ecarts: $ec,
               screen: (["Paramètres → Branches → Protection de branche → règle « \($b.name) » → « Éditer »"]
                 + lines($items; true) + ["  → « Enregistrer la règle »"])} end
        end ),
      ( $rules[] | select(.rule_name as $n | $names | index($n) | not)
        | {ecarts: ["règle « \(.rule_name) » : en trop (ni forge.base ni forge.release-branch)"],
           screen: ["Paramètres → Branches → Protection de branche → règle « \(.rule_name) » → « Supprimer la règle »"]} ),
      ( repo_items as $items | ecarts("dépôt"; $items) as $ec
        | if ($ec | length) == 0 then empty else
            {ecarts: $ec, screen: (["Paramètres → Dépôt → Paramètres avancés → Demandes d'ajout"] + lines($items; true) + ["  → « Appliquer »"])} end ),
      ( $keys[] | select(.read_only | not)
        | {ecarts: ["clé de déploiement n° \(.id) : read_only : lu false, attendu true"],
           screen: ["Paramètres → Clés de déploiement → clé n° \(.id) : la supprimer ; si elle sert encore, la recréer sans cocher « Activer l'accès en écriture »"]} )
    ] as $found
  | ([$keys[] | select(.read_only)] | length) as $ro
  | (if $ro == 0 then "aucune clé de déploiement en lecture seule."
     elif $ro == 1 then "1 clé de déploiement en lecture seule : sans droit de pousser, non signalée."
     else "\($ro) clés de déploiement en lecture seule : sans droit de pousser, non signalées." end) as $ro_line
  | if ($found | length) == 0 then
      "CONFORME",
      "conforme : " + ([$e.branches[] | "règle « \(.name) »"] | join(", "))
        + (if ($e.branches | length) == 1 then " (sans branche de publication)" else "" end)
        + ", styles de fusion, clés de déploiement.",
      $ro_line
    else
      "ECART",
      "écarts (\([$found[].ecarts[]] | length)) :",
      ($found[].ecarts[] | "  écart : " + .),
      "",
      "Réglages à poser dans l'interface de la forge, écran par écran (libellés de Gitea 1.27 en français) ; puis relancer ce contrôle, dont la relecture fait foi :",
      ($found | to_entries[] | "", "Écran \(.key + 1) — \(.value.screen[0])", .value.screen[1:][]),
      "",
      $ro_line
    end
