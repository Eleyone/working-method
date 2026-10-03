# Procédure — Miroir public GitHub du dépôt commun

**Pourquoi** (décision du 03/10/2026) : la forge garde `REQUIRE_SIGNIN_VIEW`, si bien que ce dépôt, quoique public, ne se clone pas sans compte. Un projet dont le dépôt public vit sur GitHub ne pourrait donc pas initialiser son sous-module. Le miroir public de ce dépôt sur GitHub lève l'obstacle : le `.gitmodules` du miroir public d'un projet pointe vers lui.

La forge reste la source ; GitHub n'est qu'un miroir en lecture. Rien n'est poussé à la main vers GitHub : seul le miroir de Gitea y écrit. Modèle : la procédure de miroir du projet source, éprouvée (story 1.4 du projet source).

⛔ **Opération du propriétaire du compte GitHub**, pas d'un agent : elle exige un compte, un jeton et des réglages que l'agent n'a pas. **Rien du compte ne s'écrit ici** : ni jeton, ni nom d'hôte, ni chemin de machine. Le jeton du miroir ne vit que dans Gitea.

## Avant d'activer

Un commit poussé sur GitHub reste accessible par son SHA, même après un push forcé. Donc, juste avant l'activation, depuis un clone frais de la forge :

```bash
git clone --mirror <adresse du dépôt sur la forge> /tmp/audit-miroir.git
git clone /tmp/audit-miroir.git /tmp/audit-miroir && cd /tmp/audit-miroir
bash ci/check-secrets.sh            # arbre et historique de toutes les références : code 0 attendu
bash ci/check-names.sh              # aucun nom de projet consommateur dans l'arbre : code 0 attendu
```

Un signalement : ne pas activer le miroir.

## Identité du miroir

Gitea ne sait pas pousser un miroir en SSH : la clé de déploiement est écartée.

- **Compte machine GitHub**, distinct du compte personnel, invité comme **collaborateur en écriture** sur ce seul dépôt. Le compte machine qui sert déjà au miroir du projet source peut servir ici : il est fait pour ça, et n'est invité nulle part ailleurs.
- **Jeton classique dédié**, créé sur ce compte machine pour ce miroir, avec la seule portée **`public_repo`**. La portée `workflow` n'est **pas** nécessaire : ce dépôt n'a pas de dossier `.github/workflows/` ; elle le deviendrait le jour où il en aurait un. Ni `repo`, ni `admin:*`, ni `delete_repo`, ni `gist`, ni `user`. Noter la date d'expiration.
- Un **jeton à grain fin ne convient pas** : il ne cible que les dépôts de son propriétaire de ressources, et le compte machine n'est que collaborateur d'un dépôt qui appartient au compte personnel.
- Portée réelle du risque : un jeton classique `public_repo` peut écrire sur **tous** les dépôts publics auxquels le compte machine a accès — d'où un compte machine invité sur les seuls dépôts mirrorés.
- Le jeton personnel du propriétaire ne sert jamais au miroir : GitHub ne saurait plus distinguer le miroir d'un push humain, et le refus d'un push direct deviendrait invérifiable.

## Installer

1. **Dépôt public** : créer sur GitHub un dépôt **public**, du même nom que sur la forge (`working-method`), **vide** (ni README, ni licence, ni `.gitignore`), avec `main` en branche par défaut.
2. **Compte machine** : l'inviter comme collaborateur en écriture ; accepter l'invitation depuis ce compte.
3. **Jeton** : sur le compte machine, créer le jeton classique (`public_repo` seulement), noter son expiration, et ne le coller que dans Gitea à l'étape 5.
4. **Rulesets**, sur le dépôt GitHub :
   - *toutes les branches et tous les tags* : restreindre la création, la mise à jour et la suppression ; **contournement : le compte machine désigné nommément** (« users »), jamais un rôle — un contournement par rôle couvre aussi le propriétaire, dont le push direct passerait alors ;
   - *`main` seulement* : « Block force pushes », **sans aucun contournement** : `main` n'est jamais réécrite.
5. **Miroir dans Gitea** : réglages du dépôt `working-method` sur la forge → **Miroirs** → ajouter un **miroir push** :
   - adresse : `https://github.com/<compte>/working-method.git` ;
   - identifiant : le compte machine ; mot de passe : le jeton ;
   - cocher **« synchroniser à chaque push »** ; intervalle de repli : `8h`.

   Équivalent par l'API (le jeton ne passe que par un fichier de corps lu par `curl --data @`, jamais par une ligne de commande, et ce fichier est supprimé aussitôt) :

   ```
   POST /api/v1/repos/<propriétaire>/working-method/push_mirrors
   {"remote_address": "https://github.com/<compte>/working-method.git",
    "remote_username": "<compte machine>", "remote_password": "<jeton>",
    "interval": "8h0m0s", "sync_on_commit": true}
   ```

   Puis lancer une synchronisation : `POST /api/v1/repos/<propriétaire>/working-method/push_mirrors-sync`.

## Vérifier

1. **Références poussées** : `git ls-remote` de la forge et de GitHub ; `main` porte le même SHA des deux côtés. `GET /api/v1/repos/<propriétaire>/working-method/push_mirrors` : `last_error` vide.
2. **Audit du dépôt public** : les deux commandes d'« Avant d'activer », depuis un clone frais **de GitHub**, sans authentification — c'est ce que le miroir doit permettre.
3. **Clone anonyme** : `git clone https://github.com/<compte>/working-method.git` dans un dossier jetable, sans identifiants. Attendu : succès.
4. **Push direct refusé** : depuis le compte personnel, pousser un commit sans intérêt sur une branche jetable de GitHub. Attendu : refus par le ruleset. Le miroir, lui, continue de synchroniser.
5. **Sous-module** : dans un clone jetable du miroir public d'un projet, `git submodule update --init` avec un `.gitmodules` pointant vers GitHub. Attendu : succès sans authentification (phase C de la story outillage-14).

## Entretenir

- **Expiration du jeton** : avant la date notée, créer un nouveau jeton (même portée), le coller dans le miroir de Gitea, vérifier une synchronisation, puis révoquer l'ancien. Un miroir en échec se voit dans les réglages du dépôt sur la forge.
- **Suppression d'une branche** : la synchronisation « à chaque push » ne se déclenche pas sur une suppression (constat du projet source) ; la branche reste visible sur GitHub jusqu'à la synchronisation suivante. Ce n'est pas une panne.
- **`refs/pull/*`** : GitHub refuse ces références cachées. Si la synchronisation échoue sur elles, constater ce qui a tout de même été poussé, et décider : accepter cet échec partiel, ou remplacer le miroir par un hook côté forge qui ne pousse que `refs/heads/*` et `refs/tags/*`.
