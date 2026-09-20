# Procédure — Vérifier et fusionner une pull request

Aucune fusion ne contourne la revue, le garde-fou ou le flux linéaire (AD-24). `scripts/verify-and-merge-pr.sh` audite les cinq verrous d'une PR vers `dev` et, seulement avec `--merge`, la fusionne en squash si tous passent.

**Fusionner est une décision humaine.** Un agent lance l'audit librement ; il ne lance `--merge` qu'après l'autorisation explicite d'Arnaud, donnée pour cette PR.

## Prérequis

- `jq` et `curl` installés ; `.env` avec `GITEA_URL`, `GITEA_USER` et `GITEA_TOKEN` (`gitea-token.md`).
- Le fichier de motifs (`check-private.md`), avec au moins un motif : aucune fusion sans audit.
- `scripts/check-private.sh` et `scripts/sprint-consistency.sh` présents dans l'arbre de travail.

## Lancer

```bash
scripts/verify-and-merge-pr.sh <numéro de PR>           # audit : affiche chaque verrou, ne fusionne rien
scripts/verify-and-merge-pr.sh <numéro de PR> --merge   # fusion, seulement si tous les verrous passent
```

Code de sortie : `0` tous les verrous passent (et, avec `--merge`, la PR est fusionnée) ; `1` au moins un verrou bloque, rien n'est fusionné ; `2` audit impossible (usage, `jq` absent, `.env` absent, fichier de motifs absent ou sans motif, dépôt distant qui n'est pas `Eleyone/eleyone.fr`, forge injoignable, réponse illisible, branche qui a bougé).

Il n'existe aucune option `--force`, et le script n'envoie jamais `force_merge` ni `merge_when_checks_succeed`. Il lit les objets git et l'API, et n'écrit jamais dans l'arbre de travail.

## Les cinq verrous

Chaque verrou s'affiche avec son état : `passe`, `absent` (CI pendant l'amorçage seulement, admis) ou `bloque`. Les appels à la forge restent dans le script ; les décisions (rapport retenu, règle du commit de statut, verrou CI, titre de fusion, lecture de la timeline) sont dans `scripts/lib/merge-gates.sh`, et la lecture du suivi dans `scripts/lib/sprint.sh`, toutes deux testées par `scripts/tests/run.sh` (`shell-scripts.md`).

1. **PR fusionnable** : ouverte, pas en brouillon, fusionnable pour la forge (`mergeable`), pas déjà fusionnée, base `dev`. Une base `main` est refusée : la publication passe par `release`, un correctif de production par `hotfix`. Toute autre base est refusée. Une PR fermée ou déjà fusionnée arrête l'audit. Juste après un push, la forge peut afficher la PR « non fusionnable » le temps de recalculer son état : relancer l'audit quelques secondes plus tard avant de chercher un conflit (constat de la story 0.7).
2. **Revue LLM** : compte le **dernier** commentaire `llm-review` publié par le compte `GITEA_USER`, pour la base de la PR :
   - sur le SHA de tête : `verdict=pass` passe, `verdict=block` bloque ;
   - sinon, sur le parent de la tête : `verdict=pass` passe seulement si le commit de tête respecte la **règle du commit de statut** (ci-dessous) ;
   - sinon, le verrou bloque.

   Les commentaires sont lus dans la timeline de la PR (`/issues/{n}/timeline`), par pages de la taille maximale admise par la forge (`max_response_items`, lu dans `/settings/api`), jusqu'à la première page incomplète et au plus 100 pages ; au-delà de la dernière page, la forge répond `null`, lu comme une page vide. La liste des commentaires d'une issue n'est pas utilisée : elle ignore `limit` et `page` (bogue connu de Gitea, constaté sur la forge le 15/09/2026), ce qui fait tourner sans fin toute pagination fondée sur elle.

   **Exception documentaire** : si tous les fichiers de la PR sont sous `_bmad-output/`, la revue n'est pas exigée. Un seul fichier ailleurs (dont `content/**`, `AGENTS.md`, `CLAUDE.md`, `docs/procedures/**`, `.claude/**`, `docs/format-cas.md`) la rétablit. L'exception ne saute que ce verrou.
