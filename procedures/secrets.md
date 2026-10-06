# Procédure — Aucun secret, aucun nom de projet

Ce dépôt est **public**, et consommé par plusieurs projets. Deux contrôles de sa CI le gardent ; ils se lancent aussi sur le poste.

```bash
ci/check-secrets.sh                   # arbre de travail, puis historique de toutes les références
ci/check-secrets.sh tree              # fichiers suivis de l'arbre de travail seulement
ci/check-secrets.sh history [<plage>] # lignes ajoutées, messages et chemins de chaque commit
ci/check-names.sh                     # noms des projets consommateurs dans l'arbre
```

Codes de sortie : `0` rien trouvé ; `1` au moins un signalement ; `2` contrôle impossible.

## « Aucun secret » (AC 11)

Modèle : le garde-fou public/privé du projet source, qui refuse des chemins interdits et des motifs dans le contenu **et** dans l'historique. Différence assumée : ce qui est cherché ici est un secret **de forme connue**, pas une donnée personnelle ; la liste des motifs est donc publique, dans le script.

- **Chemins interdits**, dans l'arbre et dans tout l'historique (même supprimés depuis) : `.env` et ses variantes (`.env.example`, `.env.dist`, `.env.sample` exceptés), clés SSH privées, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.kdbx`, `.netrc`, `.git-credentials`, `.pgpass`.
- **Motifs**, dans chaque ligne ajoutée par chaque commit, dans chaque message de commit et dans l'arbre : clés privées, jetons GitHub, GitLab, AWS, Slack, Anthropic, OpenAI, Google, variable `…TOKEN`, `…SECRET`, `…PASSWORD` ou `…API_KEY` affectée d'une valeur de 20 caractères ou plus, identifiants dans une adresse (`https://<compte>:<secret>@…`). Un repère (`<jeton>`, `${{ secrets.X }}`) n'est pas une valeur.
- **Un signalement donne l'endroit, jamais le contenu** : commit, fichier, ligne, et le numéro du motif. Afficher le secret dans le journal de la CI publierait ce que le contrôle doit empêcher.
- **Tout l'historique est relu**, et la CI fait un checkout complet (`fetch-depth: 0`) : un commit poussé reste lisible par son SHA, même après réécriture.

Chaque motif est écrit pour ne pas se trouver lui-même, et le contrôle passe sur son propre dépôt : un cas de `tests/test-ci-checks.sh` le vérifie.

### En cas de signalement

1. Ne pas pousser, ou arrêter le miroir public s'il a déjà synchronisé (`github-mirror.md`).
2. **Révoquer** le secret, s'il a quitté le poste.
3. Retirer le secret, puis réécrire l'historique : sur `main`, protégée, c'est une décision du propriétaire du dépôt, et une levée de protection tracée.

## « Aucun nom de projet » (AC 3)

Tout ce qui est propre à un projet se lit dans son `workflow.config` : un nom de projet consommateur dans l'arbre est le signe d'une valeur restée en dur. `ci/check-names.sh` cherche, sans tenir compte de la casse, chaque nom dans le contenu des fichiers suivis et dans leurs chemins.

```bash
CHECK_NAMES_PATTERNS="$(cat <liste hors du dépôt>)" ci/check-names.sh
ci/check-names.sh --patterns-file <liste hors du dépôt>
```

- ⛔ **La liste des noms n'est pas dans l'arbre** : écrite ici, elle serait elle-même un nom de projet dans le dépôt commun (constat bloquant de la première revue). Comme le garde-fou du projet source lit ses motifs hors du dépôt, ce contrôle reçoit la sienne de l'extérieur : en CI, la **variable d'Actions du dépôt `CHECK_NAMES_PATTERNS`** (une expression régulière étendue par ligne, lignes vides et `# …` ignorées) ; sur le poste, un fichier.
- **Sans liste, ou avec une liste vide, le contrôle sort en `2`** : un contrôle sans liste ne contrôle rien, et ne passe jamais pour vert. Une expression invalide sort en `2` aussi.
- Un signalement donne le fichier et la ligne, jamais le nom trouvé.
- Le contrôle porte sur l'**arbre**, pas sur l'historique (précision du 03/10/2026) : l'historique importé du projet source garde ses références.
- **Un nouveau projet consommateur** ajoute son nom à la variable, dans la PR qui l'adopte (réglage du dépôt → Actions → Variables, ou `PUT /repos/<propriétaire>/working-method/actions/variables/CHECK_NAMES_PATTERNS`), et la PR le dit.

### Citer un projet : `<alias>#<clé>`

Décision du 06/10/2026. Une origine — la colonne « Trouvé à » d'un piège (`shell-scripts.md`), le commentaire qui dit d'où vient un script — peut citer le projet où elle est née sous une forme courte et spécifique : **`<alias>#<clé>`**, entre accents graves, par exemple `calculette#outillage-14`. Elle remplace « projet consommateur », qui ne permettait pas de retrouver le constat.

- **L'alias** est un mot court, en minuscules, déclaré dans la table ci-dessous. Il n'est pas le nom du projet : `ci/check-names.sh` doit l'accepter, et la CI le prouve à chaque PR en lisant l'arbre avec la vraie liste. ⛔ Un alias que la liste refuserait ne s'écrit pas.
- **La clé** est, en minuscules, la clé d'une story ou d'un ticket du suivi de sprint de ce projet (`outillage-3`, `fix-promotion-image-reussit-a-vide`), ou le nom d'un artefact de planification sans son extension (`sprint-change-proposal-2026-09-30`). Un constat né hors de toute story cite celle qui l'a consigné, et sa date entre parenthèses : `calculette#outillage-3` (constat du 09/09/2026). L'alias ne s'écrit jamais sans clé.
- **Les clés `outillage-*` citées sans alias** avant cette décision (`story outillage-14`) sont celles de `calculette`.
- **Le projet source** — celui dont l'outillage a été extrait — reste « le projet source » : ses stories se citent par leur numéro (`story 0.7`), ses renvois de PR `(<projet source>#N)` (`README.md`, *Origine*).
- ⛔ **Ce qui reste interdit**, alias ou non : un nom de projet que la liste refuse, un nom de personne, une donnée privée (adresse de la forge, contenu d'un fichier privé, valeur d'un `.env`, motif du garde-fou ou de cette liste).
- **Déclarer un alias** : le vérifier contre la liste sans l'afficher — dans un dépôt d'essai dont un fichier suivi contient l'alias, `ci/check-names.sh --patterns-file <liste>` doit rendre `0` —, puis l'ajouter à la table dans la PR qui l'emploie la première, et le dire.
- **Ce qui est vérifié** : `tests/test-origines.sh` lit la colonne « Trouvé à » du tableau des pièges ; chaque cellule cite une story du projet source (`story`, `stories`, `rétrospective`) ou un `<alias>#<clé>` dont l'alias est déclaré, et aucune ne dit « projet consommateur ». Ailleurs — un commentaire de script, une procédure —, la forme n'est pas vérifiée par un test : la revue la relit, et `ci/check-names.sh` garde, sur tout l'arbre, l'interdit qui compte.

| Alias | Projet | Déclaré le |
|---|---|---|
| `calculette` | le premier projet à avoir consommé ce dépôt en sous-module ; ses stories `outillage-*` ont conduit l'extraction | 06/10/2026 |
