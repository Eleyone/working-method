# Procédure — Jeton d'accès à l'API de la forge

Les skills de développement (`create-pull-request`, `verify-and-merge-pr`, `release`, `hotfix`) appellent l'API REST de la forge Gitea. Ils s'authentifient avec un **jeton d'accès personnel**, rangé dans `.env` à la racine du dépôt. Aucun identifiant n'entre jamais dans le dépôt.

Les push git, eux, restent en SSH : une clé SSH n'ouvre pas l'API REST.

## Règles

- Le jeton vit **uniquement** dans `.env`, qui n'est jamais commité : il est ignoré par git et refusé par `scripts/check-private.sh`.
- **Aucun script n'affiche ni ne demande le jeton.** Les scripts chargent `.env` sans afficher de valeur ; sans variable, ils échouent avec un message qui renvoie à cette procédure.
- **Aucun script ne charge `.env` avec `source` (ou `.`).** Une ligne mal formée serait exécutée comme une commande, et le message d'erreur du shell peut afficher une partie de la valeur. Les scripts lisent `.env` ligne par ligne, ne retiennent que les clés dont ils ont besoin (`CLÉ=VALEUR`) et retirent les guillemets qui entourent la valeur.
- **Aucun script à jeton ne s'exécute avec la trace du shell** (`bash -x`, `set -x`) : la trace afficherait le jeton. Chaque script qui lit le jeton coupe la trace dès sa première ligne, avant de lire `.env` ; ne jamais la réactiver pour déboguer.
- **Aucun agent ne lit `.env`.** La lecture est refusée aux agents Claude (`.claude/settings.json`) et Antigravity (réglage du poste). Aucune valeur n'est copiée dans un fichier, un commit ou une conversation.
- **En CI**, pas de jeton personnel : Gitea refuse les secrets dont le nom commence par `GITEA_` et fournit aux jobs leur propre jeton.
- Un **mot de passe** n'est jamais utilisé à la place du jeton.

## Créer le jeton

1. Dans l'interface de la forge : **Paramètres → Applications → Gérer les jetons d'accès**.
2. **Nom** : explicite et unique, par exemple `eleyone-skills`, pour le reconnaître au moment de le révoquer.
3. **Portées**, les minimales et rien d'autre :
   - `repository` en **lecture et écriture** : ouverture et fusion des PR ;
   - `issue` en **lecture et écriture** : commentaires de PR, dont le rapport de revue.

   Aucune autre portée : ni `admin`, ni `organization`, ni `user`, ni `package`.
4. **Durée** : une durée courte, par exemple 90 jours. Noter la date d'expiration dans un rappel.
5. Copier le jeton **une seule fois**, directement dans `.env` (étape suivante). La forge ne le réaffiche pas.

## Renseigner `.env`

À partir de `.env.example`, ouvrir `.env` **avec un éditeur**. Ne pas utiliser `echo` ni une redirection shell, qui laissent le jeton dans l'historique du terminal.

```
GITEA_URL=https://<adresse-de-la-forge>
GITEA_USER=<compte>
GITEA_TOKEN=<jeton>
HUGO_LEGAL_PUBLISHER_NAME="<Prénom Nom>"
```

Une valeur qui contient une espace (nom, adresse) se met **entre guillemets**. Sans guillemets, un shell qui lirait le fichier prendrait le deuxième mot pour une commande.

Les valeurs réelles n'apparaissent dans aucun document du dépôt.

## Renouveler

Avant l'expiration :

1. créer un nouveau jeton avec les mêmes portées ;
2. remplacer `GITEA_TOKEN` dans `.env` ;
3. **révoquer l'ancien jeton** dans la forge.

## En cas de fuite

Si le jeton a pu apparaître ailleurs que dans `.env` (fichier, commit, sortie de terminal partagée, conversation) :

1. **révoquer immédiatement** le jeton dans la forge ;
2. en créer un nouveau et mettre à jour `.env` ;
3. si un commit est concerné : `scripts/check-private.sh history`, puis traiter l'historique **avant** tout push vers le miroir public.

## Vérifier sans afficher

`.env` est présent et ignoré :

```bash
test -f .env && git check-ignore -q .env && echo "présent et ignoré"
```

La présence des trois variables est contrôlée par les skills eux-mêmes au démarrage, sans afficher leur valeur.
