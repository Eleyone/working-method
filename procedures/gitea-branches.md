# Procédure — Branches protégées et styles de fusion

Méthode commune pour régler et **vérifier par l'API** la protection des branches et les styles de fusion d'un dépôt Gitea. Les réglages propres à chaque projet (ses branches, ses listes d'autorisation) vivent dans le projet ; ceux du dépôt commun lui-même sont à la fin. Les constats datés viennent du projet source (Gitea 1.27.3).

Dans les commandes, `<dépôt>` est le `forge.repo` du `workflow.config` du projet.

## La règle commune

Posée le 08/10/2026 pour tous les projets qui consomment le dépôt commun (calculette#fix-protection-branches-dev-master) :
la protection des branches est un **réglage commun par défaut**, dont chaque projet ne déclare que ses
valeurs propres, dans la section `[protection]` de son `workflow.config` (schéma 7, `workflow-config.md`).
Le contrôle `gitea/check-branch-protection.sh` la relit par l'API et la compare (« Vérifier », ci-dessous).

### Les branches couvertes

**Une règle par branche, au nom exact** : `forge.base`, et `forge.release-branch` quand le projet en a une.
Pas de joker : une règle `release/*` protégerait aussi les branches que poussent les agents, et bloquerait
sans rien dire ; une règle `de*` qui couvre `dev` n'en tient pas lieu. ⛔ Une règle sur **toute autre**
branche est un **écart** (code `1`), à supprimer (décision I du 08/10/2026).

### Ce que le projet déclare

| Champ de `workflow.config` | Champs de l'API (`GET /repos/<dépôt>/branch_protections`) | Libellé de l'interface |
|---|---|---|
| `protection.base-push` | règle de `forge.base` : `enable_push`, `enable_push_whitelist`, `push_whitelist_usernames` | *Soumission* : « Désactiver la soumission » (`none`) ou « Soumissions sur autorisation uniquement », *Utilisateurs autorisés à pousser* |
| `protection.base-force-push` | règle de `forge.base` : `enable_force_push`, `enable_force_push_allowlist`, `force_push_allowlist_usernames` | *Poussée forcée* : « Désactiver les poussés forcées » (`none`) ou « Soumission forcée sur autorisation uniquement », *Utilisateurs autorisés à pousser en force* |
| `protection.release-push` | règle de `forge.release-branch` : `enable_push`, `enable_push_whitelist`, `push_whitelist_usernames` | idem, sur la règle de la branche de publication |
| `protection.merge` | les deux règles : `enable_merge_whitelist: true`, `merge_whitelist_usernames` | *Fusion de demande d'ajout* : « Fusion sur autorisation uniquement », *Utilisateurs autorisés à fusionner* |
| `protection.status-contexts` | les deux règles : `enable_status_check`, `status_check_contexts` | *Activer le Contrôle Qualité*, *Motifs de vérification des statuts* |
| `protection.block-outdated` | les deux règles : `block_on_outdated_branch` | *Bloquer la fusion si la demande d'ajout est obsolète* |

« Pas de push direct, pas de push forcé » est le **défaut** (`none`), que le projet lève par une valeur
écrite, avec son motif en commentaire — jamais une interdiction absolue : un projet dont le correctif de
production rebase sa branche de travail et la pousse en force déclare ce compte dans `base-push` **et**
`base-force-push` (la forge n'admet un push forcé qu'à un compte qui peut déjà pousser).

⚠️ **`release-push` vaut `none` dans la cible** : la publication arrive en avance rapide, rien ne commite
directement sur la branche de publication (« La publication arrive en avance rapide », ci-dessous). Le champ
reste pour la **transition** d'un projet dont la CI pousse encore un commit sur sa branche de publication
(commit de version ou de changelog) : il déclare ce compte, avec en commentaire le ticket qui retire ce push.
Pousser une **étiquette** n'est pas pousser sur la branche : le tag de publication n'a pas besoin de ce champ.

### Ce que la règle fixe, pour tous

| Champ de l'API | Valeur | Motif |
|---|---|---|
| `enable_force_push` (branche de publication) | `false` | aucun projet ne réécrit sa branche de publication ; un besoin futur ajoutera un champ, avec son motif |
| `push_whitelist_deploy_keys`, `force_push_allowlist_deploy_keys` | `false` | aucune clé de déploiement ne pousse sur une branche durable |
| clés de déploiement (`GET /repos/<dépôt>/keys`) | `read_only: true` | une clé qui peut écrire est un écart ; une clé en lecture seule est relevée, pas signalée |
| `push_whitelist_teams`, `force_push_allowlist_teams`, `merge_whitelist_teams` | vides | les listes se tiennent par comptes, déclarés dans `workflow.config` |
| `enable_bypass_allowlist` | `false` | tous les comptes en jeu sont souvent le même : une liste de contournement n'exigerait plus rien (décision E) |
| `block_admin_merge_override` | `false` | garde au responsable du projet la fusion d'urgence que lui réserve la règle de hotfix (décision H) |
| `required_approvals` | `0` | une seule personne relit ; la revue croisée est celle d'un LLM, vérifiée par `verify-and-merge-pr` |
| `require_signed_commits` | `false` | ni les agents ni les CI de publication ne signent |
| `protected_file_patterns`, `unprotected_file_patterns` | vides | un motif refuserait un push sans que rien ne le dise à l'outillage |
| `allow_squash_merge` | `true` | vers `forge.base`, **squash seul** : `verify-and-merge-pr` fusionne toujours en squash, un commit par PR |
| `allow_fast_forward_only_merge` | `true` si le projet a une branche de publication, `false` sinon | vers `forge.release-branch`, **avance rapide uniquement** : les commits de la branche de travail y arrivent tels quels, avec les mêmes SHA, et la fusion est refusée si la publication a un commit que la branche de travail n'a pas. Sans branche de publication, aucun chemin ne l'emploie |
| `allow_merge_commits`, `allow_rebase`, `allow_rebase_explicit`, `allow_manual_merge` | `false` | commit de fusion, « rebaser puis rattraper », « rebaser puis créer une révision de fusion », fusion manuelle : aucun chemin ne les emploie. Un commit de fusion ou un rebase crée sur la publication des commits que la branche de travail n'a pas, et casse l'avance rapide suivante |
| `default_merge_style` | `squash` | l'interface propose le style des PR vers la branche de travail |

Correction d'Arnaud du 08/10/2026, **commune à tous les projets** : les styles de fusion ne sont pas un choix
du projet (le champ `protection.release-merge-style` de la première version du schéma 7 est retiré,
`workflow-config.md`). Gitea les règle **par dépôt**, pas par branche : les styles ouverts sont donc squash
**et** avance rapide uniquement, squash par défaut, et chaque script impose le bon par l'API selon la base
(« Pourquoi le style n'est pas fixé par branche », ci-dessous). Tout autre style ouvert est un écart.

### La publication arrive en avance rapide

La contrainte qui en découle : ⛔ **la release et les correctifs de production ne commitent jamais
directement sur la branche de publication.** Une avance rapide exige que la branche de publication soit un
ancêtre de la branche de travail ; un seul commit posé sur elle seule — un commit de version, une ligne de
changelog écrite par la CI, un correctif poussé à la main — rend la publication suivante impossible
(`500`, `Merge DivergingFastForwardOnly`), et ne se rattrape que par un commit de fusion ou une réécriture,
deux gestes que la règle ferme.

- **Ce qui doit figurer dans la publication** (changelog, numéro de version) **passe d'abord par la branche de
  travail**, par une PR fusionnée en squash comme les autres : la publication ne fait qu'avancer la branche
  de publication jusqu'à un commit déjà relu.
- **Le tag se pose sur le commit arrivé en avance rapide**, relu sur la forge **après** la fusion : la fusion
  passe par l'API et ne met pas à jour le dépôt local, si bien qu'un `git tag` sans relecture se poserait sur
  l'ancienne tête.
- **Un correctif de production** part de la branche de publication (`hotfix/<nom>`), y arrive en avance
  rapide, reçoit son tag ; puis la **branche de travail est rebasée** sur la branche de publication et
  poussée en `--force-with-lease`, ce que le projet déclare dans `base-push` et `base-force-push`. Jamais de
  `cherry-pick` : un commit recopié a un autre SHA, et casserait l'avance rapide suivante.

**Le modèle, dans le projet source** (à lire, pas à recopier ; ses scripts sont propres à lui) :

- `scripts/release.sh <tag> [--merge]` : vérifie que la branche de publication est un ancêtre de la branche
  de travail (sinon refus, et renvoi au correctif de production), ouvre la PR de publication, en audite les
  verrous, la fusionne par l'API en `"Do": "fast-forward-only"` avec `head_commit_id`, relit la branche de
  publication sur la forge, et refuse de taguer si elle ne porte pas le commit publié ; puis pose et pousse le
  tag, que le workflow de livraison prend en charge.
- `scripts/hotfix.sh start | publish [--merge] | sync [--push]` : branche `hotfix/<nom>` tirée de la
  publication, fusion en avance rapide, tag de correctif calculé, puis rebase de la branche de travail sur la
  publication, poussée en `--force-with-lease` dont le bail est la tête lue **avant** le rebase.
- `--merge` et `--push` y sont l'affaire du responsable du projet : les scripts ne les déduisent jamais.

**Non relus** (limite, écrite aussi dans la sortie du contrôle) : les protections d'**étiquettes** (`v*`,
`staging-*`…) — un `0` ne dit rien d'elles ; une **autre branche durable** sans règle n'est pas détectée ; la
branche par défaut (`adoption.md`, étape 0), les styles de mise à jour, la suppression après fusion et les
réglages d'approbation au-delà du minimum ne sont pas jugés.

### Qui pose les règles

⛔ **Le contrôle est en lecture seule** : il n'écrit jamais rien sur la forge. Le responsable du projet pose
les réglages **dans l'interface**, à partir de la liste exacte que le contrôle produit sur un écart, écran
par écran et champ par champ, avec les libellés de l'interface (Gitea 1.27, en français) et la valeur lue à
côté de chaque valeur à changer. Le contrôle relit ensuite : **c'est sa relecture qui fait foi**, jamais la
réponse `200` de la forge à une écriture (décision A du 08/10/2026). La liste vient du même code que la
vérification : elle ne peut pas diverger d'elle.

### Quand il tourne

À l'**adoption** (`adoption.md`, étape 0) et à **chaque montée du sous-module**, sur le poste, avec le jeton
du poste ; et à la main, à tout moment. Pas en CI planifiée : lire `GET /branch_protections` exige le droit
d'administration du dépôt, précisément ce qu'un jeton de CI aux droits minimaux n'aura pas ; la question se
rouvrira avec un compte machine (décision B). Pas comme verrou de fusion non plus : un jeton expiré (`2`)
bloquerait toutes les fusions pour un réglage qui n'a pas bougé.

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

```bash
.working-method/gitea/check-branch-protection.sh     # dans un projet ; gitea/check-branch-protection.sh dans le dépôt commun
```

Il lit `workflow.config` (schéma 7, sinon `2` avant tout appel), le jeton du fichier d'environnement
(`gitea-token.md` : jamais affiché, passé à `curl` par l'entrée standard), puis `GET /repos/<dépôt>`,
`GET /repos/<dépôt>/branch_protections` et `GET /repos/<dépôt>/keys` (toutes les pages, jusqu'à une page
vide). Il n'envoie aucune écriture.

| Code | Sens |
|---|---|
| `0` | **conforme** : chaque champ relu est égal à la valeur attendue — la sortie nomme les règles relues et rappelle les limites |
| `1` | **écart** : chaque écart nommé (`règle « dev » : enable_push : lu true, attendu false`), puis la liste des réglages à poser, écran par écran |
| `2` | **vérification impossible** : `workflow.config` refusé ou d'avant le schéma 7, jeton absent, HTTP `401`, `403` (le compte du jeton n'administre pas le dépôt), réponse illisible ou incomplète, liste des clés sans fin. ⛔ Jamais `0` sur une lecture qui a échoué |

Testé par `tests/test-check-branch-protection.sh`, contre une forge simulée : un cas conforme, un écart par
famille (push, push forcé, fusion, contextes, styles, clé de déploiement, règle absente, règle en trop), et
un cas `2` par cause.

⛔ Une réponse `200` à une modification ne prouve rien : relire, par ce contrôle, puis **éprouver** — un push
direct sur la branche protégée, d'un compte qui n'est pas dans sa liste, doit être refusé
(`pre-receive hook declined`), et la branche rester à son SHA.

Pour un relevé à la main (un champ que le contrôle ne relit pas), sans afficher le jeton :

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
api_get "/repos/$REPO/branch_protections" | jq '.[] | {rule_name, enable_push, push_whitelist_usernames}'
```

## Le dépôt commun lui-même

Réglé à sa création (story outillage-14, phase A, 03/10/2026) et vérifié par l'API à chaque changement :

| Réglage | Valeur |
|---|---|
| Visibilité | public (`private: false`) ; la forge exige toutefois une connexion pour lire (`REQUIRE_SIGNIN_VIEW`), d'où le miroir public (`github-mirror.md`) |
| Branche par défaut | `main`, seule branche durable |
| Styles de fusion | squash **seul** (`allow_merge_commits`, `allow_rebase`, `allow_rebase_explicit`, `allow_fast_forward_only_merge`, `allow_manual_merge` à `false`) ; branche supprimée après fusion |
| Protection de `main` | `enable_push: false`, `enable_force_push: false`, fusion réservée au compte propriétaire (`merge_whitelist_usernames`), contexte exigé `checks / checks*`, `block_on_outdated_branch: true`, 0 approbation |
| Section `[protection]` de son `workflow.config` | `base-push = none`, `base-force-push = none`, `release-push = none`, `merge` = le compte propriétaire, `status-contexts = checks / checks*`, `block-outdated = true` ; styles : squash seul (sans branche de publication, l'avance rapide n'a aucun chemin) |

Cette protection est le **modèle** de la règle commune : le contrôle rend `0` sur elle (relevé du 08/10/2026,
rejoué par `tests/test-check-branch-protection.sh` sur une copie figée de la réponse de l'API).

La protection a été levée **une seule fois**, le 03/10/2026, le temps de pousser l'import de l'historique (15 secondes, réglages identiques avant et après, push direct et force-push refusés ensuite) : la trace complète est dans le suivi de la story outillage-14. Toute autre écriture sur `main` passe par une PR.