3. **Garde-fou** : `scripts/check-private.sh history base..tête`, avec la liste des motifs, sur les commits de la PR récupérés depuis la forge.
4. **CI** : les statuts du workflow **`checks`** sur le SHA de tête rendu par la forge. Tous verts passent ; un seul `pending` bloque en disant « en cours » ; tout autre état bloque en se nommant — `failure`, `error`, `cancelled`, `skipped` ou `warning`, aucun n'étant traité par omission.
   - **Le verrou ne regarde que le workflow des contrôles.** Gitea nomme un contexte `<workflow> / <job> (<événement>)`, par exemple `checks / checks (pull_request)`, et l'état d'un statut vit sous la clé `status` — `state` n'existe qu'au niveau combiné. Juger l'état combiné laisserait n'importe quel autre workflow décider d'une fusion : l'agent de parité commente **sans bloquer** (AD-16), et son échec ne doit pas verrouiller une PR (story 3.16).
   - **Seule la forge principale fait foi.** La CI publique de GitHub peut être en retard d'une synchronisation ; elle n'entre pas dans le verrou.
   - **La présence du workflow sur la base** est lue après un `git fetch` de la base : un clone périmé ne peut pas désactiver le verrou en silence.
   - **Une CI absente bloque** dès que `.gitea/workflows/checks.yaml` existe sur la base. Le message le dit — « existe sur la base » —, à distinguer de l'amorçage ci-dessous, qui dit « absent de la base ».
   - **Règle d'amorçage, régime révolu mais pas mort.** Tant que le workflow n'existe pas sur la **base** de la PR, une CI sans statut est affichée `absent` et le script lance lui-même le substitut : `check-private.sh history`, puis `scripts/check.sh` sur la tête, dans une copie de travail à laquelle il passe les binaires épinglés du dépôt (`TOOLS_LOCAL_DIR`) — la copie n'a ni `.tools/` ni `.env`, et les valeurs légales viennent du fichier factice commité. Un substitut en échec bloque. Depuis la story 3.13, `dev` porte le workflow : ce régime ne concerne plus qu'une PR dont la base ne l'a pas encore, la PR de mise en ligne `dev` → `main` tant que `main` est en retard.
   - **L'exception documentaire ne couvre pas ce verrou.** Une PR qui ne touche que `_bmad-output/` est dispensée de revue, jamais de CI.
5. **Suivi de sprint** : `scripts/sprint-consistency.sh --merge <n.m> --rev <SHA de tête>`, le numéro de story étant tiré du nom de la branche (`chore/0-7-…` → `0.7`). Une branche sans numéro de story passe par le contrôle global (`--rev <SHA de tête>`). Exemption d'amorçage : la PR qui ajoute `sprint-status.yaml` à une base qui ne l'a pas.

## Règle du commit de statut

Le rapport `pass` sur le parent de la tête vaut pour la tête si le commit de tête :

- est le seul commit après le SHA relu ;
- dans `sprint-status.yaml`, ne change que la ligne de la story de `review` à `done`, `last_updated` et, si la story clôt son epic, la ligne de l'epic vers `done` ;
- dans le fichier de la story, ne supprime que la ligne `Status: review`, ajoute `Status: done`, et n'ajoute par ailleurs que des lignes ;
- dans `deferred-work.md`, n'ajoute que des lignes ;
- ne touche aucun autre fichier.

Toute autre modification exige une nouvelle revue.

## Fusion

Avec `--merge`, et seulement si tous les verrous passent :

1. le script relit la PR : si sa tête a bougé pendant l'audit, il s'arrête ;
2. il prépare le message du commit : titre de la PR suivi de « (#N) », puis les sujets des commits de la branche et leurs lignes `Co-Authored-By`, sans doublon ; un message contenant un motif privé bloque la fusion ;
3. il fusionne en squash sur le SHA de tête exact (`head_commit_id`), et la forge supprime la branche ;
4. il relit la PR pour confirmer la fusion et affiche le SHA du commit créé sur `dev`.

Ensuite, mettre `dev` à jour en local.

## En cas de verrou bloquant

Le script affiche la raison de chaque verrou bloquant. Corriger la cause, pousser, et relancer l'audit ; après toute modification du code, relancer d'abord `llm-review` sur la nouvelle tête.
