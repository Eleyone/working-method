#!/usr/bin/env bash
# La section « open_questions » du suivi de sprint, lue par scripts/sprint-consistency.sh.
#
# Pourquoi ces cas existent : la section a été ajoutée pour qu'une question de rétrospective ne se
# perde pas dans la prose d'un document. Une section que **rien ne lit** se perd de la même façon,
# et c'est le constat bloquant de la revue de la PR n° 107. Le contrôle la lit donc — et une lecture
# sans test n'est pas une lecture, elle est une intention (point 9 d'AGENTS.md).
#
# Chaque cas a été lancé une fois la garde retirée, pour le voir échouer.
#
# Le contrôle se place à la racine du dépôt git qu'il trouve : les cas montent donc un petit dépôt
# dans $work et l'y lancent, plutôt que de le faire tourner sur ce dépôt-ci.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Suivi minimal cohérent : une story done, son epic done, son fichier de story.
# $1 = contenu de la section open_questions, vide pour aucune section.
depot_avec() {
  new_repo
  mkdir -p "$work/depot/_bmad-output/implementation-artifacts"
  local suivi="$work/depot/_bmad-output/implementation-artifacts/sprint-status.yaml"
  cat > "$suivi" <<'EOF'
generated: 09-13-2026 22:58
development_status:
  epic-0: done
  0-1-premiere-story: done
EOF
  printf 'Status: done\n' > "$work/depot/_bmad-output/implementation-artifacts/0-1-premiere-story.md"
  [[ -z ${1:-} ]] || printf '%s\n' "$1" >> "$suivi"
}

controle() { ( cd "$work/depot" && "$root/scripts/sprint-consistency.sh" ); }

# --- le cas nominal : la section est lue, et son compte s'affiche -------------------------------

case_sprint_deux_questions_sont_comptees() {
  depot_avec 'open_questions:
  - id: "premiere"
    epic: 3
    question: "Une question."
    state: "Un état."
    lands_in: "une story"
  - id: "seconde"
    epic: 5
    question: "Une autre."
    state: "Un autre état."
    lands_in: "rien"'
  run controle
  assert_eq 0 "$rc" "le contrôle passe (messages : $err)"
  assert_contains "2 question(s) ouverte(s)" "$out" "le compte est affiché"
}

case_sprint_sans_section_le_compte_est_zero() {
  # La section est facultative : son absence n'est pas un écart. Sans ce cas, une garde trop stricte
  # ferait échouer tout suivi antérieur à la section.
  depot_avec
  run controle
  assert_eq 0 "$rc" "le contrôle passe sans la section (messages : $err)"
  assert_contains "0 question(s) ouverte(s)" "$out" "le compte vaut zéro"
}

case_sprint_valeurs_repliees_comme_en_production() {
  # **La fixture ressemble à la vraie donnée** (point 16 d'AGENTS.md). « sprint_status.py » replie
  # toute valeur longue sur des lignes de continuation plus indentées, et les neuf entrées réelles
  # en portent. Une première écriture de ce fichier n'employait que des valeurs d'une seule ligne :
  # la garde passait alors par chance, en ne lisant que la première ligne physique de chaque valeur
  # (constat bloquant de la seconde revue de la PR n° 107).
  depot_avec 'open_questions:
  - id: "repliee"
    epic: 3
    question: "Le substitut d'"'"'amorçage de verify-and-merge-pr.sh a-t-il encore un
      rôle une fois la CI en place ?"
    state: "Décrit comme « régime révolu mais pas mort » (docs/procedures/verify-and-merge-pr.md:44)
      ; le code vit toujours (scripts/verify-and-merge-pr.sh:188-206)."
    lands_in: "story 11.7 — epics.md:3011 porte « À trancher par Arnaud avant de commencer
      cette story (D-13) »"'
  #
  # **Ce cas ne prouve pas la garde** : lancé une fois le recollement retiré, il passe encore, parce
  # que la première ligne physique de chacune de ses valeurs porte déjà du texte. Il est ici pour la
  # ressemblance qu'exige le point 16 ; c'est le cas suivant qui prouve le recollement.
  run controle
  assert_eq 0 "$rc" "une entrée aux valeurs repliées est lue (messages : $err)"
  assert_contains "1 question(s) ouverte(s)" "$out" "et comptée une fois"
}

