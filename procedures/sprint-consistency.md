# Procédure — Cohérence du suivi de sprint

Aucune PR n'est fusionnée sur une story mal suivie. `gates/sprint-consistency.sh` (dépôt commun ; `.working-method/gates/sprint-consistency.sh` depuis un projet) vérifie que le suivi de sprint (`sprint.status-file` du `workflow.config` du projet, dans le projet source `_bmad-output/implementation-artifacts/sprint-status.yaml`) et les fichiers de story (`sprint.stories-dir`) disent la même chose. En v1, il ne vérifie que les statuts, pas les branches (D-17 du projet source).

Il sert deux conventions (`sprint.convention`) : **`numbered`**, clés `<n>-<m>-<titre>`, epics `epic-<n>` ; **`keyed`**, clés kebab-case libres et bloc `aliases:` (§ *Convention keyed*). `none` : le script dit que le suivi est désactivé, sort en `0` **sans affirmer de cohérence**, et refuse `--merge` en `2`.

## Quand le lancer

- **Avant chaque commit de statut** d'une story (`in-progress`, `review`, `done`) : contrôle global.
- **Avant la fusion d'une PR de story** : `--merge <n.m>` (`keyed` : `--merge <clé>`), sur la tête de la PR. C'est le verrou de suivi de `verify-and-merge-pr`, qui tire la story du nom de la branche (`chore/0-6-…` → `0.6` ; `keyed` : § *Convention keyed*).
- **En CI**, dès qu'elle existe : contrôle global. Une story `in-progress` ou `review` n'est jamais un écart en soi : le contrôle passe pendant tout le développement.

## Lancer

```bash
.working-method/gates/sprint-consistency.sh                          # contrôle global de l'arbre de travail
.working-method/gates/sprint-consistency.sh --merge 0.6              # en plus, la story 0.6 est à done des deux côtés
.working-method/gates/sprint-consistency.sh --merge 0.6 --rev <SHA>  # lit le suivi et les fichiers dans ce commit
```

Code de sortie : `0` cohérent (ou suivi désactivé, et le message le dit) ; `1` au moins un écart ; `2` contrôle impossible (usage, `workflow.config` refusé, convention inconnue, suivi absent ou vide, commit introuvable, liste ou fichier de story illisible). Seul `0` vaut cohérence.

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

Le script ne remplace pas `validate` de l'outil de planification BMAD, qui vérifie la structure du fichier de suivi ; il est écrit en bash seul, sans Python ni outil YAML ni option propre aux outils GNU, pour tourner en CI comme sur le poste. Sa lecture du suivi est celle de `lib/sprint.sh`, commune avec `llm-review` et `verify-and-merge-pr`, et testée par `tests/run.sh` (`shell-scripts.md`).

Il lit aussi, quand elle existe, la section `open_questions` du suivi (extension du projet source) : chaque entrée commence par `- id:` et porte `id`, `epic`, `question`, `state` et `lands_in`, non vides. Un suivi sans cette section n'est pas un écart.

## Convention keyed

Règles reprises sans changement du contrôle d'origine (`calculette#outillage-5`), et rejouées sur les
têtes de PR réelles de son projet avec le même verdict. Elles remplacent celles de la section précédente,
sauf la lecture de `open_questions`, commune aux deux conventions.

- **Clés** : kebab-case libres. `epic-<nom>` est un epic ; une clé qui finit par `-retrospective` est
  une rétrospective ; toute autre clé est une story.
- **Statuts** : vocabulaire des stories et des epics comme en `numbered` ; rétrospectives `optional` ou
  `done`. Rien ne relie une story à son epic : le statut d'un epic n'est vérifié que contre le
  vocabulaire.
- **Fichiers de story** : chaque fichier `.md` du dossier des stories, sauf ceux que nomme
  `sprint.non-story-files` (schéma 4). Il se rattache à sa clé **directement** (même nom) ou **par le bloc
  `aliases:`** du suivi (`<nom du fichier sans .md>: <clé>`).
- **En-tête** : la première ligne qui se lit `Status: <statut>`, `status: '<statut>'` ou
  `**Status**: <statut>`, commentaire de fin de ligne admis.

Est un écart : un statut hors vocabulaire ; un alias dont la cible n'est pas une clé ; un fichier sans
clé, ni directe ni par alias ; un fichier dont le nom est à la fois une clé et un alias (rattachement
ambigu, à trancher à la main) ; un fichier sans en-tête lisible, à un statut hors vocabulaire, ou qui
diffère du suivi ; avec `--merge <clé>`, la story absente du suivi, pas à `done`, ou sans fichier de
story. ⚠️ Une entrée du suivi **sans fichier** n'est pas un écart : le suivi d'origine (`calculette#outillage-5`) en
compte des dizaines, écrites avant les fichiers de story.

**Un premier suivi, pour un projet qui n'en a pas** (troisième adoption, calculette#outillage-16) : le
contrôle exige une section `development_status` non vide, et rien d'autre. Le plus petit suivi valide
porte un epic, et s'ajoute dans la PR d'adoption (exemption d'amorçage du verrou de suivi,
`verify-and-merge-pr.md`) :

```yaml
development_status:
  epic-outillage: backlog
```

Les stories s'y ajoutent ensuite, une ligne par story, dans la PR de chacune.

**La story d'une branche** (`verify-and-merge-pr`, `llm-review`) : le nom de branche, préfixe ôté
(`feat/outillage-4-x` → `outillage-4-x`) ou recollé (`fix/plafond` → `fix-plafond`), résolu comme un nom
de fichier. Une seule forme doit aboutir ; aucune : contrôle global ; deux : ambiguïté.

## En cas d'écart

Le script liste chaque écart sur une ligne. Corriger le côté faux :

- **le suivi** : par l'outil de planification (`--set <clé>=<statut>`), jamais à la main ;
- **le fichier de story** : sa ligne `Status:`, dans le même commit que le suivi ;
- **l'epic** : dans le commit qui fait changer ses stories de palier (première story commencée, dernière story terminée).

Puis relancer le contrôle.
