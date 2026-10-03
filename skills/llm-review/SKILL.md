---
name: llm-review
description: Fait relire par un LLM d'un autre fournisseur la spec d'une story avant son implémentation (--story), ou le diff d'une pull request avec un verdict publié sur la PR (numéro de PR), avec l'outillage du dépôt commun de méthode. À utiliser au début de chaque story, puis sur chaque PR avant sa fusion.
---

# llm-review

Revue par un relecteur d'un autre fournisseur que l'auteur, qui applique la méthode de revue de la couche projet dans une copie isolée du dépôt.

La procédure fait foi : `.working-method/procedures/llm-review.md`. L'exécution est `.working-method/review/llm-review.sh`, lancée depuis la racine du projet. Ce qui est propre au projet (relecteurs, délai, couche projet, chemins privés, suivi de sprint) se lit dans son `workflow.config`.

À retenir :

- au début de chaque story, sur sa branche : revue de spec par `--story <n.m>`, puis tri de chaque constat dans le fichier de story, avant de reformuler la story et de poser les questions au responsable du projet ;
- sur chaque PR, après le commit de statut `review` : revue du code par le numéro de la PR ; le verdict est publié en commentaire, puis chaque constat reçoit sa décision dans la section « Revue du code » du fichier de story ;
- tu ne relis jamais à la place du relecteur, et tu ne changes pas de modèle : l'auteur Claude est relu par le modèle de `review.reviewer-for-claude`, un auteur Gemini (`AUTHOR_LLM=gemini`) par celui de `review.reviewer-for-gemini` ;
- la revue dure plusieurs minutes : lance-la en arrière-plan et attends sa fin ;
- un échec ne publie rien : corrige la cause indiquée, puis relance.
- pour une **rétrospective d'epic**, `--range "<premier>^..<dernier>" --out <fichier>` relit le diff complet de la plage et n'écrit que dans ce fichier : rien n'est publié, et c'est la rétrospective qui cite le rapport après avoir rejoué chaque constat.
