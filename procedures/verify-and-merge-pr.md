# Procédure — Vérifier et fusionner une pull request

Aucune fusion ne contourne la revue, le garde-fou ou le flux linéaire. `gates/verify-and-merge-pr.sh` (dépôt commun ; `.working-method/gates/verify-and-merge-pr.sh` depuis un projet) audite les cinq verrous d'une PR vers la base du projet (`forge.base` de son `workflow.config`) et, seulement avec `--merge`, la fusionne en squash si tous passent. Il se lance depuis la racine du projet ; `workflow.config` est lu et validé en entier avant tout appel à la forge (`procedures/workflow-config.md`).

**Fusionner est une décision humaine, sauf délégation écrite.** Un agent lance l'audit librement ; il ne lance `--merge` qu'avec l'autorisation explicite du responsable du projet pour cette PR, ou dans le cadre d'une délégation que l'`AGENTS.md` du projet écrit.

## Prérequis

- `jq` et `curl` installés ; le fichier d'environnement du projet (`forge.env-file`) avec `GITEA_URL`, `GITEA_USER` et `GITEA_TOKEN` (`gitea-token.md`).
- Un `workflow.config` valide à la racine du projet.
- Si le projet a un garde-fou (`guard.command`) : l'exécutable présent, et son fichier de motifs (`guard.patterns-file`, ou `PRIVATE_PATTERNS_FILE`) avec au moins un motif : aucune fusion sans audit.
- `sprint-consistency.sh` à côté de ce script, dans le dépôt commun.

## Lancer

```bash
.working-method/gates/verify-and-merge-pr.sh <numéro de PR>           # audit : affiche chaque verrou, ne fusionne rien
.working-method/gates/verify-and-merge-pr.sh <numéro de PR> --merge   # fusion, seulement si tous les verrous passent
```

Code de sortie : `0` tous les verrous passent (et, avec `--merge`, la PR est fusionnée) ; `1` au moins un verrou bloque, rien n'est fusionné ; `2` audit impossible (usage, `jq` absent, `workflow.config` refusé, valeur que l'outillage ne sait pas encore servir, fichier d'environnement absent, garde-fou absent, fichier de motifs absent ou sans motif, dépôt distant qui n'est pas `forge.repo`, forge injoignable, réponse illisible, branche qui a bougé, copie complète de la tête impossible pour le substitut d'amorçage). Une fois la PR lue, un `2` est aussi publié en **alerte sur la PR** (`alert_pr`, `shell-scripts.md`, § *Codes de sortie*) : un commentaire « verify-and-merge-pr : anomalie (code 2) » avec le message ; si la forge le refuse, le terminal le dit et reste le seul canal.

Il n'existe aucune option `--force`, et le script n'envoie jamais `force_merge` ni `merge_when_checks_succeed`. Il lit les objets git et l'API, et n'écrit jamais dans l'arbre de travail.

## Les cinq verrous

Chaque verrou s'affiche avec son état : `passe`, `absent` (CI pendant l'amorçage seulement, admis), `inactif` (verrou désactivé par `none` dans `workflow.config` : il ne bloque pas, et il **dit** qu'il n'a rien vérifié) ou `bloque`. Les appels à la forge restent dans le script ; les décisions (rapport retenu, règle du commit de statut, verrou CI, base, exception documentaire, titre de fusion, lecture de la timeline) sont dans `gates/merge-gates.sh`, et la lecture du suivi dans `lib/sprint.sh`, toutes deux testées par `tests/run.sh` (`shell-scripts.md`).

