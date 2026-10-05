# working-method

Méthode de travail commune : outillage Gitea, revue LLM et gates de fusion, consommés en sous-module git par chaque projet. Il porte aussi BMAD : une seule version, installée ici seulement, reliée dans chaque projet par `bin/install` (`procedures/bmad.md`).

Ce dépôt ne connaît aucun projet : tout ce qui est propre à un projet se déclare dans le `workflow.config` de ce projet (`procedures/workflow-config.md`). Il est public, et sa CI vérifie qu'il ne contient ni secret ni nom de projet consommateur (`procedures/secrets.md`).

## Contenu

| Dossier | Rôle |
|---|---|
| `bin/` | `install` (installation dans un projet, `procedures/adoption.md`), `check-bash` (prérequis bash 4.3, en POSIX sh) |
| `lib/` | bibliothèques : `config.sh` (lecteur de `workflow.config`), `bmad.sh` (version de BMAD, configuration générée), `shell.sh`, `dotenv.sh`, `sprint.sh`, `require-bash.sh` |
| `bmad/` | BMAD : `bmad.config` (version, modules, épinglages), `update.sh` (le seul endroit où l'installeur BMAD tourne), `method/` (ce qu'il produit, relié dans chaque projet ; `procedures/bmad.md`) |
| `gitea/` | adaptateur de la forge (`gitea.sh`) et ouverture de PR (`create-pull-request.sh`) |
| `gates/` | verrous de fusion (`verify-and-merge-pr.sh`, `merge-gates.sh`) et cohérence du suivi de sprint (`sprint-consistency.sh`) |
| `review/` | revue par un LLM d'un autre fournisseur (`llm-review.sh`), consignes communes (`prompts/`), couche projet de ce dépôt (`self-layer.md`) |
| `checks/` | mécanisme des contrôles bloquants d'un projet (`run-checks.sh`) |
| `ci/` | job de CI de ce dépôt, contrôles « aucun secret » et « aucun nom de projet », fourniture de `jq` et de `shellcheck` épinglés |
| `tests/` | harnais de test hors ligne (`run.sh`, `lib.sh`) et tests de tout ce qui précède |
| `procedures/` | une procédure par outil ; `adoption.md` pour un nouveau projet |
| `skills/` | stubs de skills, reliés dans chaque projet par `bin/install` |
| `agents/` | bloc commun d'`AGENTS.md` |
| `renovate/` | preset Renovate partagé (`procedures/renovate.md`) |

## Origine

Extrait le 03/10/2026, avec l'historique utile, du premier projet qui portait cet outillage (story outillage-14, phase B). Les renvois de PR de l'historique importé s'écrivent `(<projet source>#N)` : ils désignent les PR de ce projet-là, pas celles de ce dépôt.

## Contribuer

Toute modification passe par une PR vers `main` : revue par un LLM d'un autre fournisseur (`review/llm-review.sh`), CI verte (workflow `checks`), puis `gates/verify-and-merge-pr.sh`. `main` refuse tout push direct.

```bash
bash ci/checks-job.sh      # ce que lance la CI : tests, aucun secret, aucun nom de projet, shellcheck
```
