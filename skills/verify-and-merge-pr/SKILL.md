---
name: verify-and-merge-pr
description: Audite les cinq verrous de fusion d'une pull request du dépôt eleyone.fr (PR fusionnable, revue LLM, garde-fou, CI, suivi de sprint) et, avec --merge, la fusionne en squash vers dev si tous passent. À utiliser avant toute fusion ; --merge seulement après l'autorisation explicite d'Arnaud.
---

# verify-and-merge-pr

Audit des verrous de fusion d'une PR vers `dev`, puis fusion en squash avec `--merge`.

La procédure fait foi : `docs/procedures/verify-and-merge-pr.md`. L'exécution est `scripts/verify-and-merge-pr.sh`.

À retenir :

- lance l'audit (`<numéro de PR>`) autant que nécessaire : il ne fusionne rien ;
- ne lance `--merge` qu'après l'autorisation explicite d'Arnaud pour cette PR : fusionner est une décision humaine ;
- une PR vers `main` passe par `release` ou `hotfix`, jamais par ce skill ;
- un verrou bloquant se corrige, puis on relance ; il n'existe aucun moyen de forcer la fusion.