case_sprint_valeur_repliee_dont_la_premiere_ligne_est_vide() {
  # Le cas que le repli rend possible et qu'aucune valeur d'une seule ligne ne peut produire : toute
  # la substance est sur la continuation. En ne lisant que la première ligne, la garde déclarait la
  # clé vide et bloquait à tort. C'est l'inverse du piège de « state: "" » — un faux positif, pas un
  # faux négatif — et les deux viennent de la même lecture partielle.
  depot_avec 'open_questions:
  - id: "premiere-ligne-vide"
    epic: 3
    question: "
      Toute la question tient sur la ligne de continuation."
    state: "Un état."
    lands_in: "rien"'
  run controle
  assert_eq 0 "$rc" "la valeur portée par la seule continuation compte (messages : $err$out)"
}

case_sprint_espace_apres_le_nom_de_section() {
  # **Le faux négatif le plus grave possible ici.** L'en-tête de section était comparé à la chaîne
  # exacte « open_questions: » ; une espace en fin de ligne et toute la section était sautée **sans
  # un mot**, le contrôle annonçant zéro question et laissant passer n'importe quelle entrée cassée.
  # L'entrée ci-dessous est incomplète exprès : si la section est lue, elle est refusée ; si elle est
  # sautée, tout passe. C'est la différence entre les deux que le cas mesure.
  #
  # L'espace vient d'une **variable**, jamais d'un littéral : écrite en fin de ligne dans la source,
  # elle est supprimée en silence par les outils d'édition, et le cas ne testait alors rien de plus
  # que l'entrée incomplète. Constaté en le lançant avec la faute remise : il passait.
  local sp=' '
  depot_avec "open_questions:$sp
  - id: \"incomplete-sous-un-en-tete-avec-espace\"
    epic: 1
    question: \"Une question.\""
  run controle
  assert_eq 1 "$rc" "la section est lue malgré l espace finale, et son entrée incomplète refusée"
  assert_contains "absente ou vide" "$err$out" "et l écart porte bien sur les clés manquantes"
}

case_sprint_commentaire_apres_le_nom_de_section() {
  # Même faute, autre forme : un commentaire YAML derrière le nom de la section. Le point 18
  # d'AGENTS.md demande de réénumérer ce qu'une condition laisse passer, pas d'ajouter le seul cas cité.
  depot_avec 'open_questions:  # les questions des rétrospectives
  - id: "incomplete-sous-un-en-tete-commente"
    epic: 1
    question: "Une question."'
  run controle
  assert_eq 1 "$rc" "un commentaire derrière le nom de section ne fait pas sauter la lecture"
}

case_sprint_lands_in_rien_est_accepte() {
  # « rien » est une valeur **légitime** : l'aveu qu'aucune story ne ramènera la question. La refuser
  # forcerait une réponse fausse, et la section perdrait ce qu'elle sert à montrer.
  depot_avec 'open_questions:
  - id: "sans-porteur"
    epic: 4
    question: "Une question que rien ne porte."
    state: "Aucune trace."
    lands_in: "rien"'
  run controle
  assert_eq 0 "$rc" "une question sans porteur ne fait pas échouer le contrôle (messages : $err)"
}

# --- les entrées que la garde doit refuser ------------------------------------------------------

case_sprint_cle_manquante_est_refusee() {
  depot_avec 'open_questions:
  - id: "incomplete"
    epic: 2
    question: "Une question."
    lands_in: "une story"'
  run controle
  assert_eq 1 "$rc" "une entrée sans « state » est un écart"
  assert_contains "clé « state » absente" "$err$out" "et l écart nomme la clé"
  assert_contains "incomplete" "$err$out" "et l entrée"
}

