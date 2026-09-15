# Procédure — Vérifier et fusionner une pull request

Aucune fusion ne contourne la revue, le garde-fou ou le flux linéaire (AD-24). `scripts/verify-and-merge-pr.sh` audite les cinq verrous d'une PR vers `dev` et, seulement avec `--merge`, la fusionne en squash si tous passent.

**Fusionner est une décision humaine.** Un agent lance l'audit librement ; il ne lance `--merge` qu'après l'autorisation explicite d'Arnaud, donnée pour cette PR.

## Prérequis

- `jq` et `curl` installés ; `.env` avec `GITEA_URL`, `GITEA_USER` et `GITEA_TOKEN` (`gitea-token.md`).
- Le fichier de motifs (`check-private.md`) : aucune fusion sans audit.
- `scripts/check-private.sh` et `scripts/sprint-consistency.sh` présents dans l'arbre de travail.

## Lancer

```bash
scripts/verify-and-merge-pr.sh <numéro de PR>           # audit : affiche chaque verrou, ne fusionne rien
scripts/verify-and-merge-pr.sh <numéro de PR> --merge   # fusion, seulement si tous les verrous passent
```

Code de sortie : `0` tous les verrous passent (et, avec `--merge`, la PR est fusionnée) ; `1` au moins un verrou bloque, rien n'est fusionné ; `2` audit impossible (usage, `jq` absent, `.env` ou fichier de motifs absent, dépôt distant qui n'est pas `Eleyone/eleyone.fr`, forge injoignable, réponse illisible, branche qui a bougé).

Il n'existe aucune option `--force`, et le script n'envoie jamais `force_merge` ni `merge_when_checks_succeed`. Il lit les objets git et l'API, et n'écrit jamais dans l'arbre de travail.

## Les cinq verrous

Chaque verrou s'affiche avec son état : `passe`, `absent` (CI pendant l'amorçage, admis) ou `bloque`.

1. **PR fusionnable** : ouverte, pas en brouillon, fusionnable pour la forge (`mergeable`), pas déjà fusionnée, base `dev`. Une base `main` est refusée : la publication passe par `release`, un correctif de production par `hotfix`. Toute autre base est refusée. Une PR fermée ou déjà fusionnée arrête l'audit.
2. **Revue LLM** : compte le **dernier** commentaire `llm-review` publié par le compte `GITEA_USER`, pour la base de la PR :
   - sur le SHA de tête : `verdict=pass` passe, `verdict=block` bloque ;
   - sinon, sur le parent de la tête : `verdict=pass` passe seulement si le commit de tête respecte la **règle du commit de statut** (ci-dessous) ;
   - sinon, le verrou bloque.

   **Exception documentaire** : si tous les fichiers de la PR sont sous `_bmad-output/`, la revue n'est pas exigée. Un seul fichier ailleurs (dont `content/**`, `AGENTS.md`, `CLAUDE.md`, `docs/procedures/**`, `.claude/**`, `docs/format-cas.md`) la rétablit. L'exception ne saute que ce verrou.
3. **Garde-fou** : `scripts/check-private.sh history base..tête`, avec la liste des motifs, sur les commits de la PR récupérés depuis la forge.
4. **CI** : état combiné de la forge sur le SHA de tête. Vert passe ; échec, erreur ou autre état terminé bloque.
   - Tant que `.gitea/workflows/checks.yaml` n'existe pas sur la base (**règle d'amorçage**), une CI absente est affichée `absent` et le script lance lui-même le substitut : `check-private.sh history`, puis `scripts/check.sh` sur la tête dès qu'il existe (story 3.2). Un substitut en échec bloque.
   - Dès que `checks.yaml` existe sur la base, une CI absente ou en cours bloque (story 3.16).
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
