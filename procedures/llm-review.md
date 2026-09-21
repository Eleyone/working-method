# Procédure — Revue par un LLM d'un autre fournisseur

Aucune spec ni aucun merge ne repose sur la seule relecture du modèle qui a écrit le code (AD-24). `scripts/llm-review.sh` fait relire, par un modèle d'un autre fournisseur, la spec d'une story avant son implémentation, puis le diff de sa PR avant la fusion.

## Prérequis

- `agy` (Antigravity CLI) installé et authentifié : `agy models` répond. Opération manuelle d'Arnaud.
- `jq`, `curl` et `timeout` installés. Sans `jq`, le script s'arrête et indique `sudo apt install jq`.
- Pour la revue du code seulement : `.env` à la racine du dépôt, avec `GITEA_URL`, `GITEA_USER` et `GITEA_TOKEN` (procédure `gitea-token.md`). La revue de spec n'appelle pas l'API et ne lit pas `.env`.
- Le fichier de motifs (`docs/private/forbidden-patterns.txt`, ou celui que désigne `PRIVATE_PATTERNS_FILE`), avec au moins un motif : rien n'est envoyé au relecteur sans audit (`check-private.md`).

## Relecteurs

Le relecteur vient toujours d'un autre fournisseur que l'auteur. Les modèles sont des constantes du script : aucune option ne permet d'en changer.

| Auteur (`AUTHOR_LLM`) | Relecteur | Identifiant dans `agy models` (relevé le 14/09/2026, `agy` 1.2.2) |
|---|---|---|
| `claude` (défaut) | Gemini 3.1 Pro (High) | `gemini-3.1-pro-high` |
| `gemini` | Claude Opus 4.6 (Thinking) | `claude-opus-4-6-thinking` |

Toute autre valeur d'`AUTHOR_LLM` est refusée.

Le relecteur applique le skill de revue BMAD `bmad-review`, qu'il lit comme un fichier dans la copie isolée. L'auteur ne relit jamais à sa place. `bmad-code-review` n'est pas utilisé : il s'arrête pour attendre des réponses.

## Revue de spec, au début de chaque story

1. Créer la branche de la story, puis lancer :

   ```bash
   scripts/llm-review.sh --story <n.m>
   scripts/llm-review.sh --story <n.m> --context <fichier>
   ```

2. Le relecteur lit le texte de la story tel qu'il est dans `epics.md` sur `dev`, avec les angles **adverse**, **structure** et **prose**. Il termine par une section « À trancher avant d'implémenter ».
3. Le script affiche le rapport et l'ajoute à la section « Revue de spec » du fichier de story (`_bmad-output/implementation-artifacts/<clé>.md`), qu'il crée s'il n'existe pas. Rien n'est publié sur la forge.
4. L'auteur trie chaque constat en ajoutant, sous le rapport, sa décision : corrigé dans la story, question tranchée par Arnaud, ou écarté avec sa raison. Puis il reformule la story et pose ses questions à Arnaud.

## Revue du code, sur chaque PR

1. Après l'ouverture de la PR et le commit de statut `review`, depuis la branche de la PR, lancer :

   ```bash
   scripts/llm-review.sh <numéro de PR>
   AUTHOR_LLM=gemini scripts/llm-review.sh <numéro de PR>
   ```

2. Le relecteur lit le diff de la branche entière par rapport à sa base, au SHA de tête lu sur la forge, avec les angles **edge-case-hunter** et **verification-gap**, plus la **couche propre au projet** : critères d'acceptation, données privées et secrets, concordance entre skill, procédure et script, cohérence avec `AGENTS.md` et l'architecture, erreurs silencieuses dans les scripts. Une PR qui ne touche que des fichiers Markdown prend les angles **structure** et **prose** à la place des deux premiers.
3. Chaque constat est classé : **bloquant** s'il casse un critère d'acceptation, fait fuiter une donnée privée ou un secret, ou laisse passer une erreur en silence ; **non bloquant** sinon.
4. Le script publie le rapport en commentaire de la PR, précédé de la ligne lue par `verify-and-merge-pr` :

   ```
   llm-review sha=<SHA de tête> base=<base> model=<modèle> verdict=<pass|block>
   ```

   Un verdict `block` se publie comme un `pass` : c'est un résultat, pas une erreur.
5. Le script ajoute aussi le rapport à la fin de la section « Revue du code » du fichier de story, si la branche courante est celle de la PR. L'auteur ajoute sous le rapport, sans le modifier, sa décision pour chaque constat : dans le commit de statut `done` après un `pass`, qui n'admet que des lignes ajoutées au fichier de story et à `deferred-work.md`, ou avec ses corrections après un `block`.

