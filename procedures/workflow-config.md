# Procédure — `workflow.config`, ce qui est propre à un projet

Le dépôt commun ne connaît aucun projet. Tout ce que son outillage lisait autrefois en dur — nom du
dépôt sur la forge, branches, chemins du suivi de sprint, exemption de revue, garde-fou, workflow de
CI — est déclaré par chaque projet dans **un seul fichier**, `workflow.config`, à sa racine, versionné.

Exemple commenté : `workflow.config.example`. Lecteur : `lib/config.sh`, testé par
`tests/test-config.sh`.

## Format

Le format de `git config`, lu par `git config -f workflow.config --no-includes --null --list`.

| Format écarté | Parce que |
|---|---|
| dotenv | son lecteur ignore en silence une ligne mal formée : l'inverse de la règle ci-dessous |
| TOML, YAML | aucun lecteur en bash, et aucun outil pour eux sur le runner ni sur le poste |
| JSON | `jq` est absent du runner ; il y est téléchargé, épinglé, pour les seuls tests |
| ⭐ `git config` | aucun lecteur à écrire : `git` est déjà un prérequis de tout l'outillage, la syntaxe est vérifiée par git, et aucune valeur n'est interprétée par le shell |

## ⛔ La règle : jamais de valeur par défaut

Le fichier est lu **en entier**, et validé **avant toute action** de l'outil qui le lit. Il est refusé,
avec le nom de chaque champ fautif et la raison, et l'outil sort en **code `2`**, quand :

- le fichier est absent ou illisible ;
- git refuse sa syntaxe (rien n'est lu, même ce qui précède l'erreur) ;
- `workflow.schema` n'est pas un schéma connu ;
- un champ du schéma est **absent** ;
- un champ ou une section sont **inconnus** — sous-section et `[include]` compris ;
- un champ est écrit **deux fois** ;
- une valeur est **vide**, ou une clé écrite sans `=` ;
- une valeur n'a pas le **type** attendu ;
- une règle entre champs est violée (ci-dessous).

⭐ **`none` est une valeur, pas une absence.** Sur un champ *désactivable*, il désactive la fonction,
et l'outil qui la porte **le dit** dans sa sortie (« désactivé (… = none) ») — il ne la rend jamais
verte en silence. Sur un champ non désactivable, `none` est une erreur de type.

## Les champs — schéma 2

