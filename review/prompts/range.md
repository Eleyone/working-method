Répertoire de travail : {{WORKTREE}}. Tous les chemins cités sont relatifs à ce répertoire ; commence par le lister, puis lis {{WORKTREE}}/{{CONTENT}}.

Tu relis en LECTURE SEULE le dépôt public eleyone.fr (site statique Hugo, portfolio et CV en ligne). Ne crée ni ne modifie aucun fichier, pas même un rapport : ta réponse est ta seule sortie. N'exécute aucune commande shell, même en lecture seule : lis, liste et cherche uniquement avec tes outils de fichiers ; toute commande shell t'est refusée et arrête la revue.

Contenu à relire : {{CONTENT}}, le diff complet d'une plage de commits — un epic entier — dont chaque story a déjà été relue séparément et fusionnée. **Ton travail n'est pas de refaire ces revues.** Cherche ce qu'aucune revue de story ne pouvait voir, c'est-à-dire ce qui se joue **entre** les stories :

- une règle appliquée différemment d'une story à l'autre (nommage, messages, codes de sortie) ;
- du code dupliqué entre deux stories, qui appelait une mise en commun ;
- une décision d'une story annulée ou contredite par une story suivante ;
- une couverture de test absente précisément à la frontière entre deux stories ;
- un commentaire ou une documentation devenus faux à cause d'une story ultérieure ;
- du code mort laissé par une story dont une suivante a changé l'approche.

La copie contient le dépôt **au commit de fin de la plage** : tu peux y lire les fichiers dans leur état final, les procédures de docs/procedures/ et les artefacts de cadrage de _bmad-output/. Le diff, lui, écarte _bmad-output/ : son volume noierait le code. Contexte utile : AGENTS.md ; docs/procedures/shell-scripts.md (règles d'écriture des scripts et pièges connus) ; _bmad-output/planning-artifacts/architecture/architecture-eleyone.fr-2026-09-13/ARCHITECTURE-SPINE.md.

1. Commence ta réponse par la ligne JETON : la première ligne de {{CONTENT}} contient un jeton de lecture ; recopie-le sur une ligne exactement de la forme « JETON: <valeur> ».
2. Applique le skill de revue BMAD : lis et suis {{WORKTREE}}/.agents/skills/bmad-review/SKILL.md comme un fichier (inutile de le découvrir comme skill), avec content = {{WORKTREE}}/{{CONTENT}} (classe : code) et les lentilles {{LENSES}}. Sans sous-agents disponibles, exécute les lentilles l'une après l'autre. N'écris aucun fichier : ignore tout report_path et présente le rapport en markdown dans ta réponse.
3. Pour chaque constat : l'emplacement (fichier:ligne), la condition qui le déclenche, le correctif suggéré, la conséquence, et la classification BLOQUANT ou NON BLOQUANT. Un constat que tu ne peux pas rattacher à une ligne du diff ou du dépôt n'est pas un constat : ne le rends pas.
4. Termine par une ligne « VERDICT: BLOQUANT — … » ou « VERDICT: NON BLOQUANT — … ».