La revue dure plusieurs minutes, jusqu'à 15 : un agent la lance en arrière-plan et attend sa fin.

## Revue d'une plage, pour une rétrospective

```bash
scripts/llm-review.sh --range "<premier>^..<dernier>" --out <fichier>
```

Relit le **diff complet d'une plage de commits** — un epic entier — pour trouver ce qu'aucune revue de story ne pouvait voir : une règle appliquée différemment d'une story à l'autre, du code dupliqué entre deux stories, une décision contredite par une story suivante, une couverture de test absente à leur frontière, un commentaire devenu faux, du code mort. Angles : `adversarial`, `edge-case-hunter`, `verification-gap`.

- **Rien n'est publié** : pas de commentaire de PR, pas de fichier de story. Le rapport va dans le fichier désigné par `--out`, ou sur la sortie standard. C'est la rétrospective qui le cite, constat par constat, après les avoir rejoués.
- **La plage est écrite telle qu'on la veut** : `A..B` exclut `A`, `A^..B` l'inclut. Pour un epic, c'est le commit qui précède la première story jusqu'au dernier.
- **Le diff écarte `_bmad-output/`** : le relecteur a les artefacts de cadrage dans la copie, au commit de fin, et leur volume noierait le code.
- **La copie isolée est celle du commit de fin**, comme pour les autres modes, avec le même garde-fou lancé sur la plage avant l'envoi et le même jeton de lecture.

Ce mode remplace le script jetable écrit deux fois de suite pour les rétrospectives des epics 2 et 3. À sa première exécution, il a trouvé quatre défauts réels dans du code déjà relu PR par PR — dont une enveloppe qui promettait d'arrêter le script et ne le pouvait pas en tête de pipeline.

## Rapports dans le fichier de story

Le script ajoute chaque rapport au fichier de story de l'arbre de travail, sans le commiter. Un rapport n'est jamais modifié ni supprimé : l'auteur n'ajoute que ses décisions, sous lui.

- **Après la revue de spec** : le tri de l'auteur s'ajoute sous le rapport, et le tout part dans le premier commit de la story (`in-progress`), avec la story réécrite.
- **Après un verdict `block`** : les décisions de l'auteur s'ajoutent sous le rapport, et rapport et décisions partent avec les corrections ; la nouvelle tête appelle une nouvelle revue, dont le rapport s'ajoutera après.
- **Après un verdict `pass`** : les décisions s'ajoutent sous le rapport, et le tout part dans le commit de statut `done`, qui n'admet que des lignes ajoutées au fichier de story (règle du commit de statut, `verify-and-merge-pr.md`).

## `--context`

`--context <fichier>` ajoute à la consigne des précisions de l'auteur : par exemple, les corrections apportées depuis une revue bloquante. Le fichier ne doit contenir aucun motif privé : sinon, rien n'est envoyé.

Les consignes elles-mêmes sont versionnées : `scripts/llm-review-prompt.md` (revue du code) et `scripts/llm-review-spec-prompt.md` (revue de spec).

## Ce que le script vérifie

Dans l'ordre. Tout refus avant la relecture n'envoie rien au relecteur ; tout refus après la relecture ne publie rien.

