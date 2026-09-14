# Procédure — Ouvrir une pull request

Chaque story ou correctif arrive en revue par une pull request ouverte sur la forge Gitea, depuis sa branche de travail vers `dev` (AD-24). `scripts/create-pull-request.sh` l'ouvre par l'API REST, toujours de la même façon.

## Prérequis

- `jq` et `curl` installés. Sans `jq`, le script s'arrête et indique `sudo apt install jq`.
- `.env` à la racine du dépôt, avec `GITEA_URL`, `GITEA_USER` et `GITEA_TOKEN` : procédure `gitea-token.md`.
- Le fichier de motifs (`docs/private/forbidden-patterns.txt`, ou celui que désigne `PRIVATE_PATTERNS_FILE`) : ouvrir une PR exige un audit, pas un passage « chemins seulement » (`check-private.md`).
- Une branche `feat/*`, `fix/*`, `chore/*` ou `docs/*`, avec tout commité, poussée sur la forge au même commit que la branche locale.

## Ouvrir la PR

1. Écrire le corps de la PR dans `.pr-body.md`, à la racine du dépôt. Ce fichier est ignoré par git et réutilisé d'une PR à l'autre : le réécrire entièrement pour chaque PR. Un autre fichier se désigne par `--body-file`.
2. Lancer :

   ```bash
   scripts/create-pull-request.sh --title "<titre>"
   scripts/create-pull-request.sh --title "<titre>" --body-file <fichier>
   ```

3. Le script affiche `PR n° <numéro> ouverte : <branche> → dev`. Il n'affiche jamais l'adresse de la PR, qui contient le nom de la forge.

Le corps est passé par `jq --rawfile`, puis envoyé par `curl --data @` : guillemets, retours à la ligne, accents et caractères spéciaux arrivent tels quels.

## Base selon la branche

| Branche | Résultat |
|---|---|
| `feat/*`, `fix/*`, `chore/*`, `docs/*` | PR vers `dev` |
| `hotfix/*` | refus : le skill `hotfix` ouvre la PR vers `main` |
| `dev`, `main` | refus : la publication de `dev` vers `main` passe par le skill `release` |
| tout autre préfixe | refus |

Ce skill n'ouvre jamais de PR vers `main`.

## Ce que le script vérifie

Dans l'ordre. Tout refus arrête le script **avant la moindre écriture sur la forge**, sauf le dernier contrôle.

1. `jq` et `curl` sont présents.
2. Un titre est donné, et le fichier de corps existe et n'est pas vide.
3. `.env` existe et contient les trois variables. Le fichier est lu ligne par ligne, jamais chargé avec `source` ; aucune valeur n'est affichée, et le jeton n'est jamais demandé. Un manque renvoie à `gitea-token.md`.
4. Le dépôt distant `origin` est bien `Eleyone/eleyone.fr`, nom canonique écrit dans le script.
5. Le préfixe de la branche donne la base (tableau ci-dessus).
6. Aucune modification n'est en attente, fichiers non suivis compris.
7. Le fichier de motifs existe.
8. La branche est poussée sur la forge au même commit que la branche locale ; la base est lue sur la forge.
9. `scripts/check-private.sh history` passe sur les commits de la branche, avec la liste des motifs.
10. Ni le titre ni le corps ne contiennent de motif privé. Un refus ne montre ni le motif ni le contenu.
11. Le jeton appartient au compte `GITEA_USER`.
12. Aucune PR n'est déjà ouverte pour la branche ; sinon, le script affiche son numéro et n'en ouvre pas de seconde.
13. La PR est créée.
14. Le corps publié est relu sur la forge et comparé octet par octet au fichier.

## Secrets

- Le jeton est passé à `curl` par l'entrée standard : il n'apparaît ni sur la ligne de commande ni dans la liste des processus.
- Aucune valeur de `.env` n'est affichée, ni en cas de succès, ni en cas d'erreur. Les messages d'erreur de la forge sont repris sans adresse.
- Le script coupe la trace du shell dès sa première ligne : même lancé avec `bash -x`, il n'affiche pas le jeton. Ne jamais réactiver la trace pour déboguer (`gitea-token.md`).

## En cas de refus

- **Avant la création** (contrôles 1 à 12) : rien n'est ouvert. Corriger la cause indiquée, puis relancer.
- **Code HTTP `000`** : la forge ne répond pas (le homelab peut être éteint). Relancer quand elle est joignable.
- **PR déjà ouverte** : poursuivre sur la PR dont le numéro est affiché.
- **Corps publié différent du fichier** (contrôle 14) : la PR est ouverte, son numéro est affiché. Corriger le corps sur la forge avant de demander la revue.
