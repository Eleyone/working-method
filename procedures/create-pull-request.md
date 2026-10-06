# Procédure — Ouvrir une pull request

Chaque story ou correctif arrive en revue par une pull request ouverte sur la forge Gitea, depuis sa branche de travail vers la base du projet (`forge.base`). `gitea/create-pull-request.sh` (dépôt commun ; `.working-method/gitea/create-pull-request.sh` depuis un projet) l'ouvre par l'API REST, toujours de la même façon. Il se lance depuis la racine du projet et lit son `workflow.config` (`procedures/workflow-config.md`).

## Prérequis

- `jq` et `curl` installés. Sans `jq`, le script s'arrête et indique `sudo apt install jq`.
- Le fichier d'environnement du projet (`forge.env-file`), avec `GITEA_URL`, `GITEA_USER` et `GITEA_TOKEN` : procédure `gitea-token.md`.
- Si le projet a un garde-fou (`guard.command`), son fichier de motifs (`guard.patterns-file`, ou celui que désigne `PRIVATE_PATTERNS_FILE`), avec au moins un motif : ouvrir une PR exige un audit, pas un passage « chemins seulement ». Sans garde-fou (`guard.command = none`), le script le dit, et n'audite ni les commits ni le titre.
- Une branche dont le préfixe figure dans `forge.branch-prefixes` (dans le projet source : `feat/*`, `fix/*`, `chore/*`, `docs/*`), avec tout commité, poussée sur la forge au même commit que la branche locale.

## Ouvrir la PR

1. Écrire le corps de la PR dans `.pr-body.md`, à la racine du dépôt. Ce fichier est ignoré par git et réutilisé d'une PR à l'autre : le réécrire entièrement pour chaque PR. Un autre fichier se désigne par `--body-file`.
2. Lancer :

   ```bash
   .working-method/gitea/create-pull-request.sh --title "<titre>"
   .working-method/gitea/create-pull-request.sh --title "<titre>" --body-file <fichier>
   ```

3. Le script affiche `PR n° <numéro> ouverte : <branche> → <base>`. Il n'affiche jamais l'adresse de la PR, qui contient le nom de la forge.

Le corps est passé par `jq --rawfile`, puis envoyé par `curl --data @` : guillemets, retours à la ligne, accents et caractères spéciaux arrivent tels quels.

## Base selon la branche

| Branche | Résultat |
|---|---|
| `<préfixe>/<nom>`, préfixe de `forge.branch-prefixes` | PR vers `forge.base` |
| la base, ou la branche de publication (`forge.release-branch`) | refus : la publication a son propre chemin |
| tout autre préfixe (dans le projet source, `hotfix/*` en est un) | refus, avec la liste des préfixes admis |

Ce skill n'ouvre jamais de PR vers la branche de publication.

## Codes de sortie

`0` PR ouverte ; `1` **écart constaté** : la branche ou l'arbre ne permet pas d'ouvrir la PR (préfixe ou base refusés, modifications non commitées, branche non poussée sur ce commit, refus du garde-fou, motif privé dans le titre ou le corps, PR déjà ouverte, corps publié différent du fichier) ; `2` l'ouverture n'a pas pu être tentée (usage, prérequis, `workflow.config`, fichier d'environnement et ses variables, lecture de git ou de la forge, création refusée par la forge).

## Ce que le script vérifie

Dans l'ordre. Tout refus arrête le script **avant la moindre écriture sur la forge**, sauf le dernier contrôle.

1. `jq` et `curl` sont présents.
2. `workflow.config` est lu et validé en entier (code `2` sinon).
3. Un titre est donné, et le fichier de corps existe et n'est pas vide.
4. Le dépôt distant `origin` est bien celui de `forge.repo`.
5. Le préfixe de la branche donne la base (tableau ci-dessus).
6. Aucune modification n'est en attente, fichiers non suivis compris.
7. Si le projet a un garde-fou, son exécutable existe et son fichier de motifs contient au moins un motif.
8. La branche est poussée sur la forge au même commit que la branche locale ; la base est lue sur la forge.
9. Si le projet a un garde-fou, `<guard.command> history` passe sur les commits de la branche, avec la liste des motifs.
10. Ni le titre ni le corps ne contiennent de motif privé. Un refus ne montre ni le motif ni le contenu.
11. Le fichier d'environnement existe et contient les trois variables. Il n'est lu qu'à ce moment, juste avant le premier appel à l'API, par `gitea/gitea.sh` : ligne par ligne, jamais chargé avec `source` ; aucune valeur n'est affichée, et le jeton n'est jamais demandé. Un manque renvoie à `gitea-token.md`.
12. Le jeton appartient au compte `GITEA_USER`.
13. Aucune PR n'est déjà ouverte pour la branche ; sinon, le script affiche son numéro et n'en ouvre pas de seconde.
14. La PR est créée.
15. Le corps publié est relu sur la forge et comparé octet par octet au fichier.

## Secrets

- Le jeton est passé à `curl` par l'entrée standard : il n'apparaît ni sur la ligne de commande ni dans la liste des processus.
- Aucune valeur de `.env` n'est affichée, ni en cas de succès, ni en cas d'erreur. Les messages d'erreur de la forge sont repris sans adresse.
- Le script coupe la trace du shell dès sa première ligne : même lancé avec `bash -x`, il n'affiche pas le jeton. Ne jamais réactiver la trace pour déboguer (`gitea-token.md`).

## En cas de refus

- **Avant la création** (contrôles 1 à 13) : rien n'est ouvert. Corriger la cause indiquée, puis relancer.
- **Code HTTP `000`** : la forge ne répond pas. Relancer quand elle est joignable.
- **PR déjà ouverte** : poursuivre sur la PR dont le numéro est affiché.
- **Corps publié différent du fichier** (contrôle 15) : la PR est ouverte, son numéro est affiché. Corriger le corps sur la forge avant de demander la revue.