1. La trace du shell est coupée, puis `jq`, `curl`, `agy` et `timeout` sont présents.
2. Exactement un usage est demandé : `--story <n.m>` ou un numéro de PR ; `AUTHOR_LLM` vaut `claude` ou `gemini`.
3. Le dépôt distant `origin` est `Eleyone/eleyone.fr`.
4. Le fichier de motifs existe et contient au moins un motif ; le fichier de contexte, s'il est donné, ne contient aucun motif privé.
5. Revue du code : `.env` est lu par `scripts/lib/gitea.sh`, sans afficher de valeur, et le jeton appartient à `GITEA_USER` ; la PR est ouverte ; sa base, sa branche et son SHA de tête sont lus par l'API, puis récupérés depuis la forge ; la branche n'a pas bougé entre-temps. Revue de spec : la tête de `dev` est lue sur la forge, et la story figure dans le suivi de sprint.
6. La copie isolée est un export du SHA relu (`git archive`), créé hors du dépôt : elle ne contient que les fichiers suivis, donc ni `.env`, ni `docs/private/`, ni `.pr-body.md`, et aucun `.git`, dont un worktree aurait eu besoin et qui donnerait au relecteur le chemin du dépôt de travail. Le script vérifie l'absence de ces quatre entrées.
7. `scripts/check-private.sh history` passe sur ce qui est relu, avec la liste des motifs.
8. Un jeton de lecture aléatoire est écrit en tête du fichier relu (`REVIEW-DIFF.patch` ou `REVIEW-SPEC.md`).
9. Une empreinte de chaque entrée de la copie est prise : `sha256sum` de chaque fichier, cible de chaque lien, liste des dossiers. Puis `agy --mode plan`, sans `--dangerously-skip-permissions`, reçoit la consigne complétée du chemin de la copie, la copie passée par `--add-dir`, et au plus 15 minutes.
10. L'empreinte est reprise après la revue et comparée : toute entrée ajoutée, modifiée ou supprimée par le relecteur est signalée, fichiers cachés compris, parce que `--mode plan` n'est pas en lecture seule.
11. Le rapport cite le jeton de lecture : sinon, ce n'est pas une revue. La réponse d'`agy` peut contenir la réflexion du relecteur et ses brouillons, qui citent déjà le jeton : le rapport retenu commence à la **dernière** ligne qui n'est que le jeton (constat de la story 0.8).
12. Revue du code : la dernière ligne non vide est `VERDICT: NON BLOQUANT — …` ou `VERDICT: BLOQUANT — …`.
13. Le rapport ne contient aucun motif privé.
14. Revue du code : le commentaire est publié (réponse HTTP 201).
15. Le rapport est ajouté à la fin de sa section du fichier de story, sans modifier ni supprimer de ligne existante ; une mise à jour qui supprimerait une ligne est refusée.
16. À la sortie, en succès, en échec ou sur interruption, la copie isolée et les fichiers temporaires sont supprimés.

## Isolement et sécurité

- Le relecteur lit son répertoire courant : il travaille donc dans la copie isolée, jamais dans le dépôt de travail, où `docs/private/` et `.env` existent.
- La copie n'a pas de `.git` : le fichier `.git` d'un worktree contient le chemin absolu du dépôt de travail (`gitdir: …`), et le relecteur exécute des commandes shell (constat S11 de la rétrospective de l'epic 0). Sans ce fichier, rien dans la copie ne désigne le dépôt de travail.
- Le relecteur est lancé **sans `--dangerously-skip-permissions`** : sans interface, `agy` ne peut pas lui demander la permission d'exécuter une commande, donc toute commande shell lui est refusée, et il ne lit que par ses outils de fichiers. Les consignes le lui disent. Essai de la story 0.8, avec un faux `.env` à valeur témoin : avec ce drapeau, l'outil de lecture était bien refusé sur `.env`, mais `grep` renvoyait la valeur ; `--sandbox` ne l'empêchait pas non plus ; sans le drapeau, la commande est refusée.
- Si le relecteur tente malgré tout une commande shell, `agy` s'arrête sans réponse : le script le signale, rien n'est publié, et il suffit de relancer.
- Les refus de lecture de `.env` configurés pour les agents (`.claude/settings.json`, réglage d'Antigravity sur le poste, `.antigravityignore`) sont une défense en profondeur : ils ne remplacent ni la copie isolée ni l'absence de commande shell.
- Le diff part vers un service externe : c'est acceptable parce que tout le contenu versionné est déjà public (AD-24).
- Le jeton Gitea n'est jamais transmis au relecteur ; il n'est jamais affiché, et la trace du shell reste coupée (`gitea-token.md`).

## En cas d'échec

- **Refus avant la relecture** : rien n'est envoyé. Corriger la cause indiquée, puis relancer.
- **Relecteur sans réponse, ou code 124** (délai dépassé) : rien n'est publié. Relancer.
- **« Le relecteur a tenté une commande shell »** : la commande lui a été refusée et l'exécution s'est arrêtée sans réponse. Rien n'est publié. Relancer ; si le cas se répète, revoir la consigne.
- **Rapport sans jeton de lecture** : le relecteur n'a pas lu le contenu, ou a répondu à côté. Rien n'est publié. Relancer.
- **Dernière ligne sans verdict lisible** : rien n'est publié. Relancer.
- **Fichiers créés, modifiés ou supprimés par le relecteur** : sans conséquence pour le dépôt, puisque la copie est supprimée ; le signalement reste dans le rapport publié.
- **Commentaire refusé par la forge** : rien n'est publié ; le fichier de story n'est pas modifié. Relancer.
- **La branche de la PR a bougé pendant la préparation** : relancer, pour relire le nouveau SHA de tête.
