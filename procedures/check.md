# Procédure — Contrôles bloquants

Un projet a **un seul** point d'entrée de ses contrôles (`checks.command` de son `workflow.config`) : la même commande tourne sur le poste et dans chaque CI, si bien qu'un contrôle local ne peut pas diverger de celui d'une forge. Le dépôt commun fournit le **mécanisme** de ce point d'entrée, `checks/run-checks.sh` ; ce qui précède les contrôles (un build, le chargement de valeurs, un niveau de contrôle) reste dans le projet, qui appelle le mécanisme après ses propres étapes.

```bash
.working-method/checks/run-checks.sh                     # chaque contrôle par « bash <contrôle> »
.working-method/checks/run-checks.sh -- <commande>...    # chaque contrôle sous un préfixe, par exemple un chargeur de valeurs
```

## Ce que fait le mécanisme

1. Il lit `checks.dir` dans le `workflow.config` du projet. `none` : aucun contrôle n'est lancé, et il le dit. Un dossier déclaré mais absent est une anomalie (`2`), jamais une conformité.
2. Il lance **tous** les scripts `*.sh` de ce dossier, découverts dynamiquement, triés, `lib.sh` exclu : une story qui ajoute un contrôle dépose son script et ne touche pas au point d'entrée.
3. Tous tournent, même après un échec ; tous les écarts s'affichent, puis une ligne nomme les contrôles en échec. `CHECK_LEVEL`, s'il est posé par le projet, est transmis tel quel et nommé dans le résumé.

Codes de sortie : `0` conforme ; `1` écart constaté ; `2` anomalie (un contrôle sorti en `2` ou plus, option inconnue, dossier introuvable, `workflow.config` refusé). Un dossier sans aucun contrôle se dit (« aucun script de contrôle ») et rend `0`, comme dans le projet source.

## Écrire un contrôle

Un contrôle est un `<checks.dir>/<nom>.sh` qui rend `0`, `1` ou `2`. Les règles suivantes viennent du projet source ; elles valent pour tout projet.

- **Signalements** : `<fichier>: <écart>` sur la sortie d'erreur. Un contrôle nomme toujours le fichier et l'écart, jamais seulement le nombre.
- **Niveau** : un contrôle qui ne juge qu'à un niveau donné (`CHECK_LEVEL`) **dit** qu'il est sauté avant de rendre `0` ailleurs : un `exit 0` muet cacherait un nom de variable mal écrit.
- **Racine de lecture paramétrable** : un contrôle lit ce qu'il juge sous une racine qu'une variable peut remplacer, pour qu'un cas de test le lance sur des entrées écrites à la main sans toucher aux sorties du projet.
- **Une liste vide n'est pas une conformité** : un contrôle qui parcourt des fichiers vérifie qu'il en a trouvé au moins un avant de conclure, sans quoi une racine erronée ou une sortie vide passeraient pour un succès (rétrospective de l'epic 3 du projet source).
- **Les enveloppes sont communes** : `shell_grep` et `shell_grep_into` dans `lib/shell.sh`, partagées avec les tests et les scripts ; les enveloppes propres aux contrôles d'un projet vivent dans son `<checks.dir>/lib.sh`. Un contrôle n'écrit pas la sienne.
- **Une recherche rend un code, jamais un silence** : tout code autre que `0` et `1` d'un `grep` est un échec de recherche, jamais « rien trouvé » (constat A2, rétrospective de l'epic 7 du projet source).

## Tester un contrôle

Les cas suivent `shell-scripts.md`.

- **La logique d'un contrôle** se teste sur des **entrées écrites à la main** sous les fixtures du projet : rapide, hors ligne, sans build.
- **Le mécanisme** (découverte, tri, cumul, codes de sortie, préfixe, `checks.dir`) se teste sur un faux dépôt : `tests/test-run-checks.sh` du dépôt commun.
- **Les étapes propres au projet** (son build, son chargeur, son niveau) se testent dans le projet, sur son propre point d'entrée.
