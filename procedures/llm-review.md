# Procédure — Revue par un LLM d'un autre fournisseur

Aucune spec ni aucun merge ne repose sur la seule relecture du modèle qui a écrit le code. `review/llm-review.sh` (dépôt commun ; `.working-method/review/llm-review.sh` depuis un projet) fait relire, par un modèle d'un autre fournisseur, la spec d'une story avant son implémentation, puis le diff de sa PR avant la fusion. Il se lance depuis la racine du projet, dont il lit le `workflow.config` (`procedures/workflow-config.md`) : un champ absent ou invalide l'arrête en code `2`, avant tout envoi.

## Prérequis

- `agy` (Antigravity CLI) installé et authentifié : `agy models` répond. Opération manuelle d'Arnaud.
- `jq`, `curl` et `timeout` installés. Sans `jq`, le script s'arrête et indique `sudo apt install jq`.
- Pour la revue du code seulement : le fichier d'environnement du projet (`forge.env-file`, en général `.env`), avec `GITEA_URL`, `GITEA_USER` et `GITEA_TOKEN` (procédure `gitea-token.md`). La revue de spec n'appelle pas l'API et ne lit pas ce fichier.
- La couche projet (`review.project-layer`) : le fragment de consigne qui décrit le projet, son contexte, sa méthode de revue et ses contrôles propres. Absente ou vide, rien n'est envoyé.
- Si le projet a un garde-fou public/privé (`guard.command`), son fichier de motifs (`guard.patterns-file`, ou celui que désigne `PRIVATE_PATTERNS_FILE`), avec au moins un motif : rien n'est envoyé au relecteur sans audit. Sans garde-fou (`guard.command = none`), le script le dit sur sa sortie d'erreur, et n'audite rien.

## Relecteurs

Le relecteur vient toujours d'un autre fournisseur que l'auteur. Les modèles sont déclarés par le projet dans la table `review.reviewers` de son `workflow.config` (`workflow-config.md`, « La table des relecteurs ») : aucune option de la ligne de commande ne permet d'en changer.

- `AUTHOR_LLM` nomme le **fournisseur** de l'auteur, en minuscules : `claude` (la valeur par défaut, si la variable n'est pas posée), `gemini`, `gpt` (Codex et les autres agents GPT)… Le relecteur est le modèle de son entrée dans la table.
- ⛔ Un auteur **sans entrée** fait sortir la revue en code `2`, **avant tout appel** au relecteur ni à la forge : il n'existe pas de relecteur par défaut. Le message nomme les fournisseurs couverts. Pour un nouveau fournisseur, on ajoute une entrée à la table — jamais du code.
- ⛔ La table elle-même refuse (code `2`, au chargement) une entrée dont le relecteur est du même fournisseur que l'auteur : le fournisseur d'un modèle est le premier segment de son nom.

Exemple (valeurs du projet source, relevées le 14/09/2026, `agy` 1.2.2, et entrée GPT ajoutée le 05/10/2026) :

| Auteur (`AUTHOR_LLM`) | Entrée de la table | Relecteur |
|---|---|---|
| `claude` (défaut) | `claude=gemini-3.1-pro-high` | un modèle Gemini |
| `gemini` | `gemini=claude-opus-4-6-thinking` | un modèle Claude |
| `gpt` | `gpt=claude-opus-4-6-thinking` | un modèle Claude |

Le délai de la relecture est `review.timeout`, en secondes ; `agy` rend la main une minute avant.

Le relecteur applique la méthode de revue que nomme la couche projet — dans le projet source, le skill de revue BMAD `bmad-review`, qu'il lit comme un fichier dans la copie isolée. L'auteur ne relit jamais à sa place. `bmad-code-review` n'est pas utilisé : il s'arrête pour attendre des réponses.

## Consignes et couche projet

Les trois consignes sont communes et ne nomment aucun projet : `review/prompts/code.md` (revue du code), `review/prompts/spec.md` (revue de spec), `review/prompts/range.md` (revue de plage). Chacune se termine par le repère `{{PROJECT_LAYER}}`, où le script insère le fichier `review.project-layer` du projet. La couche projet porte ce que le projet source écrivait dans ses consignes :

