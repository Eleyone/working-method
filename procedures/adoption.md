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

**Relever aussi la protection des branches** (`GET /repos/<forge.repo>/branch_protections`) et les styles de fusion admis (`GET /repos/<forge.repo>`) : la story d'adoption note ce qu'elle trouve, sans rien changer. Une règle de protection commune (branche de travail et branche de publication), appliquée à l'adoption et vérifiée par un contrôle, est à venir (`calculette#fix-protection-branches-dev-master`) ; d'ici là, un écart se note et se signale (constat de la quatrième adoption : aucune règle de protection, et la fusion par commit de fusion interdite, alors que la publication du projet en aura besoin).

## 1. Ajouter le sous-module

```bash
git submodule add <adresse du dépôt commun> .working-method
```

- Le chemin conseillé est **`.working-method`** : c'est le point d'entrée que citent les stubs de skills et le bloc commun d'`AGENTS.md`. Un autre chemin fonctionne : `bin/install` pose alors un lien `.working-method` vers lui.
- ⚠️ La forge exige une connexion pour lire (`REQUIRE_SIGNIN_VIEW`) : le clone du sous-module est **authentifié** partout — poste, CI, worktrees jetables, Renovate. Le miroir **public** d'un projet pointe son `.gitmodules` vers le miroir public du dépôt commun (`github-mirror.md`).

## 2. Écrire `workflow.config`

À la racine du projet, depuis `.working-method/workflow.config.example`, champ par champ (`workflow-config.md`). Chaque valeur que les scripts du projet lisaient en dur y entre : nom du dépôt, branches, préfixes, chemins du suivi de sprint, exception documentaire, garde-fou, workflow et contexte de CI, commande de contrôle.

