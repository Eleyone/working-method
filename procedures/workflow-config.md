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

## Les champs — schéma 3

Le lecteur ne lit que le schéma **3** (« Changer de schéma », ci-dessous). Par rapport au schéma 2, il
remplace les deux relecteurs nommés, `review.reviewer-for-claude` et `review.reviewer-for-gemini`, par
la **table** `review.reviewers`, ouverte à tout fournisseur. Le schéma 2 avait ajouté au 1 les trois
champs `bmad.project-name`, `bmad.document-output-language` et `bmad.output-folder`, dont `bin/install`
génère la configuration BMAD du projet.

| Champ | Type | Désactivable | Lu par |
|---|---|---|---|
| `workflow.schema` | `3` | non | tous |
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
| `review.reviewers` *(schéma 3)* | table : entrées `auteur=modèle` séparées par une espace (ci-dessous) | non | `llm-review` : relecteur du fournisseur de l'auteur |
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
| `bmad.project-name` | libellé | non | `bin/install` : `project_name` de la configuration BMAD générée |
| `bmad.document-output-language` | libellé | non | `bin/install` : `document_output_language` |
| `bmad.output-folder` | chemin | non | `bin/install` : `output_folder`, et les dossiers d'artefacts qui en dérivent |
| `agents.skill-dirs` | chemins séparés par une espace | non | `bin/install` |
| `module.<nom>.<clé>` *(optionnel)* | valeur du modèle du module (ci-dessous) | — | `bin/install` : surcharge de la configuration générée du module |

Un **libellé** est recopié tel quel, sans citation, dans un fichier TOML et dans une valeur YAML
générés : ni espace en tête ou en fin, ni caractère de contrôle, ni aucun de `"`, `\`, `'`,
`` ` ``, `#`, `:`, `{`, `}`, `[`, `]`, `,`, `&`, `*`, `!`, `|`, `>`, `%`, `@`. Un **chemin** est relatif à la racine du projet, sans `/` initial, sans `.` ni `..`, sans blanc ni
`/` final. Un **booléen** s'écrit `true` ou `false`, jamais `yes`, `on` ou `1`, que git accepterait.

### La table des relecteurs — `review.reviewers`

```ini
[review]
	reviewers = claude=gemini-3.1-pro-high gemini=claude-opus-4-6-thinking gpt=claude-opus-4-6-thinking
```

- Une entrée par **fournisseur d'auteur**, `auteur=modèle`. L'auteur est nommé par son fournisseur,
  en minuscules (`claude`, `gemini`, `gpt`…) : c'est la valeur d'`AUTHOR_LLM` (`llm-review.md`). Le
  modèle est un nom de `agy models`.
- Le **fournisseur d'un modèle** est le premier segment de son nom (`gemini-3.1-pro-high` → `gemini`,
  `gpt-oss-120b-medium` → `gpt`).
- ⛔ Une entrée dont le relecteur est **du même fournisseur** que l'auteur est refusée (code `2`) :
  c'est la règle de la revue croisée, que la configuration ne peut pas contourner. Un auteur écrit
  deux fois l'est aussi.
- Un fournisseur s'ajoute par **une entrée**, jamais par du code. Un auteur **sans entrée** fait sortir
  la revue en `2`, sans appeler aucun relecteur : il n'existe pas de relecteur par défaut.

### Surcharges des modules BMAD — `[module "<nom>"]` (optionnelles)

`bin/install` génère la configuration de chaque module activé depuis le **modèle** que porte le
sous-module (`bmad/method/templates/<nom>.config.yaml`). Les valeurs propres au module (chemins
d'artefacts de `tea`, son cadre de test…) y sont écrites telles que l'installeur BMAD les produit. Un
projet qui en veut d'autres les **surcharge** :

```ini
[module "tea"]
	test-artifacts = {project-root}/_bmad-output/test-artifacts
	test-framework = playwright
	tea-pact-mcp = none
```

- **Optionnelles** : sans surcharge, la valeur est celle du modèle — une valeur écrite et versionnée
  dans le dépôt commun, pas un défaut du lecteur. Un `workflow.config` sans section `[module …]`
  reste valide au **même schéma** : aucune migration pour les projets qui n'en ont pas besoin.
- La clé s'écrit avec des tirets (git config refuse « `_` ») : `test-framework` désigne
  `test_framework`. Elle s'applique au `config.yaml` du module **et** au bloc `[modules.<nom>]` de
  `_bmad/config.toml`.
- ⛔ Refusé en `2` : un module absent de `bmad.modules`, ou sans modèle dans le dépôt commun ; une clé
  absente du modèle (le message liste les clés admises) ; une clé dont la valeur dérive déjà d'un
  champ (`planning_artifacts` ← `bmad.output-folder`, `user_name` ← `config.user.toml`…) ; une
  surcharge écrite deux fois ; une valeur vide, avec un blanc en tête ou en fin, un caractère de
  contrôle, ou l'un de `"`, `\`, `` ` ``, `@`. Une clé dont le modèle vaut `true` ou `false`
  n'admet que `true` ou `false`.
- Rendu : un booléen reste nu, toute autre valeur est écrite entre guillemets doubles (chaîne en YAML
  comme en TOML).
- **Générique, pas propre à `tea`** : tout module activé dont le modèle porte une valeur littérale se
  surcharge ainsi (`bmm` : `project-knowledge` ; `cis` : `visual-tools` ; `bmb` : ses deux dossiers).
  `core` n'en a aucune — toutes ses valeurs dérivent d'un champ. Le même code sert tous les modules :
  le restreindre à `tea` aurait coûté une liste à tenir, pas une ligne de moins.

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

Un champ ajouté, retiré ou retypé change de schéma : `workflow.schema` augmente, et chaque projet monte
le sien dans sa PR de montée du sous-module. Un fichier d'un schéma que le lecteur ne connaît pas est
refusé, jamais lu « au mieux ».

En règle générale, le lecteur apprend l'ancien schéma et le nouveau : c'est ce qu'il a fait du 1 au 2.
⛔ **Le schéma 3 fait exception** : les schémas 1 et 2 portent `review.reviewer-for-claude` et
`review.reviewer-for-gemini`, que plus aucun outil ne lit. Les lire encore, ce serait accepter un
fichier dont les relecteurs déclarés sont ignorés en silence. Un fichier au schéma 1 ou 2 est donc
**refusé en `2`**, avec ce qu'il faut changer ; et l'une des deux anciennes clés, à quelque schéma que
ce soit, est refusée avec la forme qui la remplace :

| Schéma 2 | Schéma 3 |
|---|---|
| `schema = 2` | `schema = 3` |
| `reviewer-for-claude = gemini-3.1-pro-high`<br>`reviewer-for-gemini = claude-opus-4-6-thinking` | `reviewers = claude=gemini-3.1-pro-high gemini=claude-opus-4-6-thinking` (et toute autre entrée utile, `gpt=…` par exemple) |

Depuis le schéma 1, ajouter aussi les trois champs `bmad.*`. La PR de montée du sous-module qui
franchit le schéma 3 réécrit le fichier dans le même commit.
