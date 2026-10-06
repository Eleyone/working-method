---
name: sprint-consistency
description: Vérifie que le suivi de sprint (sprint-status.yaml) et les fichiers de story disent la même chose, et qu'une story est à done avant la fusion de sa PR, avec l'outillage du dépôt commun de méthode. À utiliser avant chaque commit de statut d'une story et avant toute fusion.
---

# sprint-consistency

Contrôle de cohérence entre le suivi de sprint et les fichiers de story, aux chemins que déclare le `workflow.config` du projet (`sprint.status-file`, `sprint.stories-dir`).

La procédure fait foi : `.working-method/procedures/sprint-consistency.md`. L'exécution est `.working-method/gates/sprint-consistency.sh`, lancée depuis la racine du projet.

À retenir :

- avant chaque commit de statut : contrôle global, sans option ;
- avant la fusion d'une PR de story : `--merge <n.m>` (convention `keyed` : `--merge <clé>`), avec `--rev <SHA de tête>` pour lire exactement la tête de la PR ;
- seul le code de sortie `0` vaut cohérence ; un écart se corrige du côté faux (suivi par l'outil de planification, ligne `Status:` du fichier de story), puis on relance ;
- un projet sans suivi de sprint (`sprint.convention = none`) le dit : le contrôle n'affirme alors aucune cohérence.
