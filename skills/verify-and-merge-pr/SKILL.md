---
name: verify-and-merge-pr
description: Audite les cinq verrous de fusion d'une pull request (PR fusionnable, revue LLM, garde-fou, CI, suivi de sprint) avec l'outillage du dépôt commun de méthode et, avec --merge, la fusionne en squash vers la base du projet si tous passent. À utiliser avant toute fusion ; --merge seulement quand la règle de fusion du projet l'autorise.
---

# verify-and-merge-pr

Audit des verrous de fusion d'une PR vers la base du projet (`forge.base`), puis fusion en squash avec `--merge`.

La procédure fait foi : `.working-method/procedures/verify-and-merge-pr.md`. L'exécution est `.working-method/gates/verify-and-merge-pr.sh`, lancée depuis la racine du projet. Ce que chaque verrou lit (exception documentaire, garde-fou, workflow de CI, suivi de sprint) se déclare dans le `workflow.config` du projet ; un verrou désactivé s'affiche « inactif ».

À retenir :

- lance l'audit (`<numéro de PR>`) autant que nécessaire : il ne fusionne rien ;
- ne lance `--merge` que si la règle de fusion du projet l'autorise pour cette PR (décision humaine, ou délégation écrite dans l'`AGENTS.md` du projet) ;
- une PR vers la branche de publication ne passe jamais par ce skill ;
- un verrou bloquant se corrige, puis on relance ; il n'existe aucun moyen de forcer la fusion.
