# Procédure — bash, prérequis de l'outillage, et le runner de la forge

Reprise de la note d'exploitation écrite en phase A de la story outillage-14 (03/10/2026), dans le dépôt du premier projet qui l'a constaté.

## La règle

- **bash 4.3 ou plus** est un prérequis de tout l'outillage commun : `local -n` (références de variables, `lib/shell.sh`, `lib/config.sh`) date de bash 4.3, `declare -A` (`gates/sprint-consistency.sh`) de 4.0.
- Il est **vérifié avant la première ligne de bash**, par du POSIX sh : `bin/check-bash` (et `bin/install`, qui l'appelle). Sans bash, ou avec un bash trop ancien, la sortie est un message explicite et le code **`2`** — jamais une erreur de syntaxe à mi-parcours (AC 9).
- En CI, la vérification est le premier pas du job, **en `shell: sh`** : sans cette ligne, le pas tournerait sous bash, et un bash absent le ferait échouer avant le contrôle qui doit le dire.

```bash
sh bin/check-bash      # « check-bash : bash 5.3.9(1)-release », code 0
```

## Le runner de la forge (constat du 03/10/2026)

| Élément | Constat |
|---|---|
| Runners | deux conteneurs, enregistrés `docker-runner-1` et `docker-runner-2`, partagés par tous les projets de la forge |
| Mode d'exécution | **hôte** : les pas `run:` tournent dans le conteneur du runner, aucune image de job n'est tirée |
| Labels | `ubuntu-latest`, `linux_amd64`, `docker`, `linux`, `x64`, `self-hosted`, tous en `:host` |
| Système | Alpine 3.24.1, outils de BusyBox |
| bash | `GNU bash, version 5.3.9(1)-release`, installé dans l'image depuis le 19/09/2026 |
| Absents | `coreutils`, **`jq`** (fourni au job par `ci/ensure-jq.sh`, binaire épinglé par version et SHA-256), `shellcheck` |

⚠️ **Conséquences pour un script :**

- Les pas **sans** `shell:` tournent sous `bash --noprofile --norc -e -o pipefail` dès que bash est présent : ce n'est pas du `sh`.
- BusyBox n'est pas GNU : son `find` ignore `-printf` (d'où `stat` dans `tests/run.sh`), et ses outils diffèrent sur les options rares. Lancer le job de CI avant de livrer un script que la CI exécute.
- Rien ne s'installe sur le runner, qui est partagé : un outil manquant se télécharge, épinglé, dans un dossier temporaire du job, comme `jq`.

## Preuve de référence

Un `docker exec` ne prouve que le conteneur ; ce qui compte est **le job**. La preuve se fait par un `workflow_dispatch` sur une branche jetable, avec un pas `bash --version` sur chaque label, après avoir vérifié qu'aucun run n'est actif. C'est ainsi qu'a été faite celle du 03/10/2026 (run 2476 du dépôt où la phase A a été menée : deux jobs verts, un par label).

## Retour arrière

⛔ Retirer bash de l'image du runner serait une **régression** : tous les projets dont les pas tournent sous bash, et cet outillage, cesseraient de fonctionner. Toute modification de l'image se fait avec sauvegarde, tag de retour arrière, aucun job interrompu, et preuve par un vrai job.
