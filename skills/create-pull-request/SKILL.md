---
name: create-pull-request
description: Ouvre la pull request de la branche courante sur la forge Gitea du dépôt eleyone.fr, par l'API REST, vers dev (branches feat/, fix/, chore/, docs/). À utiliser quand une story ou un correctif est commité, poussé et prêt à passer en revue.
---

# create-pull-request

Ouvre la PR de la branche courante vers `dev`.

La procédure fait foi : `docs/procedures/create-pull-request.md`. L'exécution est `scripts/create-pull-request.sh`.

À retenir :

- tout est commité et la branche est poussée avant de lancer le script ;
- écris le corps dans `.pr-body.md` à la racine du dépôt (ignoré par git, réutilisé d'une PR à l'autre : réécris-le entièrement pour chaque PR), puis lance le script avec `--title "<titre>"` ;
- n'ouvre jamais de PR vers `main` : c'est le rôle de `release` ou de `hotfix` ;
- n'affiche ni ne copie jamais le jeton ni l'adresse de la forge ; le script ne donne que le numéro de la PR ;
- un refus n'ouvre rien : corrige la cause indiquée, puis relance.
