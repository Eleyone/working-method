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

- **Quand** : avant toute PR qui touche `scripts/`, sur le poste ; en CI, par `scripts/ci/checks-job.sh` dans `CHECK_IMAGE` (story 3.12). Tant que la CI n'existe pas, le résultat est noté dans la PR.
- **Conditions** : aucun réseau, ni `.env` ni `docs/private/` ; dépendances `bash`, `git`, `jq`, `grep` GNU et outils de base. Chaque cas tourne dans son propre processus bash, pour que `set -e` y reste actif.
- **Ajouter un cas** : une fonction `case_<nom>` dans un fichier `scripts/tests/test-*.sh`, qui charge `scripts/tests/lib.sh` et se termine par `run_case "$@"`. Outils : `run` (code dans `rc`, sortie dans `out`, erreur dans `err`), `assert_eq`, `assert_contains`, `new_repo` et `commit_all` pour un dépôt git de test, `$work` pour les fichiers temporaires, `$fixtures` pour les fixtures versionnées sous `scripts/tests/fixtures/`.
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
| fichier de configuration présent mais vide | vérifier l'existence ne suffit pas : un fichier de motifs sans motif désactivait l'audit | vérifier qu'il contient au moins une entrée | story 0.8 (D2) |

## En cas d'échec d'un test

Le lanceur affiche le fichier, le cas et sa sortie. Corriger le script, ou le test s'il décrivait mal le comportement voulu, puis relancer `scripts/tests/run.sh` en entier avant de pousser.
