# Procédure — BMAD dans le dépôt commun

Le dépôt commun porte **la** version de BMAD ; chaque projet utilise celle-là, ce qui garantit une
méthode identique partout. ⛔ **L'installeur BMAD ne tourne qu'ici**, jamais dans un projet : lancé
dans un projet, il écrirait à travers les liens, donc dans le sous-module.

## Les couches

| Couche | Contenu | Où | Écrit par |
|---|---|---|---|
| Méthode | skills BMAD, catalogue d'aide de chaque module, scripts de `_bmad/scripts` | `bmad/method/` du dépôt commun, relié dans le projet | `bmad/update.sh` |
| Configuration du projet | `_bmad/config.toml` (versionné), `_bmad/_config/bmad-help.csv` (versionné) | projet | `bin/install`, depuis `workflow.config` |
| Configuration par module | `_bmad/<module>/config.yaml` (**non versionné**) | projet | `bin/install`, depuis `workflow.config` **et** `_bmad/config.user.toml` |
| Couche utilisatrice | `_bmad/config.user.toml` (`user_name`, `communication_language`, `user_skill_level`) | projet | l'utilisatrice — jamais `bin/install` |
| Personnalisations | `_bmad/custom/` | projet | l'équipe — jamais l'installeur ni `bin/install` |
| Artefacts | `_bmad-output/` (ou `bmad.output-folder`) | projet | les skills |

⚠️ **En BMAD 6.12, `_bmad/<module>/` mêle la méthode et la configuration du projet** : il contient
`module-help.csv` (méthode) et `config.yaml` (projet), que les skills lisent à cet endroit précis.
Ce dossier est donc un **vrai dossier** du projet, qui contient un **lien par fichier de méthode** et
le `config.yaml` généré (décision du 04/10/2026). La méthode reste dans le sous-module, la
configuration dans le projet.

⚠️ **Les `config.yaml` embarquent des valeurs de l'utilisatrice** (son nom, sa langue) : ils
dépendent d'un fichier propre à chaque poste, et ne se versionnent pas. `config.toml`, lui, n'en a
aucune : il se versionne. Les valeurs de l'utilisatrice y sont superposées par BMAD lui-même, qui lit
`config.user.toml` par-dessus.

## Ce que porte le dépôt commun

- `bmad/bmad.config` : la version de `bmad-method`, l'**union** des modules — six :
  `core bmm bmb cis bmad-loop tea` —, les shims v6 (`bmad-create-story`, `bmad-dev-story`,
  `bmad-sprint-status`…), et **une version exacte par module externe**. Le canal « stable » de
  l'installeur résout la plus haute étiquette **au moment de l'installation** : sans épinglage, deux
  installations de la même version de BMAD peuvent différer.
- `bmad/method/` : ce que l'installeur produit, réduit à la méthode — skills, catalogues,
  `scripts/`, **modèles** de configuration (`templates/`), licences, provenance (`SOURCE`).
- ⛔ Ni `wds` ni `render` : `render` n'est pas un module (c'est le cache `_bmad/render/`, écrit à
  l'exécution) ; `wds` est déprécié en amont depuis 6.12.0 et exclu (décision du 04/10/2026). Un
  projet qui les active fait sortir `bin/install` en `1`.

Les fichiers `.md` des skills sont marqués `-diff` (`.gitattributes`) : un diff, celui de la revue LLM
compris, n'en montre que la liste. ⛔ Les scripts des skills (`.py`, `.js`, `.cjs`, `.sh`…) restent
visibles : du code exécutable n'est jamais caché à la revue. Le contenu des `.md` est prouvé
autrement — la CI rejoue l'installeur et exige le même arbre. Pour lire le vrai diff : `git diff --text`. Les contrôles « aucun secret » et « aucun nom de
projet » les lisent quand même.

## Monter BMAD (ou un module)

1. Modifier `bmad/bmad.config` : `version`, un épinglage, la liste des modules.
2. `bash bmad/update.sh` — demande node 20.12 ou plus, `npx`, git, et le réseau (npm pour
   `bmad-method`, GitHub pour les modules externes). Il rejoue l'installeur dans un dossier jetable,
   avec un `HOME` et un cache npm vides, et des valeurs **sentinelles** ; il vérifie que les versions
   installées sont celles déclarées, puis réécrit `bmad/method/`. Code `2`, et `bmad/method/` intact,
   si quoi que ce soit échoue.
3. Relire `git status -- bmad/method` : le diff des modèles (`templates/`) et des catalogues se lit ;
   celui des skills se lit avec `--text`.
4. PR du dépôt commun, puis une PR de montée par projet, avec ses propres gates. Chaque projet aligne
   `bmad.version` de son `workflow.config` dans cette PR : sans cela, `bin/install` rend `1` en nommant
   les deux versions.