- ⛔ Aucune valeur par défaut : le fichier est complet, ou il est refusé.
- Une fonction que le projet n'a pas se désactive par `none`, et l'outil le dit. ⛔ **Une fonction sans objet qu'on omet de désactiver n'est pas désactivée, elle est refusée** : un champ absent fait refuser le fichier en `2`, et un dossier de contrôles déclaré mais vide fait sortir `run-checks` en `2` (`check.md`). Le **motif** de chaque `none` s'écrit en commentaire à côté du champ, et l'`AGENTS.md` du projet les rassemble dans une table (champ, motif, ce qu'affiche l'outil) : les outils affichent la désactivation et la clé, pas le motif du projet (constat de la quatrième adoption, un dépôt sans code ni CI, calculette#outillage-17).
- Écrire aussi la **couche projet** de la revue (`review.project-layer`) : description, contexte, méthode de revue, contrôles propres (`llm-review.md`).
- **Le fichier des secrets du poste** (`forge.env-file`) doit être ignoré par git **et** exclu des images. Un projet qui **versionne** `.env` (convention de Symfony : valeurs de développement) en nomme un autre, déjà ignoré et exclu — `.env.local` par exemple —, et ne met pas `.env` dans `review.private-paths` : un chemin suivi est dans toute copie relue, et la revue serait refusée à chaque fois (constat de la troisième adoption, calculette#outillage-16).
- Ignorer `.pr-body.md` (corps de PR de `create-pull-request`, réécrit à chaque PR), à côté des fichiers générés de BMAD (étape 3).

## 3. Lancer `bin/install`

```bash
.working-method/bin/install
```

Il vérifie bash, valide `workflow.config`, vérifie BMAD (version, modules, `_bmad/config.user.toml`), puis pose `.working-method` (si besoin), un lien par skill commun et par skill BMAD des modules activés dans chaque dossier de `agents.skill-dirs`, la méthode BMAD dans `_bmad/` par liens, et génère la configuration BMAD (`bmad.md`). Il ne remplace rien, sauf la configuration générée — et il le signale.

- **Conflit** (code `1`, aucun lien posé) : le projet a déjà un skill du même nom. **Choisir et écrire** lequel sert — jamais deux skills homonymes qui se masquent. Si c'est le skill commun, retirer celui du projet dans la même PR, puis relancer ; si c'est celui du projet, `bin/install` refusera tant qu'il porte ce nom : la décision et sa mise en œuvre (renommer le skill du projet, par exemple) s'écrivent dans la story d'adoption.
- **Un module que l'union ne porte pas** (`wds`, déprécié en amont) : `bin/install` refuse de l'activer (`1`), et le projet s'en passe — il n'existe pas de module local (`bmad.md`). Son dossier `_bmad/<module>/` est un conflit, mais **ses skills ne sont pas reconnues** (elles n'ont pas le préfixe `bmad-`) : les relever dans le manifeste de l'ancien installeur (`_bmad/_config/skill-manifest.csv`) **avant** de le supprimer, et les supprimer à la main dans la même PR. Vérifier aussi qu'une skill du module n'a rien écrit hors du dépôt : la skill `sync` de wds recopiait ses skills dans `~/.claude/commands/` et `~/.claude/wds/`.
- **BMAD** (`bmad.md`, « Passer un projet sur le BMAD du sous-module ») : les copies locales de BMAD (skills `bmad-*` de chaque dossier d'outil, `_bmad/scripts`, tout le contenu de `_bmad/<module>/`, `_bmad/_config/`) sont **supprimées dans la même PR** ; sinon chacune est un conflit — y compris une copie **sans équivalent** dans la méthode du sous-module (un skill retiré en amont depuis la version copiée, un dossier de méthode d'une version antérieure, un manifeste de l'ancien installeur). Un installeur BMAD récent (6.6 et plus) écrit aussi `_bmad/config.toml`, que `bin/install` régénère, et `_bmad/config.user.toml` : s'il est suivi par git, il en sort (`git rm --cached`) et reste sur le poste comme couche utilisatrice. Écrire `_bmad/config.user.toml` (couche utilisatrice, jamais écrite par `bin/install`) et ignorer `_bmad/*/config.yaml` (générés, non versionnés) avant de lancer `bin/install`. ⛔ L'installeur BMAD ne se lance **jamais** dans le projet : il écrirait à travers les liens, dans le sous-module.
- **Skills homonymes dont le script commun ne sert pas encore le projet** (constaté à la deuxième adoption : une convention de suivi de sprint, ou une forme de rapport de revue, que l'outillage commun refuse en `2`). Le projet garde ses scripts et **renomme ses skills**, avec un préfixe propre au projet. Le skill commun reste relié et refuse en `2` ; l'`AGENTS.md` du projet dit lequel sert.
- **Réglages propres à un module BMAD** (par exemple les chemins d'artefacts ou le cadre de test d'un module de test) : ils vont dans les surcharges `[module "<nom>"]` de `workflow.config` (`workflow-config.md`, « Surcharges des modules BMAD »), jamais dans une édition du `config.yaml` généré.
- **Un script du projet qui recopie ses skills d'un dossier d'outil à l'autre doit ignorer les liens.** Sinon il remplace un lien par une copie, que `bin/install` refuse ensuite comme un conflit. Un dossier de skills qui est lui-même un lien vers le dossier d'un autre outil est accepté.
- **La suppression des copies touche des milliers de fichiers.**
  - Un `.gitattributes` (`-diff`) n'en montre que la liste à la revue.
  - Le gate de fusion du projet doit pourtant lire **toute** la liste des fichiers de la PR. Il la lit **page par page, jusqu'à une page vide** : la fin ne se déduit jamais d'une page plus courte que demandée, puisque Gitea rend au plus 50 entrées quel que soit `limit`. Au-delà d'un nombre maximal de pages, il **refuse**, jamais il ne fusionne sur une liste tronquée. Ce nombre doit couvrir la PR d'adoption, et le plafond qu'annonce le refus se calcule sur la taille de page réellement rendue. Le gate commun (`gates/verify-and-merge-pr.sh`) n'a pas ce problème : il lit la liste par `git diff --name-only` entre la base et la tête, sans l'API ; la règle vaut pour un gate propre au projet qui passe par l'API.
- Relancé, il ne change rien : les liens posés se commitent avec le reste.
- ⚠️ **Les liens doivent être suivis** par chaque outil d'agent visé (Claude Code, Cursor, Antigravity) : le vérifier en **chargeant une skill** dans chacun, pas en le supposant (AC 8).

## 4. Brancher les scripts du projet

- Les scripts du projet qui chargeaient une bibliothèque extraite la chargent depuis `.working-method/` : `lib/shell.sh`, `lib/dotenv.sh`, `lib/sprint.sh`, `gitea/gitea.sh` (qui exige désormais `lib/config.sh` chargé et `gitea_configure`), `gates/merge-gates.sh`.
- Les tests du projet chargent `.working-method/tests/lib.sh` et se lancent par `.working-method/tests/run.sh <fichiers>` ; `root` y reste la racine du projet, `fixtures` le dossier voisin du fichier de test.
- Le point d'entrée des contrôles garde ses étapes propres, puis appelle `.working-method/checks/run-checks.sh [-- <préfixe>]`.
- Les copies des fichiers extraits **disparaissent** du projet ; ⛔ aucun test n'est supprimé : un test qui suivait un fichier extrait tourne dans le dépôt commun, ou suit son nouveau chemin.

## 5. CI, worktrees jetables, Renovate

- **CI** : le checkout initialise le sous-module (`submodules: recursive`, authentifié), et le premier pas vérifie bash en `shell: sh` (`sh .working-method/bin/check-bash`). Un run sans sous-module **échoue** : il ne passe jamais en ignorant des fichiers manquants.
- **Réinstallation prouvée en CI** (recommandé). La couche utilisatrice n'est pas versionnée : le job écrit une `_bmad/config.user.toml` de CI, relance `bin/install`, puis exige un `git status` vide et aucun lien de skill mort. Cela suppose `_bmad/config.user.toml` et les `config.yaml` ignorés par git (étape 3).
- **Image** : un Dockerfile qui copie tout le contexte (`COPY . .`) **doit** exclure le sous-module par `.dockerignore`.
- **Worktrees jetables** (commit de clôture, revue) : `git submodule update --init` dans le worktree, pour que les gates y voient la même méthode que le poste. Le substitut d'amorçage de `verify-and-merge-pr` le fait lui-même dans sa copie de la tête, depuis les sous-modules du poste, sans réseau : ils doivent donc y être initialisés (`verify-and-merge-pr.md`, verrou 4).
- **Renovate** : `renovate.json` étend le preset partagé et **garde son propre `branchPrefix`** (`renovate.md`) ; une PR de montée du sous-module doit déclencher la CI du projet, vérifié sur le run. Si la CI ne se déclenche que sur certains préfixes de branche, la PR de montée doit en porter un.

  ⚠️ Renovate lit cette configuration sur la branche par défaut : l'étape 0 doit être faite, sinon le `renovate.json` de l'adoption n'agit qu'après une publication.

  ⚠️ **Un `renovate.json` ne suffit pas à faire servir le projet** : Renovate ne parcourt que les dépôts que son lanceur lui nomme (`RENOVATE_REPOSITORIES`, sans découverte automatique), et son compte doit pouvoir lire le projet. Ajouter le projet à cette liste, dans le dépôt qui porte le workflow de Renovate, et donner l'accès au compte du robot, sont deux gestes de l'adoption ; sans eux, aucune PR de montée n'est jamais ouverte (`renovate.md`).

## 6. `AGENTS.md`

Le bloc commun vit dans `.working-method/agents/AGENTS.common.md`. L'`AGENTS.md` du projet y renvoie en tête, et ne garde que ce qui est propre au projet. Le bloc est écrit **en français** (décision d'Arnaud du 04/10/2026) ; les commandes, les chemins et les identifiants y restent tels quels. **Forme de l'inclusion : le renvoi.** Les trois premières adoptions l'ont toutes retenue : l'`AGENTS.md` du projet nomme `.working-method/agents/AGENTS.common.md` en tête, et dit ce qui y déroge ; aucune copie du bloc n'entre dans un projet, si bien qu'aucun test n'a à vérifier qu'elle reste fidèle.

## 7. Prouver le comportement constant

Avant de supprimer les copies, rejouer `verify-and-merge-pr.sh` **en audit** sur des PR réelles du projet — au moins une conforme, une refusée par un gate, une exemptée — avec l'ancien script et avec le nouveau : même verdict, verrou par verrou. Un écart est un défaut de l'adoption, pas une amélioration.

Un projet qui n'avait **aucun** gate avant l'adoption n'a rien à rejouer : la story d'adoption le dit, et la première PR fusionnée par les gates communs (la PR d'adoption elle-même, étape 9) en tient lieu.

## 8. Monter le sous-module

Une montée est une PR du projet qui change le SHA du sous-module (ouverte par Renovate, ou à la main), et qui passe par les gates du projet. Si le schéma de `workflow.config` change, la PR de montée met le fichier à jour.

## 9. La PR d'adoption elle-même

Elle ne peut pas compter sur des gates que sa base n'a pas encore. Deux cas :

- **La base a déjà ses propres gates** (deuxième adoption) : la PR est relue et fusionnée par eux, **depuis la base à jour** — le gate qui juge est celui déjà fusionné, pas le code qu'il contrôle.
- **La base n'a aucun gate** (troisième adoption) : les scripts communs se lancent **depuis la branche de la PR**, sur le poste — `review/llm-review.sh <n>`, puis `gates/verify-and-merge-pr.sh <n> --merge`. Ce que la PR leur apporte, et que la revue lit dans le diff, est la configuration qu'ils lisent (`workflow.config`, la couche projet). Leur code doit être celui du dépôt commun déjà relu, jamais un code que la PR choisit : ⛔ **avant de les lancer**, vérifier que l'URL du sous-module dans `.gitmodules` de la PR désigne le dépôt commun, et que le commit épinglé est sur sa branche principale (`git -C .working-method merge-base --is-ancestor HEAD origin/main`, après un `fetch`). Une PR qui épinglerait un autre dépôt ou un commit hors de la branche principale ferait exécuter son propre code par le gate qui la juge.

- **Le projet n'a pas de CI, et n'en aura pas** (quatrième adoption : un dépôt de documents). `ci.workflow = none` (et ses trois champs liés), `ci.bootstrap = false` : il n'y a ni workflow à attendre ni contrôle à lancer à sa place, donc pas de substitut d'amorçage. Le verrou de CI s'affiche `inactif` à chaque fusion, ce qui n'est jamais une CI verte ; les verrous qui jugent sont la PR fusionnable et la revue sur le SHA de tête (plus le suivi et le garde-fou si le projet en a). La PR d'adoption suit le cas précédent (scripts lancés depuis la branche, sous-module épinglé vérifié sur la branche principale du dépôt commun), et l'`AGENTS.md` du projet écrit ce chemin pour toutes les PR suivantes.

  Côté forge, ensuite : le verrou de CI juge les statuts de la tête, le workflow de contrôles arrivant avec la PR ; le verrou de suivi admet la PR qui ajoute le fichier de suivi à une base qui ne l'a pas (exemption d'amorçage, `verify-and-merge-pr.md`). La story d'adoption écrit ce chemin avant de demander la revue.
