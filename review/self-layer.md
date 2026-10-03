## Projet

Le dépôt commun de méthode de travail : l'outillage partagé par plusieurs projets et consommé par chacun en sous-module git — bibliothèques bash (`lib/`), adaptateur de la forge Gitea (`gitea/`), gates de fusion (`gates/`), revue par un LLM d'un autre fournisseur (`review/`), mécanisme des contrôles (`checks/`), installation (`bin/`), CI (`ci/`, `.gitea/workflows/`), procédures (`procedures/`), stubs de skills (`skills/`), bloc commun d'`AGENTS.md` (`agents/`), preset Renovate (`renovate/`). Ce dépôt est public : il ne contient aucun secret ni aucun nom de projet consommateur.

## Contexte

`README.md` ; `procedures/workflow-config.md` (format et contrat de `workflow.config`, le seul endroit où un projet déclare ce qui lui est propre) ; `procedures/shell-scripts.md` (règles d'écriture et pièges connus des scripts) ; les procédures de `procedures/` qui décrivent chaque script ; `agents/AGENTS.common.md` ; les tests de `tests/`.

## Méthode de revue

Aucun skill de revue n'est installé dans ce dépôt. Applique toi-même les lentilles demandées, une à une, en les nommant dans ton rapport :

- **edge-case-hunter** : chaque branche, chaque condition limite et chaque entrée qu'aucun chemin du code ne traite (valeur vide, absente, en double, `none`, chemin avec espace, sortie d'erreur d'un outil, code de retour 2 d'un `grep`) ;
- **verification-gap** : chaque affirmation (commentaire, procédure, message) que rien ne vérifie, et chaque garde qu'aucun test n'exerce sur l'entrée qu'elle doit refuser ;
- **structure**, **prose** (documents) : clarté, ambiguïté, ordre des idées ; une procédure ne décrit rien que son script ne fasse ;
- **adversarial** : ce qui, laissé tel quel, ferait passer une PR qui aurait dû être bloquée.

## Contrôles du projet

- **Comportement constant** : ce dépôt est extrait d'un projet source ; un changement de verdict d'une gate qui n'est pas exigé par le paramétrage est un défaut, pas une amélioration.
- **Jamais de valeur par défaut** : un champ de `workflow.config` absent, inconnu, en double, vide ou mal typé fait sortir en `2` ; une fonction désactivée par `none` le dit, et ne passe jamais pour verte.
- **Aucun nom de projet consommateur ni aucun secret** dans l'arbre ; aucun script ne peut afficher un secret ou l'adresse de la forge.
- **Skill, procédure et script concordent** : une procédure ne cite aucune commande absente de son script, un skill ne décrit aucune étape absente de sa procédure.
- **Scripts shell** : aucune erreur ne passe en silence sous `set -euo pipefail` ; chaque garde a un test qui échoue sans elle.
- **bash 4.3 au minimum** : aucune construction plus récente sans garde.
