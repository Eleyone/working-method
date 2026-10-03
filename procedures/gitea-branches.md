# Procédure — Branches protégées et styles de fusion

Méthode commune pour régler et **vérifier par l'API** la protection des branches et les styles de fusion d'un dépôt Gitea. Les réglages propres à chaque projet (ses branches, ses listes d'autorisation) vivent dans le projet ; ceux du dépôt commun lui-même sont à la fin. Les constats datés viennent du projet source (Gitea 1.27.3).

Dans les commandes, `<dépôt>` est le `forge.repo` du `workflow.config` du projet.

### Les contextes exigés

Le contexte d'un statut Gitea s'écrit `<workflow> / <job> (<événement>)` : le workflow des contrôles en pose deux selon ce qui l'a déclenché, `checks / checks (pull_request)` et `checks / checks (push)`. Le motif exigé est donc **`checks / checks*`**, un glob qui couvre les deux : nommer un seul événement bloquerait l'autre, et se tromper d'un caractère bloquerait toutes les fusions sans rien dire de plus qu'« en attente ».

Le réglage a été posé le 21/09/2026, après la première exécution verte : Gitea ne propose un contexte dans cette liste qu'une fois qu'il a été rapporté au moins une fois. La PR qui a introduit cette ligne a servi d'essai — elle ne pouvait se fusionner que si le motif correspondait vraiment.

Ce réglage change ce que la forge rapporte : depuis qu'il est posé, la tête d'une PR porte **deux** statuts, `checks / checks (pull_request)` vert et `checks / checks (push)` **ignoré** — le déclencheur `push` n'écoutant que les branches d'intégration et de publication. `verify-and-merge-pr.sh` a dû l'apprendre : un statut ignoré est écarté, mais ne remplace pas un run effectif (constaté en fusionnant la PR qui a introduit ce réglage).

Ce réglage est le second verrou sur la CI, côté forge. Le premier est `gates/verify-and-merge-pr.sh`, qui refuse de fusionner sans un run vert du workflow `ci.status-context` sur le SHA de tête (`verify-and-merge-pr.md`). Les deux disent la même chose à deux endroits : le script protège l'audit, la protection de branche protège l'interface et l'API. ⚠️ Le contexte exigé par la protection **fixe le nom** du workflow et du job de la CI : les deux se changent ensemble.

Modifier une règle par l'API (`PATCH /api/v1/repos/<dépôt>/branch_protections/<règle>`) : un champ imbriqué n'est pris en compte que si la requête porte aussi ses champs parents. Envoyé seul, `push_whitelist_deploy_keys: false` répond `200` sans rien changer ; il faut envoyer `enable_push`, `enable_push_whitelist` et `push_whitelist_usernames` avec lui, et de même `enable_force_push`, `enable_force_push_allowlist` et `force_push_allowlist_usernames` avec `force_push_allowlist_deploy_keys`. Une réponse `200` ne prouve donc rien : relire la règle.

## Pourquoi le style n'est pas fixé par branche

Gitea fixe les styles autorisés pour tout le dépôt. Les scripts imposent le style par l'API (`POST /api/v1/repos/<dépôt>/pulls/<numéro>/merge`), avec `head_commit_id` égal au SHA relu, pour que la fusion échoue si la tête a bougé :

- `verify-and-merge-pr` fusionne vers `forge.base` en `"Do": "squash"`, et refuse toute base égale à `forge.release-branch` ;
- la publication vers la branche de publication a son propre chemin, propre au projet (dans le projet source, des skills `release` et `hotfix` en `"Do": "fast-forward-only"`).

Réponses constatées de l'API de fusion :

| Situation | Réponse |
|---|---|
| Style non autorisé dans le dépôt | `405`, `<style> is not allowed an allowed merge style for this repository` |
| Fast-forward après divergence de la base | `500`, `Merge DivergingFastForwardOnly` : rien n'est fusionné |
| Juste après un déplacement de la base | `405` transitoire, `Please try again later` : réessayer, ce n'est pas un refus |

## Vérifier

Sans afficher le jeton : le fichier d'environnement est lu ligne par ligne, jamais avec `source`, les variables ne sont pas exportées, et le jeton passe à `curl` par l'entrée standard (voir `gitea-token.md`).

```bash
REPO=<dépôt>    # forge.repo du workflow.config
while IFS= read -r line; do
  case "$line" in
    GITEA_URL=*|GITEA_TOKEN=*) k=${line%%=*}; v=${line#*=}; v=${v%\"}; v=${v#\"}; declare "$k=$v" ;;
  esac
done < .env
api_get () {
  printf 'header = "Authorization: token %s"\n' "$GITEA_TOKEN" \
    | curl -sf -K - "${GITEA_URL%/}/api/v1$1"
}
api_get "/repos/$REPO" | jq '{allow_merge_commits, allow_rebase, allow_rebase_explicit,
  allow_squash_merge, allow_fast_forward_only_merge, allow_manual_merge, default_merge_style,
  allow_merge_update, allow_rebase_update, default_update_style,
  default_delete_branch_after_merge, default_branch}'
api_get "/repos/$REPO/branch_protections" | jq '.[] | {rule_name, enable_push,
  push_whitelist_usernames, push_whitelist_deploy_keys, enable_force_push,
  force_push_allowlist_usernames, force_push_allowlist_deploy_keys,
  merge_whitelist_usernames, enable_status_check, status_check_contexts, block_on_outdated_branch}'
api_get "/repos/$REPO/keys" | jq length
```

Chaque valeur doit correspondre aux réglages écrits par le projet, et la dernière commande afficher `0` tant qu'aucune clé de déploiement n'est prévue. ⛔ Une réponse `200` à une modification ne prouve rien : relire, puis **éprouver** — un push direct sur la branche protégée doit être refusé (`pre-receive hook declined`), et la branche rester à son SHA.

## Le dépôt commun lui-même

Réglé à sa création (story outillage-14, phase A, 03/10/2026) et vérifié par l'API à chaque changement :

| Réglage | Valeur |
|---|---|
| Visibilité | public (`private: false`) ; la forge exige toutefois une connexion pour lire (`REQUIRE_SIGNIN_VIEW`), d'où le miroir public (`github-mirror.md`) |
| Branche par défaut | `main`, seule branche durable |
| Styles de fusion | squash **seul** (`allow_merge_commits`, `allow_rebase`, `allow_rebase_explicit`, `allow_fast_forward_only_merge`, `allow_manual_merge` à `false`) ; branche supprimée après fusion |
| Protection de `main` | `enable_push: false`, `enable_force_push: false`, fusion réservée au compte propriétaire (`merge_whitelist_usernames`), contexte exigé `checks / checks*`, `block_on_outdated_branch: true`, 0 approbation |

La protection a été levée **une seule fois**, le 03/10/2026, le temps de pousser l'import de l'historique (15 secondes, réglages identiques avant et après, push direct et force-push refusés ensuite) : la trace complète est dans le suivi de la story outillage-14. Toute autre écriture sur `main` passe par une PR.

