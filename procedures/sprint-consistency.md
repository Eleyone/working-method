# Procédure — Cohérence du suivi de sprint

Aucune PR n'est fusionnée sur une story mal suivie (AD-24). `scripts/sprint-consistency.sh` vérifie que le suivi de sprint (`_bmad-output/implementation-artifacts/sprint-status.yaml`) et les fichiers de story du même dossier disent la même chose. En v1, il ne vérifie que les statuts, pas les branches (D-17).

## Quand le lancer

- **Avant chaque commit de statut** d'une story (`in-progress`, `review`, `done`) : contrôle global.
- **Avant la fusion d'une PR de story** : `--merge <n.m>`, sur la tête de la PR. C'est le verrou de suivi de `verify-and-merge-pr` (story 0.7), qui tire le numéro de la story du nom de la branche (`chore/0-6-…` → `0.6`).
- **En CI**, dès qu'elle existe : contrôle global. Une story `in-progress` ou `review` n'est jamais un écart en soi : le contrôle passe pendant tout le développement.

## Lancer

```bash
scripts/sprint-consistency.sh                          # contrôle global de l'arbre de travail
scripts/sprint-consistency.sh --merge 0.6              # en plus, la story 0.6 est à done des deux côtés
scripts/sprint-consistency.sh --merge 0.6 --rev <SHA>  # lit le suivi et les fichiers dans ce commit
```

Code de sortie : `0` cohérent ; `1` au moins un écart ; `2` contrôle impossible (usage, suivi absent ou vide, commit introuvable, liste des fichiers de story illisible). Seul `0` vaut cohérence.

## Ce qu'il vérifie

Il lit la seule section `development_status` du suivi, quelle que soit l'indentation de ses lignes : les epics (`epic-<n>`), les stories (`<n>-<m>-<titre>`) et les rétrospectives (`epic-<n>-retrospective`, non vérifiées). Seuls les fichiers comptent comme fichiers de story : un dossier nommé `*.md` est ignoré, dans l'arbre de travail comme avec `--rev`.

Est un écart :

1. une story hors `backlog` sans fichier de story `<clé>.md` ;
2. un fichier de story sans entrée dans le suivi ;
3. un fichier de story dont la première ligne `Status:` manque, est mal écrite (par exemple `status:` ou `Status : done`), porte une valeur hors vocabulaire, ou diffère du suivi ;
4. un statut de story hors vocabulaire (`backlog`, `ready-for-dev`, `in-progress`, `review`, `done`), ou d'epic hors vocabulaire (`backlog`, `in-progress`, `done`) ;
5. un epic dont le statut ne correspond pas à ses stories : `backlog` si aucune n'a commencé (`backlog` ou `ready-for-dev`), `done` si toutes sont à `done`, `in-progress` sinon ; un epic sans aucune story dans le suivi, ou des stories dont l'epic n'a pas de ligne dans le suivi, sont aussi des écarts ;
6. une clé non reconnue dans `development_status` ;
7. avec `--merge <n.m>` : la story absente du suivi, présente sous plusieurs clés, pas à `done`, ou sans fichier de story.

Tolérances :

- une story en `backlog` peut avoir un fichier de story s'il porte `Status: backlog` : la revue de spec (`llm-review --story`) crée ce fichier avant le premier commit de la story ;
- seule la première ligne `Status:` du fichier compte : les rapports de revue ajoutés plus bas peuvent en citer d'autres.

Si le suivi est absent, si sa section `development_status` est vide, ou si la liste des fichiers de story ne peut pas être lue, le script le dit et sort en échec : il ne conclut jamais à la cohérence sans avoir tout lu.

Le script ne remplace pas `validate` de l'outil de planification BMAD, qui vérifie la structure du fichier de suivi ; il est écrit en bash seul, sans Python ni outil YAML ni option propre aux outils GNU, pour tourner en CI comme sur le poste. Sa lecture du suivi est celle de `scripts/lib/sprint.sh`, commune avec `llm-review` et `verify-and-merge-pr`, et testée par `scripts/tests/run.sh` (`shell-scripts.md`).

## En cas d'écart

Le script liste chaque écart sur une ligne. Corriger le côté faux :

- **le suivi** : par l'outil de planification (`--set <clé>=<statut>`), jamais à la main ;
- **le fichier de story** : sa ligne `Status:`, dans le même commit que le suivi ;
- **l'epic** : dans le commit qui fait changer ses stories de palier (première story commencée, dernière story terminée).

Puis relancer le contrôle.