- **Projet** : ce qu'est le dépôt relu ;
- **Contexte** : les fichiers utiles au relecteur (règles, architecture, suivi, procédures) ;
- **Méthode de revue** : le skill ou les lentilles à appliquer ;
- **Contrôles du projet** : les vérifications propres, ajoutées à la revue du code.

Les repères `{{WORKTREE}}`, `{{CONTENT}}`, `{{SHA}}`, `{{LENSES}}`, `{{PR}}`, `{{BRANCH}}`, `{{BASE}}` et `{{STORY}}` sont remplacés dans la couche projet comme dans la consigne. Exemple : `review/self-layer.md`, la couche du dépôt commun lui-même.

## Revue de spec, au début de chaque story

1. Créer la branche de la story, puis lancer :

   ```bash
   .working-method/review/llm-review.sh --story <n.m>
   .working-method/review/llm-review.sh --story <n.m> --context <fichier>
   ```

2. Le relecteur lit le texte de la story tel qu'il est dans `sprint.spec-source` sur la base (`forge.base`), sous l'en-tête `### Story n.m :`, avec les angles **adverse**, **structure** et **prose**. Il termine par une section « À trancher avant d'implémenter ».
3. Le script affiche le rapport et l'ajoute à la section « Revue de spec » du fichier de story (`<sprint.stories-dir>/<clé>.md`), qu'il crée s'il n'existe pas. Rien n'est publié sur la forge.
4. L'auteur trie chaque constat en ajoutant, sous le rapport, sa décision : corrigé dans la story, question tranchée par le responsable du projet, ou écarté avec sa raison. Puis il reformule la story et pose ses questions.

La revue de spec exige un suivi numéroté (`sprint.convention = numbered`) et une source (`sprint.spec-source`) : sans elle, le script le dit et sort en `2`.

## Revue du code, sur chaque PR

1. Après l'ouverture de la PR et le commit de statut `review`, depuis la branche de la PR, lancer :

   ```bash
   .working-method/review/llm-review.sh <numéro de PR>
   AUTHOR_LLM=gemini .working-method/review/llm-review.sh <numéro de PR>
   ```

