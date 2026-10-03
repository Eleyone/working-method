---
name: create-pull-request
description: Ouvre la pull request de la branche courante sur la forge Gitea, par l'API REST, vers la base du projet (forge.base de workflow.config), avec l'outillage du dépôt commun de méthode. À utiliser quand une story ou un correctif est commité, poussé et prêt à passer en revue.
---

# create-pull-request

Ouvre la PR de la branche courante vers la base du projet.

La procédure fait foi : `.working-method/procedures/create-pull-request.md`. L'exécution est `.working-method/gitea/create-pull-request.sh`, lancée depuis la racine du projet. Les préfixes de branche admis, la base et la branche de publication se lisent dans le `workflow.config` du projet.

À retenir :

- tout est commité et la branche est poussée avant de lancer le script ;
- écris le corps dans `.pr-body.md` à la racine du dépôt (ignoré par git, réutilisé d'une PR à l'autre : réécris-le entièrement pour chaque PR), puis lance le script avec `--title "<titre>"` ;
- n'ouvre jamais de PR vers la branche de publication (`forge.release-branch`) : la publication a son propre chemin ;
- n'affiche ni ne copie jamais le jeton ni l'adresse de la forge ; le script ne donne que le numéro de la PR ;
- un refus n'ouvre rien : corrige la cause indiquée, puis relance.