1. **PR fusionnable** : ouverte, pas en brouillon, fusionnable pour la forge (`mergeable`), pas déjà fusionnée, base `forge.base`. Une base égale à la branche de publication (`forge.release-branch`) est refusée : la publication a son propre chemin, hors de ce script. Toute autre base est refusée. Une PR fermée ou déjà fusionnée arrête l'audit. Juste après un push, la forge peut afficher la PR « non fusionnable » le temps de recalculer son état : relancer l'audit quelques secondes plus tard avant de chercher un conflit (constat de la story 0.7).
2. **Revue LLM** : compte le **dernier** commentaire `llm-review` publié par le compte `GITEA_USER`, pour la base de la PR :
   - sur le SHA de tête : `verdict=pass` passe, `verdict=block` bloque ;
   - sinon, sur le parent de la tête : `verdict=pass` passe seulement si le commit de tête respecte la **règle du commit de statut** (ci-dessous) ;
   - sinon, le verrou bloque.

   Les commentaires sont lus dans la timeline de la PR (`/issues/{n}/timeline`), par pages de la taille maximale admise par la forge (`max_response_items`, lu dans `/settings/api`), jusqu'à la première page incomplète et au plus 100 pages ; au-delà de la dernière page, la forge répond `null`, lu comme une page vide. La liste des commentaires d'une issue n'est pas utilisée : elle ignore `limit` et `page` (bogue connu de Gitea, constaté sur la forge le 15/09/2026), ce qui fait tourner sans fin toute pagination fondée sur elle.

   **Exception documentaire** : si **chaque** fichier de la PR correspond à l'expression `review.exempt-paths` (dans le projet source : `^_bmad-output/`), la revue n'est pas exigée. Un seul fichier hors de l'expression la rétablit. `none` : aucune exception. L'exception ne saute que ce verrou.

   Le rapport n'est lu qu'en commentaire de PR (`review.report = pr-comment`) ; la valeur `file` sort en `2` jusqu'à la story 8.
3. **Garde-fou** : `<guard.command> history base..tête`, avec la liste des motifs, sur les commits de la PR récupérés depuis la forge. `guard.command = none` : verrou `inactif`.
4. **CI** : les statuts du workflow que nomme **`ci.status-context`** (dans le projet source : `checks`) sur le SHA de tête rendu par la forge. `ci.workflow = none` : verrou `inactif`, qui le dit — jamais une CI verte. Tous verts passent ; un seul `pending` bloque en disant « en cours » ; tout autre état bloque en se nommant — `failure`, `error`, `cancelled` ou `warning`, aucun n'étant traité par omission.
   - **`skipped` fait exception** : le workflow a délibérément renoncé, l'événement ne le concernant pas. Dans le projet source, depuis que les contextes sont obligatoires (21/09/2026), la tête d'une PR porte un `checks / checks (push)` ignoré à côté du `(pull_request)` vert, puisque le déclencheur `push` n'y écoute que les branches d'intégration et de publication. Un statut ignoré est donc écarté — mais il ne suffit pas : sans **aucun** run effectif, le verrou bloque.
   - **Le verrou ne regarde que le workflow des contrôles.** Gitea nomme un contexte `<workflow> / <job> (<événement>)`, par exemple `checks / checks (pull_request)`, et l'état d'un statut vit sous la clé `status` — `state` n'existe qu'au niveau combiné. Un statut compte si son contexte vaut `ci.status-context`, ou commence par `ci.status-context` suivi de ` /`. Juger l'état combiné laisserait n'importe quel autre workflow décider d'une fusion : dans le projet source, un agent de parité commente **sans bloquer**, et son échec ne doit pas verrouiller une PR (story 3.16).
   - **Seule la forge principale fait foi.** La CI d'un miroir public peut être en retard d'une synchronisation ; elle n'entre pas dans le verrou.
   - **La présence du workflow sur la base** est lue après un `git fetch` de la base : un clone périmé ne peut pas désactiver le verrou en silence.
   - **Une CI absente bloque** dès que le workflow `ci.workflow` existe sur la base. Le message le dit — « existe sur la base » —, à distinguer de l'amorçage ci-dessous, qui dit « absent de la base ».
   - **Règle d'amorçage (`ci.bootstrap = true`), régime révolu mais pas mort.** Tant que le workflow n'existe pas sur la **base** de la PR, une CI sans statut est affichée `absent` et le script lance lui-même le substitut : le garde-fou du verrou 3, puis `checks.command` sur la tête, dans une copie de travail (`git worktree add`) à laquelle il passe le dossier des binaires épinglés du projet (`TOOLS_LOCAL_DIR=<racine>/.tools`) — la copie n'a aucun fichier ignoré par git. La commande est découpée sur les espaces, jamais évaluée par le shell. Un substitut en échec bloque. Dans le projet source, ce régime n'est plus atteignable depuis que sa base porte le workflow : il ne couvre plus aucun cas vivant, et une mise en ligne ne se valide jamais sur un substitut.
     - **Les sous-modules de la copie.** `git worktree add` n'en initialise aucun : leurs dossiers y seraient vides. Un contrôle qui lit un sous-module sans en vérifier la présence y passerait à tort, `git -C <sous-module>` y répondrait pour la copie elle-même, et un contrôle qui exige le sous-module y refuserait sans avoir rien contrôlé. Le script peuple donc chaque sous-module de la tête (gitlink, mode `160000`) **depuis le sous-module du dépôt de travail, jamais depuis la forge** : `git submodule update --checkout` dans la copie, l'URL du sous-module remplacée par son dossier local pour cette seule commande (`git -c`, avec `protocol.file.allow=always`), jamais dans la configuration du dépôt. Il vérifie ensuite que, dans la copie, git répond pour le sous-module lui-même, au commit épinglé.
     - **Refus en `2`**, sans lancer le contrôle : sous-module non initialisé dans le dépôt de travail (`git rev-parse --show-prefix` doit y rendre une ligne vide ; un dossier vide fait répondre le dépôt **parent**, comme pour la revue, `llm-review.md` étape 7), sans le commit que la tête épingle, absent du `.gitmodules` de la tête, contenant lui-même un sous-module (les sous-modules imbriqués ne sont pas peuplés), peuplement impossible ou sans effet, et création de la copie impossible. Remède : `git submodule update --init` dans le dépôt de travail, puis relancer l'audit. Un substitut ne tourne jamais sur une copie incomplète.
     - Un `checks.command` qui sort en `2` compte aujourd'hui comme un substitut en échec (verrou `bloque`, sortie `1`).
   - **Sans règle d'amorçage (`ci.bootstrap = false`)**, une CI sans statut et sans workflow sur la base **bloque** : il n'y a pas de substitut.
   - **L'exception documentaire ne couvre pas ce verrou.** Une PR dispensée de revue ne l'est jamais de CI.