2. Le relecteur lit le diff de la branche entière par rapport à sa base, au SHA de tête lu sur la forge, avec les angles **edge-case-hunter** et **verification-gap**, plus les **contrôles de la couche projet** (dans le projet source : critères d'acceptation, données privées et secrets, concordance entre skill, procédure et script, cohérence avec `AGENTS.md` et l'architecture, erreurs silencieuses dans les scripts). Une PR qui ne touche que des fichiers Markdown prend les angles **structure** et **prose** à la place des deux premiers.
3. Chaque constat est classé : **bloquant** s'il casse un critère d'acceptation, fait fuiter une donnée privée ou un secret, ou laisse passer une erreur en silence ; **non bloquant** sinon.
4. Le script publie le rapport en commentaire de la PR (`review.report = pr-comment` ; la valeur `file`, rapport versionné, viendra avec la story 8 et sort en `2` d'ici là), précédé de la ligne lue par `verify-and-merge-pr` :

   ```
   llm-review sha=<SHA de tête> base=<base> model=<modèle> verdict=<pass|block>
   ```

   Un verdict `block` se publie comme un `pass` : c'est un résultat, pas une erreur.
5. Si le projet suit ses stories (`sprint.convention = numbered`) et que la branche porte un numéro de story, le script ajoute aussi le rapport à la fin de la section « Revue du code » du fichier de story, si la branche courante est celle de la PR. L'auteur ajoute sous le rapport, sans le modifier, sa décision pour chaque constat : dans le commit de statut `done` après un `pass`, qui n'admet que des lignes ajoutées au fichier de story et à `deferred-work.md`, ou avec ses corrections après un `block`.

La revue dure plusieurs minutes, jusqu'à 15 : un agent la lance en arrière-plan et attend sa fin.

## Revue d'une plage, pour une rétrospective

```bash
.working-method/review/llm-review.sh --range "<premier>^..<dernier>" --out <fichier>
```

Relit le **diff complet d'une plage de commits** — un epic entier — pour trouver ce qu'aucune revue de story ne pouvait voir : une règle appliquée différemment d'une story à l'autre, du code dupliqué entre deux stories, une décision contredite par une story suivante, une couverture de test absente à leur frontière, un commentaire devenu faux, du code mort. Angles : `adversarial`, `edge-case-hunter`, `verification-gap`.

- **Rien n'est publié** : pas de commentaire de PR, pas de fichier de story. Le rapport va dans le fichier désigné par `--out`, ou sur la sortie standard. C'est la rétrospective qui le cite, constat par constat, après les avoir rejoués.
- **La plage est écrite telle qu'on la veut** : `A..B` exclut `A`, `A^..B` l'inclut. Pour un epic, c'est le commit qui précède la première story jusqu'au dernier.
- **Le diff écarte les chemins de `review.range-exclude`** (dans le projet source, `_bmad-output`) : le relecteur a les artefacts de cadrage dans la copie, au commit de fin, et leur volume noierait le code. `none` : rien n'est écarté.
- **La copie isolée est celle du commit de fin**, comme pour les autres modes, avec le même garde-fou lancé sur la plage avant l'envoi et le même jeton de lecture.

Ce mode remplace le script jetable écrit deux fois de suite pour les rétrospectives des epics 2 et 3 du projet source. À sa première exécution, il a trouvé quatre défauts réels dans du code déjà relu PR par PR — dont une enveloppe qui promettait d'arrêter le script et ne le pouvait pas en tête de pipeline.

## Rapports dans le fichier de story

Le script ajoute chaque rapport au fichier de story de l'arbre de travail, sans le commiter. Un rapport n'est jamais modifié ni supprimé : l'auteur n'ajoute que ses décisions, sous lui.

- **Après la revue de spec** : le tri de l'auteur s'ajoute sous le rapport, et le tout part dans le premier commit de la story (`in-progress`), avec la story réécrite.
- **Après un verdict `block`** : les décisions de l'auteur s'ajoutent sous le rapport, et rapport et décisions partent avec les corrections ; la nouvelle tête appelle une nouvelle revue, dont le rapport s'ajoutera après.
- **Après un verdict `pass`** : les décisions s'ajoutent sous le rapport, et le tout part dans le commit de statut `done`, qui n'admet que des lignes ajoutées au fichier de story (règle du commit de statut, `verify-and-merge-pr.md`).

## `--context`

`--context <fichier>` ajoute à la consigne des précisions de l'auteur : par exemple, les corrections apportées depuis une revue bloquante. Le fichier ne doit contenir aucun motif privé : sinon, rien n'est envoyé.

Les consignes elles-mêmes sont versionnées dans le dépôt commun (`review/prompts/`), la couche projet dans le projet (`review.project-layer`).

## Ce que le script vérifie

Dans l'ordre. Tout refus avant la relecture n'envoie rien au relecteur ; tout refus après la relecture ne publie rien.

1. La trace du shell est coupée, puis `jq`, `curl`, `agy` et `timeout` sont présents.
2. Exactement un usage est demandé : `--story <n.m>`, un numéro de PR ou `--range`.
3. `workflow.config` est lu et validé en entier — table `review.reviewers` comprise : une entrée dont le relecteur est du même fournisseur que l'auteur, ou une ancienne clé `review.reviewer-for-*`, l'arrête en `2` ; le fournisseur d'`AUTHOR_LLM` a une entrée dans la table, sinon `2`, sans relecteur par défaut ; une valeur que l'outillage ne sait pas encore servir (`review.report = file`, `sprint.convention = keyed`) l'arrête en `2`, en nommant la story qui l'apportera ; la couche projet existe et n'est pas vide.
4. Le dépôt distant `origin` est celui de `forge.repo`.
5. Si le projet a un garde-fou, son fichier de motifs existe et contient au moins un motif ; le fichier de contexte, s'il est donné, ne contient aucun motif privé.
6. Revue du code : le fichier d'environnement est lu par `gitea/gitea.sh`, sans afficher de valeur, et le jeton appartient à `GITEA_USER` ; la PR est ouverte ; sa base, sa branche et son SHA de tête sont lus par l'API, puis récupérés depuis la forge ; la branche n'a pas bougé entre-temps. Revue de spec : la tête de la base est lue sur la forge, et la story figure dans le suivi de sprint.
7. La copie isolée est un export du SHA relu (`git archive`), créé hors du dépôt : elle ne contient que les fichiers suivis, donc aucun fichier ignoré, et aucun `.git`, dont un worktree aurait eu besoin et qui donnerait au relecteur le chemin du dépôt de travail. Le script vérifie l'absence de `.git` et de chaque chemin de `review.private-paths` (dans le projet source : `.env`, `docs/private`, `.pr-body.md`). `git archive` n'exporte pas le contenu d'un sous-module : chaque sous-module du commit relu (ce dépôt commun compris) est exporté à part, au commit que le commit relu épingle, depuis le sous-module initialisé du poste ; un sous-module non initialisé, qui n'a pas ce commit, ou dont l'export ne contient aucun fichier, arrête la revue en `2` (`git submodule update --init`) : sans son code, la copie ne peut pas être construite. ⚠️ Un dossier de sous-module vide (clone sans `submodule update`, `submodule deinit`) n'a pas de `.git` : `git -C` y interroge le dépôt **parent**, qui peut avoir le commit épinglé et n'exporterait alors qu'un sous-arbre vide, en code `0`. Le sous-module doit donc être sa propre racine : `git rev-parse --show-prefix` y rend une ligne vide, et `<chemin>/` quand c'est le parent qui répond (dossier sans `.git`, ou `.git` qui n'est pas un dépôt). Le diff d'une PR est écrit avec `--submodule=diff` : la montée d'un sous-module s'y lit comme le diff de son code. Sans le commit que la base épingle, git n'écrirait que `(commits not present)`, en code `0` : ce cas arrête aussi la revue en `2`. Un sous-module supprimé par la PR n'est pas concerné : git écrit `(submodule deleted)`, sans contenu, qu'il ait ou non l'ancien commit.
8. Si le projet a un garde-fou, `<guard.command> history` passe sur ce qui est relu, avec la liste des motifs.
9. Un jeton de lecture aléatoire est écrit en tête du fichier relu (`REVIEW-DIFF.patch`, `REVIEW-SPEC.md` ou `REVIEW-RANGE.md`).
10. Une empreinte de chaque entrée de la copie est prise : `sha256sum` de chaque fichier, cible de chaque lien, liste des dossiers. Puis `agy --mode plan`, sans `--dangerously-skip-permissions`, reçoit la consigne complétée de la couche projet et du chemin de la copie, la copie passée par `--add-dir`, et au plus `review.timeout` secondes.
11. L'empreinte est reprise après la revue et comparée : toute entrée ajoutée, modifiée ou supprimée par le relecteur est signalée, fichiers cachés compris, parce que `--mode plan` n'est pas en lecture seule.
12. Le rapport cite le jeton de lecture : sinon, ce n'est pas une revue. La réponse d'`agy` peut contenir la réflexion du relecteur et ses brouillons, qui citent déjà le jeton : le rapport retenu commence à la **dernière** ligne qui n'est que le jeton (constat de la story 0.8).
13. Revue du code : la dernière ligne non vide est `VERDICT: NON BLOQUANT — …` ou `VERDICT: BLOQUANT — …`.
14. Le rapport ne contient aucun motif privé.
15. Revue du code : le commentaire est publié (réponse HTTP 201).
16. Le rapport est ajouté à la fin de sa section du fichier de story, sans modifier ni supprimer de ligne existante ; une mise à jour qui supprimerait une ligne est refusée.
17. À la sortie, en succès, en échec ou sur interruption, la copie isolée et les fichiers temporaires sont supprimés.

