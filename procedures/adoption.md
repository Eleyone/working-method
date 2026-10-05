# Procédure — Adopter le dépôt commun dans un projet

Écrite en phase B de la story outillage-14, **avant** la première adoption. ⚠️ Les stories d'adoption (le premier projet en phase C, puis les stories 15, 16 et 17) mesureront ce qu'elle oublie : chaque étape imprévue s'ajoute ici, dans la PR qui la découvre.

## Prérequis du poste

- bash 4.3 ou plus (`sh <sous-module>/bin/check-bash`), git, `jq`, `curl` ; `agy`, authentifié, pour la revue (`llm-review.md`).
- Un jeton personnel de la forge dans le fichier d'environnement du projet (`gitea-token.md`).

## 0. Réglages de la forge : la branche par défaut est la branche de travail

⛔ **La branche par défaut du dépôt est sa branche d'intégration** — `forge.base` du `workflow.config`, là où tout se développe —, pas la branche de publication. Règle posée le 04/10/2026, pour tous les projets ; chaque story d'adoption la relève et l'applique.

**Motif** : deux mécanismes lisent la branche par défaut, et seulement elle.

- **Renovate** lit sa configuration (`renovate.json`, et le preset qu'il étend) sur la branche par défaut. Si c'est la branche de publication, un correctif mergé dans la branche d'intégration n'agit qu'après une publication ; une PR de migration de configuration vise la branche de publication directement, hors du chemin normal. Constaté dans le projet source : une contrainte de version corrigée en intégration est restée fausse un mois, et la PR de migration proposait de la régresser.
- **Les `schedule:` de Gitea Actions** ne sont enregistrés que depuis la branche par défaut, au commit du **dernier push** sur elle (Gitea 1.27.3, `services/actions/notifier_helper.go`). Un cron ajouté ou corrigé en intégration ne part qu'une fois arrivé sur la branche par défaut.

**Appliquer, au moment de l'adoption** : dans l'interface de la forge (*Paramètres → Branches → Branche par défaut*), choisir la branche d'intégration. Puis relire la valeur affichée : elle doit être `forge.base`. La story d'adoption note la valeur avant et après, et la date.

⏳ **Instrumentation à venir** : un script du dépôt commun relèvera et appliquera ce réglage par l'API, avec ses tests (ticket ouvert dans le projet source, à reporter ici quand il sera livré). D'ici là, le geste est manuel, dans l'interface.

Ce que le changement déplace, à relire **avant** de l'appliquer, dans la story d'adoption :

- **Chaque cron** tourne ensuite avec la version de la branche d'intégration du workflow, sur un commit d'intégration. Un cron qui doit juger la **production** (audit de dépendances, contrôle des artefacts publiés) fait un checkout explicite de la branche de publication (`ref:`) ; un cron qui **supprime** quelque chose (purge de registre) porte une garde, puisqu'il perd le filtre de la publication.
- **`workflow_run`** : Gitea 1.27.3 exécute la version de la branche **par défaut** du workflow déclenché (`WorkflowRunStatusUpdate`, ref de la branche par défaut), quel que soit le filtre `branches:` — qui porte, lui, sur le run déclencheur.
- **Planifications existantes** : le changement dans l'interface les **supprime**, et annule les crons en cours ; aucun cron ne tourne avant le **push suivant** sur la nouvelle branche par défaut, qui les réenregistre depuis son commit. À vérifier après ce push : un run planifié dans l'onglet Actions, sur la branche d'intégration, au SHA de ce push. (Par l'API, Gitea 1.27.3 les laisse en place sur le dernier commit de l'ancienne branche, jusqu'au même push.)
- **Un run planifié ne pose aucun statut de commit** (`commit_status.go`, « don't create commit status for cron job ») : il se voit dans l'onglet Actions et par courriel, jamais sur un commit.
- **PR** : l'interface propose la branche par défaut comme base. Une PR de publication choisit sa base explicitement.
- **Clones existants** : leur `origin/HEAD` reste sur l'ancienne branche ; chaque poste le réaligne sur la nouvelle branche par défaut. Les scripts du dépôt commun nomment leurs branches et n'en dépendent pas.

Le retour arrière (même chemin, valeur inverse, et ce qu'il faut revérifier) s'écrit dans une note du projet, puisque l'opération est manuelle.

## 1. Ajouter le sous-module

```bash
git submodule add <adresse du dépôt commun> .working-method
```

- Le chemin conseillé est **`.working-method`** : c'est le point d'entrée que citent les stubs de skills et le bloc commun d'`AGENTS.md`. Un autre chemin fonctionne : `bin/install` pose alors un lien `.working-method` vers lui.
- ⚠️ La forge exige une connexion pour lire (`REQUIRE_SIGNIN_VIEW`) : le clone du sous-module est **authentifié** partout — poste, CI, worktrees jetables, Renovate. Le miroir **public** d'un projet pointe son `.gitmodules` vers le miroir public du dépôt commun (`github-mirror.md`).

## 2. Écrire `workflow.config`

À la racine du projet, depuis `.working-method/workflow.config.example`, champ par champ (`workflow-config.md`). Chaque valeur que les scripts du projet lisaient en dur y entre : nom du dépôt, branches, préfixes, chemins du suivi de sprint, exception documentaire, garde-fou, workflow et contexte de CI, commande de contrôle.

- ⛔ Aucune valeur par défaut : le fichier est complet, ou il est refusé.
- Une fonction que le projet n'a pas se désactive par `none`, et l'outil le dit.
- Écrire aussi la **couche projet** de la revue (`review.project-layer`) : description, contexte, méthode de revue, contrôles propres (`llm-review.md`).

## 3. Lancer `bin/install`

```bash
.working-method/bin/install
```

Il vérifie bash, valide `workflow.config`, vérifie BMAD (version, modules, `_bmad/config.user.toml`), puis pose `.working-method` (si besoin), un lien par skill commun et par skill BMAD des modules activés dans chaque dossier de `agents.skill-dirs`, la méthode BMAD dans `_bmad/` par liens, et génère la configuration BMAD (`bmad.md`). Il ne remplace rien, sauf la configuration générée — et il le signale.

- **Conflit** (code `1`, aucun lien posé) : le projet a déjà un skill du même nom. **Choisir et écrire** lequel sert — jamais deux skills homonymes qui se masquent. Si c'est le skill commun, retirer celui du projet dans la même PR, puis relancer ; si c'est celui du projet, `bin/install` refusera tant qu'il porte ce nom : la décision et sa mise en œuvre (renommer le skill du projet, par exemple) s'écrivent dans la story d'adoption.
- **BMAD** (`bmad.md`, « Passer un projet sur le BMAD du sous-module ») : les copies locales de BMAD (skills `bmad-*` de chaque dossier d'outil, `_bmad/scripts`, `_bmad/<module>/module-help.csv`, `_bmad/_config/`) sont **supprimées dans la même PR** ; sinon chacune est un conflit. Écrire `_bmad/config.user.toml` (couche utilisatrice, jamais écrite par `bin/install`) et ignorer `_bmad/*/config.yaml` (générés, non versionnés) avant de lancer `bin/install`. ⛔ L'installeur BMAD ne se lance **jamais** dans le projet : il écrirait à travers les liens, dans le sous-module.
- Relancé, il ne change rien : les liens posés se commitent avec le reste.
- ⚠️ **Les liens doivent être suivis** par chaque outil d'agent visé (Claude Code, Cursor, Antigravity) : le vérifier en **chargeant une skill** dans chacun, pas en le supposant (AC 8).

## 4. Brancher les scripts du projet

- Les scripts du projet qui chargeaient une bibliothèque extraite la chargent depuis `.working-method/` : `lib/shell.sh`, `lib/dotenv.sh`, `lib/sprint.sh`, `gitea/gitea.sh` (qui exige désormais `lib/config.sh` chargé et `gitea_configure`), `gates/merge-gates.sh`.
- Les tests du projet chargent `.working-method/tests/lib.sh` et se lancent par `.working-method/tests/run.sh <fichiers>` ; `root` y reste la racine du projet, `fixtures` le dossier voisin du fichier de test.
- Le point d'entrée des contrôles garde ses étapes propres, puis appelle `.working-method/checks/run-checks.sh [-- <préfixe>]`.
- Les copies des fichiers extraits **disparaissent** du projet ; ⛔ aucun test n'est supprimé : un test qui suivait un fichier extrait tourne dans le dépôt commun, ou suit son nouveau chemin.

## 5. CI, worktrees jetables, Renovate

- **CI** : le checkout initialise le sous-module (`submodules: recursive`, authentifié), et le premier pas vérifie bash en `shell: sh` (`sh .working-method/bin/check-bash`). Un run sans sous-module **échoue** : il ne passe jamais en ignorant des fichiers manquants.
- **Worktrees jetables** (commit de clôture, revue) : `git submodule update --init` dans le worktree, pour que les gates y voient la même méthode que le poste.
- **Renovate** : `renovate.json` étend le preset partagé et **garde son propre `branchPrefix`** (`renovate.md`) ; une PR de montée du sous-module doit déclencher la CI du projet, vérifié sur le run.

  ⚠️ Renovate lit cette configuration sur la branche par défaut : l'étape 0 doit être faite, sinon le `renovate.json` de l'adoption n'agit qu'après une publication.

## 6. `AGENTS.md`

Le bloc commun vit dans `.working-method/agents/AGENTS.common.md`. L'`AGENTS.md` du projet y renvoie en tête, et ne garde que ce qui est propre au projet. Le bloc est écrit **en français** (décision d'Arnaud du 04/10/2026) ; les commandes, les chemins et les identifiants y restent tels quels. La forme définitive de l'inclusion (renvoi ou copie vérifiée par un test) se tranche à la première adoption, et s'écrit ici.

## 7. Prouver le comportement constant

Avant de supprimer les copies, rejouer `verify-and-merge-pr.sh` **en audit** sur des PR réelles du projet — au moins une conforme, une refusée par un gate, une exemptée — avec l'ancien script et avec le nouveau : même verdict, verrou par verrou. Un écart est un défaut de l'adoption, pas une amélioration.

## 8. Monter le sous-module

Une montée est une PR du projet qui change le SHA du sous-module (ouverte par Renovate, ou à la main), et qui passe par les gates du projet. Si le schéma de `workflow.config` change, la PR de montée met le fichier à jour.
