---
name: llm-review
description: Fait relire par un LLM d'un autre fournisseur la spec d'une story du dépôt eleyone.fr avant son implémentation (--story), ou le diff d'une pull request avec un verdict publié sur la PR (numéro de PR). À utiliser au début de chaque story, puis sur chaque PR avant sa fusion.
---

# llm-review

Revue par un relecteur d'un autre fournisseur que l'auteur, qui applique le skill `bmad-review` dans une copie isolée du dépôt.

La procédure fait foi : `docs/procedures/llm-review.md`. L'exécution est `scripts/llm-review.sh`.

À retenir :

- au début de chaque story, sur sa branche : revue de spec par `--story <n.m>`, puis tri de chaque constat dans le fichier de story, avant de reformuler la story et de poser les questions à Arnaud ;
- sur chaque PR, après le commit de statut `review` : revue du code par le numéro de la PR ; le verdict est publié en commentaire, puis chaque constat reçoit sa décision dans la section « Revue du code » du fichier de story ;
- tu ne relis jamais à la place du relecteur, et tu ne changes pas de modèle : l'auteur Claude est relu par Gemini, un auteur Gemini (`AUTHOR_LLM=gemini`) par Claude ;
- la revue dure plusieurs minutes : lance-la en arrière-plan et attends sa fin ;
- un échec ne publie rien : corrige la cause indiquée, puis relance.
