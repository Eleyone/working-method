---
name: sprint-consistency
description: Vérifie que le suivi de sprint (sprint-status.yaml) et les fichiers de story du dépôt eleyone.fr disent la même chose, et qu'une story est à done avant la fusion de sa PR. À utiliser avant chaque commit de statut d'une story et avant toute fusion.
---

# sprint-consistency

Contrôle de cohérence entre `_bmad-output/implementation-artifacts/sprint-status.yaml` et les fichiers de story.

La procédure fait foi : `docs/procedures/sprint-consistency.md`. L'exécution est `scripts/sprint-consistency.sh`.

À retenir :

- avant chaque commit de statut : contrôle global, sans option ;
- avant la fusion d'une PR de story : `--merge <n.m>`, avec `--rev <SHA de tête>` pour lire exactement la tête de la PR ;
- seul le code de sortie `0` vaut cohérence ; un écart se corrige du côté faux (suivi par l'outil de planification, ligne `Status:` du fichier de story), puis on relance.