⚠️ Les sentinelles deviennent dans les modèles des champs `@bmad.…@` (valeurs de `workflow.config`)
et `@user:<section>.<clé>@` (valeurs de `config.user.toml`). Une sentinelle restée hors des modèles
est une valeur du projet qui a fui dans la méthode : `update.sh` sort en `2`.

## Le test de réinstallation (décision 9)

`ci/bmad-reinstall.sh`, dans la CI du dépôt commun : sur un projet fixture
(`tests/fixtures/bmad-projet`), installer, **réinstaller BMAD dans le dépôt commun** par
`bmad/update.sh`, relancer `bin/install`, puis prouver :

- par empreinte, qu'**aucun** fichier de `workflow.config`, `_bmad/config.user.toml`,
  `_bmad/custom/` et `_bmad-output/` n'a changé ;
- que le sous-module est **propre** après chaque étape — `bin/install` n'écrit pas à travers ses liens,
  et l'installeur reproduit exactement `bmad/method/` ;
- que `config.toml`, chaque `config.yaml` et le catalogue d'aide sont **octet pour octet** ceux
  qu'une installation neuve génère depuis le même `workflow.config`.

⛔ Un test qui ne peut pas échouer ne prouve rien : `tests/test-bmad-reinstall.sh` y injecte des
régénérations fautives (une couche projet modifiée, un fichier ajouté, une méthode régénérée
autrement, le sous-module sali), et chacune doit le faire échouer. Une réinstallation impossible
— réseau compris — sort en `2`, jamais en vert.

Ce que le test **ne couvre pas** : une skill lancée par un agent qui écrit à travers les liens.
`bmad-loop init` (lancé par la skill `bmad-loop-setup`) dépose des skills dans les dossiers d'outil
du projet, donc **dans le sous-module**. Le contrôle « sous-module propre » le **détecte après coup**
(`git -C .working-method status`), il ne l'empêche pas.

## Passer un projet sur le BMAD du sous-module

Dans la PR d'adoption (ou de montée) du projet :

1. `workflow.config` au **schéma 3** : `bmad.version` (celle du sous-module), `bmad.modules` (le
   sous-ensemble utile, `core` compris), `bmad.project-name`, `bmad.document-output-language`,
   `bmad.output-folder` (`workflow-config.md`).
2. **Supprimer les copies locales** : chaque skill `bmad-*` des dossiers d'outil, `_bmad/scripts/`,
   `_bmad/<module>/module-help.csv` et ce qui l'accompagne, `_bmad/_config/` (le manifeste de
   l'installeur n'a plus d'objet : il ne tourne plus dans le projet). Une copie restante est un
   **conflit** (`bin/install` rend `1`, rien n'est écrit).
3. `_bmad/config.user.toml` : la couche utilisatrice, en `clé = "valeur"` — sans lui, `bin/install`
   rend `2` en listant les clés attendues. Il n'est pas versionné ; s'il l'était, c'est un choix du
   projet, à écrire.
4. `.gitignore` : `/_bmad/*/config.yaml`, et `git rm --cached` des `config.yaml` suivis (un
   `config.yaml` suivi est un conflit). `/_bmad/render/` (cache) reste ignoré.
5. `.working-method/bin/install` ; commiter les liens, `_bmad/config.toml` et
   `_bmad/_config/bmad-help.csv`.
6. Prouver que les skills fonctionnent : en charger une à travers les liens, et créer une story
   avec `bmad-create-story`.

⚠️ **Ce qui disparaît** avec l'installeur dans le projet : les dossiers d'artefacts qu'il créait à la
racine (`docs/`, `_bmad-output/`, les dossiers de `tea`) ne sont plus créés à l'installation. Les
skills qui en ont besoin les créent à l'usage.

## Codes de `bin/install` (partie BMAD)

| Code | Quand |
|---|---|
| `0` | installé, ou déjà en place ; une édition à la main de la configuration générée est **écrasée et signalée** (`ATTENTION`) |
| `1` | `bmad.version` différente de la version du sous-module (les deux sont nommées) ; module activé hors de l'union (`wds`, `render`…) ; `core` absent ; conflit (copie locale, lien étranger, `config.yaml` suivi par git) |
| `2` | `workflow.config` refusé (au schéma 1 ou 2 notamment) ; `bmad/bmad.config` ou `bmad/method/` du sous-module illisibles ou incomplets ; `_bmad/config.user.toml` absent, hors du format lu, ou sans une clé attendue |

Relancé, `bin/install` ne change rien — ni un lien, ni un fichier, ni une date. Un module désactivé
perd ses liens et son `config.yaml` généré à l'installation suivante, et le script le dit.