case_sprint_cle_vide_vaut_cle_absente() {
  # Une clé présente mais vide est le cas que la relecture humaine laisse passer : elle **paraît**
  # renseignée. Sans ce cas, la garde ne testerait que la clé franchement absente.
  depot_avec 'open_questions:
  - id: "vide"
    epic: 2
    question: "Une question."
    state: ""
    lands_in: "une story"'
  run controle
  assert_eq 1 "$rc" "une clé vide est un écart"
  assert_contains "clé « state » absente ou vide" "$err$out" "et le message dit les deux cas"
}

case_sprint_identifiant_repete_est_refuse() {
  depot_avec 'open_questions:
  - id: "meme-id"
    epic: 1
    question: "Première."
    state: "Un état."
    lands_in: "rien"
  - id: "meme-id"
    epic: 2
    question: "Seconde."
    state: "Un état."
    lands_in: "rien"'
  run controle
  assert_eq 1 "$rc" "un identifiant répété est un écart"
  assert_contains "identifiant répété" "$err$out" "et le message le dit"
  # **Un seul écart, et vrai.** La garde signalait en plus « clé « id » absente ou vide » : elle est
  # présente, elle est seulement répétée. Une assertion qui n'aurait cherché que le bon message
  # aurait laissé passer le mauvais à côté (constat de la quatrième revue de la PR n° 107).
  [[ $err$out != *"clé « id » absente"* ]] \
    || { echo "la garde prétend aussi que « id » est absente, ce qui est faux" >&2; exit 1; }
}

case_sprint_ligne_vide_dans_une_valeur_repliee() {
  # **Ce cas ne garde rien ; il épingle une propriété.** Une revue annonçait qu'une ligne vide au
  # milieu d'une valeur repliée interromprait la lecture, et une garde a été écrite pour ça. Le cas,
  # lancé sans elle, est passé : rien ne réinitialise la lecture sur une ligne vide. La garde est
  # partie, le cas reste — il refuserait le jour où un traitement des lignes vides serait ajouté et
  # casserait cette propriété. Ici, toute la substance est **après** la ligne vide.
  depot_avec 'open_questions:
  - id: "avec-ligne-vide"
    epic: 6
    question: "

      La substance est après la ligne vide."
    state: "Un état."
    lands_in: "rien"'
  run controle
  assert_eq 0 "$rc" "la valeur reprend après la ligne vide (messages : $err$out)"
}

case_sprint_identifiant_vide_est_refuse() {
  depot_avec 'open_questions:
  - id: ""
    epic: 1
    question: "Une question."
    state: "Un état."
    lands_in: "rien"'
  run controle
  assert_eq 1 "$rc" "un identifiant vide est un écart"
  assert_contains "« id » vide" "$err$out" "et le message le dit"
}

case_sprint_entree_sans_id_en_tete_est_signalee() {
  # Le contrôle lit l'entrée à partir de sa ligne « - id: ». Une entrée écrite autrement ne serait
  # pas lue — et ses clés manquantes ne seraient **jamais** vues. Elle est donc signalée plutôt
  # qu'ignorée : une garde qui saute silencieusement ce qu'elle ne comprend pas ne garde rien.
  depot_avec 'open_questions:
  - epic: 1
    id: "id-pas-en-tete"
    question: "Une question."
    state: "Un état."
    lands_in: "rien"'
  run controle
  assert_eq 1 "$rc" "une entrée qui ne commence pas par « - id: » est un écart"
  assert_contains "doit commencer par" "$err$out" "et le message dit quoi faire"
}

case_sprint_la_section_suivante_ferme_la_lecture() {
  # Une clé de premier niveau ferme la section. Sans cela, les entrées d'une section voisine
  # seraient lues comme des questions, et le compte comme les écarts porteraient sur autre chose.
  depot_avec 'open_questions:
  - id: "seule"
    epic: 1
    question: "Une question."
    state: "Un état."
    lands_in: "rien"
action_items:
  - id: "une-action"
    epic: 1
    action: "Une action, qui ne porte ni question ni state."
    status: done'
  run controle
  assert_eq 0 "$rc" "les entrées d action_items ne sont pas lues comme des questions (messages : $err)"
  assert_contains "1 question(s) ouverte(s)" "$out" "une seule question est comptée"
}

run_case "$@"
