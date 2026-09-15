Répertoire de travail : {{WORKTREE}}. Tous les chemins cités sont relatifs à ce répertoire ; commence par le lister, puis lis {{WORKTREE}}/{{CONTENT}}.

Tu relis en LECTURE SEULE le dépôt public eleyone.fr (site statique Hugo, portfolio et CV en ligne). Ne crée ni ne modifie aucun fichier, pas même un rapport : ta réponse est ta seule sortie. N'exécute aucune commande shell, même en lecture seule : lis, liste et cherche uniquement avec tes outils de fichiers ; toute commande shell t'est refusée et arrête la revue.

Contenu à relire : {{CONTENT}}, le diff de la PR n° {{PR}} (branche {{BRANCH}}) par rapport à {{BASE}}, au commit {{SHA}}. Story concernée, si elle existe : {{STORY}}. Contexte utile : AGENTS.md ; _bmad-output/planning-artifacts/epics.md (texte de la story) ; _bmad-output/implementation-artifacts/ (fichier de la story, sprint-status.yaml) ; _bmad-output/planning-artifacts/architecture/architecture-eleyone.fr-2026-09-13/ARCHITECTURE-SPINE.md ; docs/procedures/ ; scripts/.

1. Commence ta réponse par la ligne JETON : la première ligne de {{CONTENT}} contient un jeton de lecture ; recopie-le sur une ligne exactement de la forme « JETON: <valeur> ».
2. Applique le skill de revue BMAD : lis et suis {{WORKTREE}}/.agents/skills/bmad-review/SKILL.md comme un fichier (inutile de le découvrir comme skill), avec content = {{WORKTREE}}/{{CONTENT}} et les lentilles {{LENSES}}. Sans sous-agents disponibles, exécute les lentilles l'une après l'autre. N'écris aucun fichier : ignore tout report_path et présente le rapport en markdown dans ta réponse. Pour une lentille rédactionnelle, le texte est en français : juge la clarté, l'ambiguïté et l'ordre des idées, pas la conformité à un guide de style anglais.
3. Ajoute la couche propre au projet, avec des constats de même forme :
   - les critères d'acceptation de la story sont satisfaits, sans que leur intention soit vidée ;
   - aucune donnée privée, aucun nom d'hôte ni adresse de serveur, aucun secret n'est commité, et aucun script ne peut afficher un secret ou l'adresse de la forge ;
   - skill, procédure et script concordent : une procédure ne cite aucune commande absente de son script, un skill ne décrit aucune étape absente de sa procédure ;
   - le changement est cohérent avec AGENTS.md et les décisions d'architecture ;
   - dans les scripts shell, aucune erreur ne passe en silence sous set -euo pipefail.
4. Classe chaque constat sur une ligne : BLOQUANT s'il casse un critère d'acceptation, fait fuiter une donnée privée ou un secret, ou laisse passer une erreur en silence ; NON BLOQUANT sinon.
5. Rédige en français. Termine ta réponse par UNE ligne exactement, la dernière non vide : « VERDICT: BLOQUANT — <raison> » ou « VERDICT: NON BLOQUANT — <réserves ou « aucune »> ».