Le lecteur lit les schémas **1 et 2** (« Changer de schéma », ci-dessous). Le schéma 2 ajoute les
trois champs `bmad.project-name`, `bmad.document-output-language` et `bmad.output-folder`, dont
`bin/install` génère la configuration BMAD du projet (story 1) : au schéma 1, ils sont **inconnus**
(code `2` s'ils sont écrits), et `bin/install` refuse en `2` en demandant le schéma 2. Les autres
outils lisent indifféremment les deux.

| Champ | Type | Désactivable | Lu par |
|---|---|---|---|
| `workflow.schema` | `1` \| `2` | non | tous |
| `forge.repo` | `propriétaire/nom` | non | `gitea/gitea.sh` : dépôt distant vérifié, appels à l'API |
| `forge.base` | branche (`git check-ref-format --branch`) | non | `create-pull-request`, `verify-and-merge-pr`, `llm-review` |
| `forge.release-branch` | branche, différente de la base | **oui** | refus des PR vers elle (`create-pull-request`, `verify-and-merge-pr`) |
| `forge.branch-prefixes` | mots séparés par une espace, sans `/` | non | `create-pull-request` : préfixes admis vers la base |
| `forge.env-file` | chemin | non | `gitea/gitea.sh` : `GITEA_URL`, `GITEA_USER`, `GITEA_TOKEN` |
| `sprint.convention` | `numbered` \| `keyed` | **oui** | `lib/sprint.sh`, `sprint-consistency`, `verify-and-merge-pr`, `llm-review` |
| `sprint.status-file` | chemin | avec `sprint.convention` | idem |
| `sprint.stories-dir` | chemin | avec `sprint.convention` | idem |
| `sprint.spec-source` | chemin | **oui** | `llm-review --story` |
| `review.exempt-paths` | expression régulière étendue, appliquée à **chaque** chemin modifié | **oui** | `verify-and-merge-pr`, verrou de revue |
| `review.report` | `pr-comment` \| `file` | non | `llm-review`, `verify-and-merge-pr` |
| `review.reviewer-for-claude` | nom de modèle de `agy models` | non | `llm-review` |
| `review.reviewer-for-gemini` | nom de modèle de `agy models` | non | `llm-review` |
| `review.timeout` | entier, en secondes | non | `llm-review` |
| `review.project-layer` | chemin d'un fragment de consigne | non | `llm-review` |
| `review.private-paths` | chemins séparés par une espace | non | `llm-review` : refusés dans la copie isolée |
| `review.range-exclude` | chemins séparés par une espace | **oui** | `llm-review --range` : écartés du diff |
| `guard.command` | chemin d'un exécutable, appelé `<commande> history <plage>` | **oui** | `create-pull-request`, `llm-review`, `verify-and-merge-pr` |
| `guard.patterns-file` | chemin, passé au garde-fou par `PRIVATE_PATTERNS_FILE` | **oui** | idem |
| `ci.workflow` | chemin du workflow qui fait foi | **oui** | `verify-and-merge-pr`, verrou de CI |
| `ci.status-context` | nom du workflow, tel que la forge préfixe ses contextes | avec `ci.workflow` | `verify-and-merge-pr`, verrou de CI |
| `ci.bootstrap` | `true` \| `false` | non | `verify-and-merge-pr` : règle d'amorçage |
| `checks.command` | commande, lancée à la racine | **oui** | `verify-and-merge-pr` : substitut d'amorçage |
| `checks.dir` | chemin | **oui** | `checks/run-checks.sh` |
| `tests.protected-outputs` | chemins séparés par une espace | **oui** | `tests/run.sh` |
| `bmad.version` | `X.Y.Z` | non | `bin/install` : doit être la version que porte le sous-module (`bmad/bmad.config`), sinon code `1` |
| `bmad.modules` | mots séparés par une espace | non | `bin/install` : modules activés, parmi l'union du sous-module (sinon `1`), `core` compris |
| `bmad.project-name` *(schéma 2)* | libellé | non | `bin/install` : `project_name` de la configuration BMAD générée |
| `bmad.document-output-language` *(schéma 2)* | libellé | non | `bin/install` : `document_output_language` |
| `bmad.output-folder` *(schéma 2)* | chemin | non | `bin/install` : `output_folder`, et les dossiers d'artefacts qui en dérivent |
| `agents.skill-dirs` | chemins séparés par une espace | non | `bin/install` |

Un **libellé** est recopié tel quel, sans citation, dans un fichier TOML et dans une valeur YAML
générés : ni espace en tête ou en fin, ni caractère de contrôle, ni aucun de `"`, `\`, `'`,
`` ` ``, `#`, `:`, `{`, `}`, `[`, `]`, `,`, `&`, `*`, `!`, `|`, `>`, `%`, `@`. Un **chemin** est relatif à la racine du projet, sans `/` initial, sans `.` ni `..`, sans blanc ni
`/` final. Un **booléen** s'écrit `true` ou `false`, jamais `yes`, `on` ou `1`, que git accepterait.

### Règles entre champs

- `sprint.convention = none` exige `none` sur `sprint.status-file`, `sprint.stories-dir` et
  `sprint.spec-source` ; une convention active exige les deux chemins.
- `guard.patterns-file = none` exige `guard.command = none` : un garde-fou sans motif ne garde rien.
- `ci.workflow` et `ci.status-context` valent `none` ensemble, ou portent une valeur ensemble.
- `forge.release-branch` diffère de `forge.base`.

### Valeurs posées pour la suite

Deux valeurs sont au schéma pour qu'il ne change pas sous les projets, mais l'outillage ne sait pas
encore les servir. Un outil qui les rencontre sort en `2` en nommant la story qui les apportera —
jamais un repli silencieux :

| Valeur | Story |
|---|---|
| `sprint.convention = keyed` (clés en kebab-case, bloc `aliases:`) | 5 |
| `review.report = file` (rapport versionné plutôt que commentaire de PR) | 8 |

## Pièges de la syntaxe

Constatés le 03/10/2026 avec git 2.53.0, chacun rejoué par un cas de `tests/test-config.sh` :

| Constat | Conséquence |
|---|---|
| Erreur de syntaxe : code `128`, **mais une sortie partielle est écrite** | le lecteur ne lit jamais la sortie si le code n'est pas `0` |
| Clé dupliquée : `--get` rend la **dernière**, code `0`, sans rien dire | toutes les valeurs sont lues et comptées |
| `[include] path = …` : avec `--no-includes`, non suivi, mais listé comme `include.path` | refusé comme section inconnue |
| `GIT_CONFIG_COUNT`, `GIT_CONFIG_PARAMETERS` : sans effet avec `-f` | rien à faire, mais sous test |
| Une clé sans `=` vaut « vrai » ; `cle =` vaut une chaîne vide | toutes deux refusées |
| Noms de section et de clé **insensibles à la casse**, `_` interdit dans un nom | noms en minuscules avec tirets ; `[FORGE] Repo` est lu `forge.repo`, et compte comme doublon d'un `[forge] repo` |
| `\.md$` hors guillemets : **erreur de syntaxe** ; `"\\.md$"` donne `\.md$` | écrire `[.]md$` |
| `a # commentaire` donne `a` ; `"a # b"` donne `a # b` | citer toute valeur qui contient `#`, `;` ou `\` |

## Racine du projet

Un outil prend pour racine le dépôt git du dossier courant. Si ce dépôt est le dépôt commun
lui-même, consommé en sous-module, la racine est le projet qui le contient : lancé par mégarde depuis
le sous-module, un outil agit sur le projet, jamais sur le dépôt commun. Le dépôt commun, cloné seul,
est sa propre racine et lit son propre `workflow.config`.

## Changer de schéma

Un champ ajouté, retiré ou retypé change de schéma : `workflow.schema` passe à `2`, le lecteur
apprend les deux, et chaque projet monte le sien dans sa PR de montée du sous-module. Un fichier d'un
schéma que le lecteur ne connaît pas est refusé, jamais lu « au mieux ».