5. **Suivi de sprint** : `sprint-consistency.sh --merge <n.m> --rev <SHA de tête>`, le numéro de story étant tiré du nom de la branche (`chore/0-7-…` → `0.7`). Une branche sans numéro de story passe par le contrôle global (`--rev <SHA de tête>`). Exemption d'amorçage : la PR qui ajoute `sprint.status-file` à une base qui ne l'a pas. `sprint.convention = none` : verrou `inactif` ; `keyed` sort en `2` jusqu'à la story 5.

## Règle du commit de statut

Le rapport `pass` sur le parent de la tête vaut pour la tête si le commit de tête :

- est le seul commit après le SHA relu ;
- dans le suivi de sprint, ne change que la ligne de la story de `review` à `done`, `last_updated` et, si la story clôt son epic, la ligne de l'epic vers `done` ;
- dans le fichier de la story, ne supprime que la ligne `Status: review`, ajoute `Status: done`, et n'ajoute par ailleurs que des lignes ;
- dans `deferred-work.md` du dossier des stories, n'ajoute que des lignes ;
- ne touche aucun autre fichier.

Toute autre modification exige une nouvelle revue.

## Fusion

Avec `--merge`, et seulement si tous les verrous passent :

1. le script relit la PR : si sa tête a bougé pendant l'audit, il s'arrête ;
2. il prépare le message du commit : titre de la PR suivi de « (#N) », puis les sujets des commits de la branche et leurs lignes `Co-Authored-By`, sans doublon ; un message contenant un motif privé bloque la fusion ;
3. il fusionne en squash sur le SHA de tête exact (`head_commit_id`), et la forge supprime la branche ;
4. il relit la PR pour confirmer la fusion et affiche le SHA du commit créé sur la base.

Ensuite, mettre la base à jour en local.

## En cas de verrou bloquant

Le script affiche la raison de chaque verrou bloquant. Corriger la cause, pousser, et relancer l'audit ; après toute modification du code, relancer d'abord `llm-review` sur la nouvelle tête.
