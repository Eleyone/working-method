# Procédure — Écrire et tester les scripts shell

Les scripts du poste de développement (`scripts/*.sh`, `scripts/lib/`) et ceux de la CI suivent les mêmes règles. Cette procédure les rassemble, avec les pièges déjà rencontrés et les tests qui les rejouent (story 0.9, constat P1 de la rétrospective de l'epic 0).

## Règles

- En tête : `#!/usr/bin/env bash` et `set -euo pipefail`. Un script qui lit un jeton coupe la trace (`set +x`) avant de charger `scripts/lib/gitea.sh` (`gitea-token.md`).
- Un script se lance depuis n'importe quel dossier du dépôt et se place à sa racine (`git rev-parse --show-toplevel`) avant de lire les fichiers suivis.
- Un message commence par le nom du script. Aucun message n'affiche une valeur de `.env`, l'adresse de la forge ou un contenu privé.
- Identifiants en anglais ; messages, commentaires et procédures en français.
- Aucun outil de plus sans décision : `bash`, `git`, `jq`, `curl` sur le poste, `grep` GNU et outils de base, disponibles aussi dans `CHECK_IMAGE`.
- La logique commune vit dans `scripts/lib/` : `gitea.sh` (environnement, API de la forge, fichier de motifs), `sprint.sh` (lecture du suivi de sprint, sans `jq`), `merge-gates.sh` (décisions des verrous de fusion).
- Une fonction de bibliothèque ne compte pas sur `set -e` et vérifie chaque étape : appelée derrière `||`, elle n'en profiterait pas. Elle répond par son code de retour, comme une commande, et n'écrit rien sur la sortie standard en cas d'erreur.
- Ce qui appelle la forge reste dans le script ; ce qui décide lit des fichiers. Une lecture paginée reçoit le nom de la fonction qui écrit une page : le script lui fait appeler la forge, les tests lui font lire des fixtures. Aucune variable d'environnement ne remplace un appel à la forge.

## Tests

```bash
scripts/tests/run.sh                                  # tous les cas, arrêt au premier échec
scripts/tests/run.sh scripts/tests/test-sprint.sh     # les cas d'un fichier
```

Code de sortie : `0` tous les cas réussis ; `1` un cas échoue (le script nomme le fichier, le cas et affiche sa sortie) ; `2` tests impossibles à lancer (outil absent, fichier de test illisible).

- **Quand** : avant toute PR qui touche `scripts/`, sur le poste ; dans `CHECK_IMAGE`, par `scripts/ci/checks-job.sh`, que le poste et les deux CI lancent de la même façon (`checks-job.md`). Tant que la CI n'existe pas, le résultat est noté dans la PR.
- **Conditions** : aucun réseau, ni `.env` ni `docs/private/` ; dépendances `bash`, `git`, `jq`, `grep` GNU et outils de base. Chaque cas tourne dans son propre processus bash, pour que `set -e` y reste actif. La suite ne touche ni `public/` ni `build/` du dépôt : `run.sh` relève leur état avant et après, et échoue sur tout écart.
- **Ajouter un cas** : une fonction `case_<nom>` dans un fichier `scripts/tests/test-*.sh`, qui charge `scripts/tests/lib.sh` et se termine par `run_case "$@"`. Outils : `run` (code dans `rc`, sortie dans `out`, erreur dans `err`), `assert_eq`, `assert_contains`, `new_repo` et `commit_all` pour un dépôt git de test, `$work` pour les fichiers temporaires, `$fixtures` pour les fixtures versionnées sous `scripts/tests/fixtures/`.
- **Chercher dans un fichier** : `tests_grep_into <variable> <arguments de grep>`. Il distingue « rien trouvé » (1) d'une erreur de lecture (2 et plus), et remplit une variable de l'appelant plutôt que d'écrire sur la sortie standard : appelée dans `$(…)`, une fonction ne peut pas arrêter le cas, son `exit` ne quittant que le sous-shell.
- **Un cas sans objet ici** : `skip_case "<raison>"` (code 3), ou `skip_if_root "<ce qui est rendu illisible>"`. Le cas n'échoue pas et ne se tait pas : le résumé de `run.sh` compte les ignorés et donne leur raison. Un cas ne doit jamais rendre un verdict différent selon l'endroit où la suite tourne — s'il le fait, il s'ignore en le disant.
- **Tout nouveau piège** reçoit un cas de test et une ligne dans le tableau ci-dessous.

## Pièges connus

| Piège | Ce qui se passe | Parade | Trouvé à |
|---|---|---|---|
| `commande < <(fonction)` | l'échec de la fonction est masqué : la boucle lit une liste vide | lire dans une variable d'abord : `liste=$(fonction) \|\| die …` | story 0.6 |
| `{ a; b; } \|\| die`, ou `fonction \|\| die` | `set -e` est suspendu pour tout le bloc ou toute la fonction : un échec au milieu passe en silence | commande par commande, chacune avec son arrêt ; une fonction vérifie chaque étape | story 0.7 |
| apostrophe dans `"${var:+texte}"` | l'apostrophe ouvre une chaîne : erreur de syntaxe, trouvée par `bash -n` | mettre le texte dans une variable | story 0.7 |
| regex construite depuis une variable (`grep -E "…$base…"`) | un caractère spécial casse la regex, et l'erreur est avalée par `\|\| true` | comparer à l'identique : champs `awk`, `grep -F` | story 0.7 |
| `git diff … \| grep … \|\| true` | l'échec de `git diff` est masqué avec le « rien trouvé » de `grep` | lire le diff dans une variable, avec son arrêt, puis filtrer | story 0.7 |
| `grep` : `1` rien trouvé, `2` erreur | `\|\| true` confond les deux ; `git grep` peut même rendre `1` avec une erreur sur la sortie d'erreur | garder le code et distinguer `1` de `2` (fonction `select_lines` de `merge-gates.sh`) ; une sortie d'erreur non vide vaut échec | stories 0.3, 0.8, 0.9 |
| `jq @tsv` puis `read -r` | l'antislash reste doublé | lire un texte libre seul, avec `jq -r` | story 0.8 (D5) |
| pagination de l'API de la forge | la liste des commentaires d'une issue ignore `limit` et `page` ; la timeline répond `null` au-delà de la dernière page | timeline, page `null` lue comme vide, plafond de pages ; essayer contre la forge tout comportement supposé | story 0.8 (D1) |
| `git ls-files`, `git ls-tree`, `git grep -- .` | relatifs au dossier courant : lancés depuis un sous-dossier, ils ne voient que lui | se placer à la racine du dépôt | story 0.8 (D3) |
| insertion par remplacement de texte dans un document | un titre court est contenu dans un titre plus long (`## Epic 2 …` est une sous-chaîne de `### Epic 2 …`) : l'insertion frappe deux endroits et duplique un bloc entier | ancrer sur une chaîne unique **et** encadrée (sauts de ligne compris), vérifier qu'elle n'apparaît qu'une fois avant d'écrire, puis recompter les titres après écriture | story 1.5 (S5 de la rétro de l'epic 1) |
| test qui lance un script destructeur (`build.sh` vide sa destination) | sans racine jetable, la suite efface le `public/` du dépôt en silence : le cas passe, la sortie de build disparaît | passer la racine d'essai (`BUILD_DESTINATION_ROOT="$work/sortie"`) à **chaque** appel, pas seulement dans l'utilitaire du fichier ; `run.sh` compare l'état de `public/` et `build/` avant et après la suite | rétrospective de l'epic 2 (F1) |
| `commande \| tail` derrière `&&` | le pipeline rend le code de `tail` : un contrôle en échec laisse passer la commande suivante, un commit par exemple | écrire la sortie dans un fichier, tester le code, puis afficher le fichier ; jamais de `\| tail` devant un `&&` | rétrospective de l'epic 2 (P3) |
| `git checkout -- <dossier>` pour défaire un essai | ne restaure que les fichiers suivis : un fichier créé par la story, pas encore commité, garde la modification d'essai (un `draft: false` est parti dans un build de production local) | copier les fichiers avant l'essai et les restaurer depuis la copie ; supprimer nommément les fichiers créés ; relire `git status` et `git diff` | story 2.5, rétrospective de l'epic 2 (P3) |
| `exit` dans un sous-shell (élément de pipeline, `< <(…)`, `$(…)` filtré) | l'arrêt ne quitte que le sous-shell : la fonction ou le script continue, et un `\|\| true` final transforme l'anomalie en succès | lire la sortie dans une variable **avant** de filtrer, propager le code (`brut=$(cmd) \|\| return $?`) ; aucune substitution de processus dans un script de contrôle | story 3.11, revues de la PR n° 47 |
| cas de test qui suppose son environnement | `case_…_hors_image` comptait sur l'absence d'`apk` : vrai sur le poste, faux dans `CHECK_IMAGE`, où la suite tourne **dans** le job et où le cas relançait le job entier ; de même, une variable que le cas veut absente (`HOST_UID`) lui est léguée par le conteneur | réduire le `PATH` du cas à ce qu'il lui faut, retirer nommément les variables (`env -u`) : un cas doit rendre le même verdict des deux côtés | story 3.12 |
| script essayé seulement sur le poste | BusyBox n'est pas GNU : le `find` de l'image ignore `-printf`, et `xmllint` y rend 11 là où le poste rend 10 pour « aucun nœud » | lancer `scripts/ci/checks-job.sh` avant de livrer un script que la CI exécute ; ajouter l'outil GNU à `CHECK_PACKAGES` plutôt que d'écrire deux variantes | story 3.12 |
| cas de test qui suppose ne pas être `root` | `root` lit tout fichier quelles que soient ses permissions : un cas qui fait `chmod 000` puis attend une anomalie constate l'inverse. Invisible sur le poste, il a fait rougir la première exécution en CI, où le job tourne en `root` | `skip_if_root "<ce qui est rendu illisible>"` en tête du cas : `run.sh` le compte comme ignoré **et affiche sa raison**, pour qu'une couverture moindre ne passe pas inaperçue. Le contrat lui-même se vérifie sans permissions, par un faux binaire qui rend le code voulu | story 3.13 |
| fichier de configuration présent mais vide | vérifier l'existence ne suffit pas : un fichier de motifs sans motif désactivait l'audit | vérifier qu'il contient au moins une entrée | story 0.8 (D2) |

## En cas d'échec d'un test

Le lanceur affiche le fichier, le cas et sa sortie. Corriger le script, ou le test s'il décrivait mal le comportement voulu, puis relancer `scripts/tests/run.sh` en entier avant de pousser.
