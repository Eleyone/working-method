# Procédure — Contrôles bloquants

## Écrire un contrôle

Un contrôle est un `scripts/checks/<nom>.sh` qui charge `scripts/checks/lib.sh`, lit les manifestes du rendu de travail et rend `0`, `1` ou `2`.

```bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
manifests=$(checks_manifests build/work)
```

- **Signalements** : `checks_report <fichier> <écart>` écrit `<fichier>: <écart>` sur la sortie d'erreur. Un contrôle nomme toujours le fichier et l'écart, jamais seulement le nombre.
- **Brouillons** (AD-10) : sur un fichier en `draft: true`, une valeur qui commence par `[TODO` passe toutes les règles de **forme**. `checks_is_todo <valeur>` et `checks_tolerated <brouillon> <valeur>` donnent l'outil ; la bibliothèque n'écarte rien d'elle-même, parce que la parité (C3), la liste des rubriques (C4) et le garde-fou s'appliquent aussi aux brouillons.
- **Forme du manifeste** : documentée en tête de `scripts/checks/lib.sh`, définie une seule fois dans `layouts/home.checks.json`. Une entrée peut porter `error` (front matter absent, suffixe de langue absent, page introuvable) : un contrôle lit `error` avant tout le reste.
- **Niveau** : `CHECK_LEVEL` vaut `standard`, ou `release` avec `--release`. Un contrôle de mise en ligne ne juge rien hors de `release` — `dev` porte des cas en brouillon et les valeurs légales factices, et il y échouerait à chaque PR —, mais il **dit** qu'il est sauté avant de rendre `0` : un `exit 0` muet cacherait un nom de variable mal écrit. C15 (`scripts/checks/release-pages.sh`) est le premier de cette famille, C22 (`scripts/checks/output-patterns.sh`) le second.
- **Racine du rendu** : un contrôle lit `${CHECK_WORK_ROOT:-build/work}`, pour qu'un cas de test le lance sur des manifestes écrits à la main sans toucher au rendu du dépôt.
- **Une liste vide n'est pas une conformité** : un contrôle qui parcourt des fichiers vérifie qu'il en a trouvé au moins un avant de conclure, sans quoi une racine erronée ou une sortie de build vide passeraient pour un succès (rétrospective de l'epic 3).
- **Les enveloppes sont communes** : `checks_xpath`, `checks_attributes` et `checks_find` dans `scripts/checks/lib.sh`, `shell_grep` et `shell_grep_into` dans `scripts/lib/shell.sh`, partagées avec les tests et les scripts. Un contrôle n'écrit pas la sienne.
- **Lire une chaîne dans une sortie de Hugo** : `decoder_echappements` puis `normaliser_blancs` (`scripts/lib/text.sh`, chargés par `scripts/checks/lib.sh` ; la répétition générale s'en sert aussi depuis la story 11.9), dans cet ordre. Une même chaîne y a **six** sérialisations constatées — entités décimales, hexadécimales ou nommées, séquences `\uXXXX` du JSON-LD de Go — et le rendu de production est minifié : chercher la chaîne brute dans un HTML échappé ne trouve rien et passe pour vert (huit tours de revue sur la PR n° 98). Après normalisation, un fichier tient sur **une seule ligne**, ce qui est aussi ce qui rend sûre une recherche par `grep`, qui travaille ligne par ligne. La résolution d'une `RelPermalink` en chemin de fichier est `checks_page_de_url`.
- **Confronter à la liste des motifs** : `pdf_confront` (`scripts/lib/pdf.sh`), partagée par C21, C22 et le garde-fou. Elle rend des **numéros de ligne**, jamais le motif ni l'extrait ; tout code autre que `0` et `1` est un échec de recherche, jamais « rien trouvé ». Un contrôle n'écrit pas sa propre recherche (constat A2, rétrospective de l'epic 7).

## Tester un contrôle

Les cas vivent dans `scripts/tests/test-*.sh` et suivent `docs/procedures/shell-scripts.md`.

- **La logique d'un contrôle** se teste sur des **manifestes écrits à la main** sous `scripts/tests/fixtures/` : rapide, hors ligne, sans Hugo.
- **La forme du manifeste** se teste une seule fois, par `scripts/tests/test-checks-manifest.sh` : un site fixture (`scripts/tests/fixtures/site/`) construit avec le Hugo épinglé, avec les gabarits, la configuration et les données du dépôt, puis lu à `jq`. C'est le seul cas qui lance un vrai build.
- **L'orchestration** (ordre des builds, découverte, cumul, codes de sortie) se teste sur un faux dépôt, avec un `build.sh` bouchonné : `scripts/tests/test-check.sh`.

