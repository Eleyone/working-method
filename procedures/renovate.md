# Procédure — Preset Renovate partagé

Le dépôt commun publie `renovate/default.json`, un preset que chaque projet **étend** dans son propre `renovate.json`.

## Ce que fait le preset

- Il **active le manager `git-submodules`**, désactivé par défaut dans Renovate : sans lui, aucune PR de montée du sous-module n'est jamais ouverte.
- ⛔ Il **ne fixe pas `branchPrefix`** (décision du 30/09/2026). Le préfixe de branche dépend des déclencheurs de la CI de **chaque** projet : un préfixe imposé par le preset ferait ouvrir des PR sur lesquelles **aucune CI ne démarre**, donc des gates muets. Chaque projet déclare le sien. Un cas de `tests/test-ci-checks.sh` refuse tout `branchPrefix` dans le preset, à quelque niveau que ce soit.

## Dans un projet

```json
{
  "extends": ["local>Eleyone/working-method//renovate/default"],
  "branchPrefix": "<préfixe que la CI du projet déclenche>"
}
```

`local>` désigne un dépôt de la même forge que le projet ; `//renovate/default` le fichier `renovate/default.json` de ce dépôt.

⛔ **Une PR de montée sans job lancé est un échec, pas un succès** (AC 10 de la story outillage-14) : après l'adoption, faire ouvrir une PR de montée du sous-module par Renovate sur une branche d'essai, et vérifier **sur le run** que la CI du projet a démarré et que ses gates ont tourné.

⚠️ La forge exige une connexion pour lire (`REQUIRE_SIGNIN_VIEW`) : le compte de Renovate doit pouvoir lire ce dépôt, sans quoi il ne trouve ni le preset ni les commits du sous-module.