## Isolement et sécurité

- Le relecteur lit son répertoire courant : il travaille donc dans la copie isolée, jamais dans le dépôt de travail, où le fichier d'environnement et les chemins privés existent.
- La copie n'a pas de `.git` : le fichier `.git` d'un worktree contient le chemin absolu du dépôt de travail (`gitdir: …`), et le relecteur exécute des commandes shell (constat S11 de la rétrospective de l'epic 0 du projet source). Sans ce fichier, rien dans la copie ne désigne le dépôt de travail.
- Le relecteur est lancé **sans `--dangerously-skip-permissions`** : sans interface, `agy` ne peut pas lui demander la permission d'exécuter une commande, donc toute commande shell lui est refusée, et il ne lit que par ses outils de fichiers. Les consignes le lui disent. Essai de la story 0.8 du projet source, avec un faux `.env` à valeur témoin : avec ce drapeau, l'outil de lecture était bien refusé sur `.env`, mais `grep` renvoyait la valeur ; `--sandbox` ne l'empêchait pas non plus ; sans le drapeau, la commande est refusée.
- Si le relecteur tente malgré tout une commande shell, `agy` s'arrête sans réponse : le script le signale, rien n'est publié, et il suffit de relancer.
- Les refus de lecture de `.env` configurés pour les agents (`.claude/settings.json`, réglage d'Antigravity sur le poste, `.antigravityignore`) sont une défense en profondeur : ils ne remplacent ni la copie isolée ni l'absence de commande shell.
- Le diff part vers un service externe : c'est acceptable pour un dépôt dont le contenu versionné est public, ou dont le responsable l'a accepté ; c'est au projet de le décider, et à son garde-fou d'arrêter ce qui ne doit pas partir.
- Le jeton Gitea n'est jamais transmis au relecteur ; il n'est jamais affiché, et la trace du shell reste coupée (`gitea-token.md`).

## Codes de sortie

`0` revue publiée (ou rapport écrit, ou affiché) ; `1` **écart constaté** sur ce qu'on s'apprêtait à envoyer ou publier, refusé à raison — motif privé dans le fichier de contexte ou dans le rapport, chemin privé (ou `.git`) dans la copie isolée, refus du garde-fou ; `2` **la revue n'a pas pu avoir lieu** — usage, prérequis du poste (`agy`, `timeout`, `jq`, `curl`), configuration, fichier d'environnement et ses variables, lecture de la forge ou de git, plage, suivi de sprint, construction de la copie isolée, relecteur sans réponse ou qui tente une commande shell, rapport sans jeton ou sans verdict lisible, publication refusée. Un verdict `block` n'est pas un code de sortie : la revue a eu lieu, elle sort en `0`.

Une fois la PR lue, un `2` est aussi publié en **alerte sur la PR** (`alert_pr`, `shell-scripts.md`, § *Codes de sortie*), que voit quiconque l'ouvre ; si la forge le refuse, le terminal le dit et reste le seul canal. L'alerte n'est pas un rapport : elle ne commence pas par `llm-review sha=`, et `verify-and-merge-pr` ne la lit pas.

## En cas d'échec

- **Refus avant la relecture** : rien n'est envoyé. Corriger la cause indiquée, puis relancer.
- **Relecteur sans réponse, ou code 124** (délai dépassé) : rien n'est publié. Relancer.
- **« Le relecteur a tenté une commande shell »** : la commande lui a été refusée et l'exécution s'est arrêtée sans réponse. Rien n'est publié. Relancer ; si le cas se répète, revoir la consigne.
- **Rapport sans jeton de lecture** : le relecteur n'a pas lu le contenu, ou a répondu à côté. Rien n'est publié. Relancer.
- **Dernière ligne sans verdict lisible** : rien n'est publié. Relancer.
- **Fichiers créés, modifiés ou supprimés par le relecteur** : sans conséquence pour le dépôt, puisque la copie est supprimée ; le signalement reste dans le rapport publié.
- **Commentaire refusé par la forge** : rien n'est publié ; le fichier de story n'est pas modifié. Relancer.
- **La branche de la PR a bougé pendant la préparation** : relancer, pour relire le nouveau SHA de tête.
