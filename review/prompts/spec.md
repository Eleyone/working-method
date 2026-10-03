Répertoire de travail : {{WORKTREE}}. Tous les chemins cités sont relatifs à ce répertoire ; commence par le lister, puis lis {{WORKTREE}}/{{CONTENT}}.

Tu relis en LECTURE SEULE le dépôt que décrit la couche projet, à la fin de cette consigne. Ne crée ni ne modifie aucun fichier, pas même un rapport : ta réponse est ta seule sortie. N'exécute aucune commande shell, même en lecture seule : lis, liste et cherche uniquement avec tes outils de fichiers ; toute commande shell t'est refusée et arrête la revue.

Contenu à relire : {{CONTENT}}, le texte de la story {{STORY}} du backlog, AVANT son implémentation, tel qu'il est sur la branche {{BASE}} au commit {{SHA}}. Le but est de lever les failles de la spec : ambiguïtés, contradictions, critères invérifiables ou manquants, cas oubliés, incohérences avec les règles et l'architecture du projet ou avec les stories voisines. Le contexte utile est celui que donne la couche projet ; ses contrôles de revue du code servent ici de contexte, pas de liste à appliquer.

1. Commence ta réponse par la ligne JETON : la première ligne de {{CONTENT}} contient un jeton de lecture ; recopie-le sur une ligne exactement de la forme « JETON: <valeur> ».
2. Applique la méthode de revue que nomme la couche projet, avec content = {{WORKTREE}}/{{CONTENT}} (classe : docs, document qui définit un comportement) et les lentilles {{LENSES}}. Sans sous-agents disponibles, exécute les lentilles l'une après l'autre. N'écris aucun fichier : ignore tout report_path et présente le rapport en markdown dans ta réponse. Le texte est en français : pour les lentilles rédactionnelles, juge la clarté, l'ambiguïté et l'ordre des idées, pas la conformité à un guide de style anglais.
3. Classe chaque constat sur sa ligne : BLOQUANT si, laissé tel quel, il ferait implémenter autre chose que ce qui est voulu — deux lectures contradictoires possibles, un critère invérifiable ou absent qui ne prouverait donc jamais la story faite, un comportement qui contredit les règles ou une décision d'architecture du projet, un cas oublié qui ferait perdre une donnée ou fuiter une donnée privée ; NON BLOQUANT sinon, y compris pour la clarté et l'ordre des idées. Un constat qui ne peut pas être classé est BLOQUANT : il n'est pas compris.
4. Rédige en français. N'écris **aucune** ligne `VERDICT:` : elle n'appartient qu'à la revue du code. Termine ta réponse par une section « À trancher avant d'implémenter » : la liste courte des points de la spec qui exigent une décision humaine, ou « aucun ».

Couche projet :

{{PROJECT_LAYER}}
