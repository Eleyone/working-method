#!/usr/bin/env bash
# La section « open_questions » du suivi de sprint, lue par gates/sprint-consistency.sh ; puis les
# chemins et la convention du suivi, lus dans workflow.config.
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
  write_workflow_config "$work/depot"
}

controle() { ( cd "$work/depot" && "$common/gates/sprint-consistency.sh" "$@" ); }

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

# --- les chemins et la convention viennent de workflow.config ------------------------------------

case_sprint_chemins_lus_dans_workflow_config() {
  # Le suivi déplacé ailleurs : le contrôle le suit, et l'ancien emplacement ne compte plus.
  depot_avec
  mkdir -p "$work/depot/suivi"
  mv "$work/depot/_bmad-output/implementation-artifacts/sprint-status.yaml" \
    "$work/depot/_bmad-output/implementation-artifacts/0-1-premiere-story.md" "$work/depot/suivi/"
  write_workflow_config "$work/depot" sprint.status-file=suivi/sprint-status.yaml sprint.stories-dir=suivi
  run controle
  assert_eq 0 "$rc" "le suivi est lu là où workflow.config le place (messages : $err)"
  write_workflow_config "$work/depot"
  run controle
  assert_eq 2 "$rc" "à l'ancien emplacement, le suivi est absent"
  assert_contains "absent" "$err" "et le contrôle le dit"
}

case_sprint_desactive_le_dit() {
  depot_avec
  write_workflow_config "$work/depot" sprint.convention=none sprint.status-file=none \
    sprint.stories-dir=none sprint.spec-source=none
  run controle
  assert_eq 0 "$rc" "un suivi désactivé n'est pas un écart (messages : $err)"
  assert_contains "désactivé (sprint.convention = none)" "$out" "le contrôle le dit"
  assert_contains "aucune cohérence" "$out" "sans affirmer de cohérence"
  run controle --merge 0.1
  assert_eq 2 "$rc" "--merge sans suivi n'a pas de réponse"
}

# --- convention keyed (calculette#outillage-5) : les règles reprises du contrôle d'origine -----------

readonly art=_bmad-output/implementation-artifacts

# Suivi keyed cohérent, à la forme du suivi d'origine : bloc aliases:, epics nommés,
# rétrospective « optional », commentaires de fin de ligne, une entrée sans fichier (admise en keyed),
# des en-têtes de forme ancienne, et deux fichiers qui ne sont pas des stories.
depot_keyed() {
  new_repo
  mkdir -p "$work/depot/$art"
  cat > "$work/depot/$art/sprint-status.yaml" <<'YAML'
generated: 2026-07-06T10:30:00
aliases:
  court: fix-long-nom
development_status:
  epic-outillage: in-progress  # un commentaire
  fix-long-nom: review
  feat-direct: done
  chore-sans-fichier: done
  epic-outillage-retrospective: optional
YAML
  printf '# Court\n\nStatus: review  # en revue\n' > "$work/depot/$art/court.md"
  printf "# Direct\n\nstatus: 'done'\n" > "$work/depot/$art/feat-direct.md"
  printf '# Travail reporté\n' > "$work/depot/$art/deferred-work.md"
  printf "status: 'planning'\n" > "$work/depot/$art/spec-ancienne.md"
  write_workflow_config "$work/depot" workflow.schema=4 sprint.convention=keyed "sprint.non-story-files=deferred-work spec-*"
}

suivi_keyed() { printf '%s\n' "$1" >> "$work/depot/$art/sprint-status.yaml"; }

case_sprint_keyed_coherent() {
  depot_keyed
  run controle
  assert_eq 0 "$rc" "le suivi keyed cohérent passe (messages : $err$out)"
  assert_contains "cohérent dans l'arbre de travail (3 stories, 1 epics, 2 fichiers de story, 1 alias, 0 question(s) ouverte(s))" "$out" "les comptes"
}

case_sprint_keyed_plus_petit_suivi_valide() {
  # L'exemple de procedures/sprint-consistency.md (« Un premier suivi ») : un seul epic, aucune story,
  # aucun fichier de story ; et la même section vide reste refusée.
  new_repo
  mkdir -p "$work/depot/$art"
  printf 'development_status:\n  epic-outillage: backlog\n' > "$work/depot/$art/sprint-status.yaml"
  write_workflow_config "$work/depot" workflow.schema=4 sprint.convention=keyed "sprint.non-story-files=deferred-work spec-*"
  run controle
  assert_eq 0 "$rc" "le plus petit suivi de la procédure passe (messages : $err$out)"
  assert_contains "(0 stories, 1 epics, 0 fichiers de story, 0 alias" "$out" "les comptes"
  printf 'development_status:\n' > "$work/depot/$art/sprint-status.yaml"
  run controle
  assert_eq 2 "$rc" "une section vide n'est jamais une cohérence"
}

case_sprint_keyed_lit_un_commit() {
  depot_keyed
  local sha
  sha=$(commit_all "suivi")
  printf 'Status: done\n' > "$work/depot/$art/court.md"
  run controle
  assert_eq 1 "$rc" "l'arbre de travail diverge"
  run controle --rev "$sha"
  assert_eq 0 "$rc" "le commit est cohérent (messages : $err$out)"
  assert_contains "dans le commit ${sha:0:7}" "$out" "le commit est nommé"
}

case_sprint_keyed_sous_dossier_ignore_dans_les_deux_lectures() {
  # Seuls les fichiers du dossier des stories comptent, pas ceux d'un sous-dossier : dans l'arbre de
  # travail (joker du shell) comme dans un commit (git ls-tree, sans -r, ne descend pas).
  depot_keyed
  mkdir -p "$work/depot/$art/archives"
  printf 'Status: done\n' > "$work/depot/$art/archives/vieille-story.md"
  local sha
  sha=$(commit_all "suivi")
  run controle
  assert_eq 0 "$rc" "arbre de travail : le sous-dossier est ignoré (messages : $err$out)"
  run controle --rev "$sha"
  assert_eq 0 "$rc" "commit : le sous-dossier est ignoré aussi (messages : $err$out)"
  assert_contains "2 fichiers de story" "$out" "même compte dans les deux lectures"
}

ecart_keyed() { # $1 message attendu ; le contrôle refuse en 1
  run controle
  assert_eq 1 "$rc" "écart constaté (messages : $err$out)"
  assert_contains "$1" "$out" "l'écart est nommé"
}

case_sprint_keyed_orphelin() {
  depot_keyed
  printf 'Status: done\n' > "$work/depot/$art/feat-oubliee.md"
  ecart_keyed "feat-oubliee.md — aucune entrée dans le suivi (ni directe, ni par alias)"
}

case_sprint_keyed_sans_liste_tout_md_est_une_story() {
  depot_keyed
  write_workflow_config "$work/depot" workflow.schema=4 sprint.convention=keyed sprint.non-story-files=none
  ecart_keyed "spec-ancienne.md — aucune entrée dans le suivi"
}

case_sprint_keyed_en_tete_divergent() {
  depot_keyed
  printf 'Status: done\n' > "$work/depot/$art/court.md"
  ecart_keyed "court.md — en-tête « done », suivi « review » (clé : fix-long-nom)"
}

case_sprint_keyed_en_tete_absent_ou_hors_vocabulaire() {
  depot_keyed
  printf '# Court\n' > "$work/depot/$art/court.md"
  ecart_keyed "court.md — aucun en-tête « Status: » lisible"
  printf 'Status: termine\n' > "$work/depot/$art/court.md"
  ecart_keyed "court.md — en-tête « termine » n'est pas un statut de story"
}

case_sprint_keyed_alias_sans_cible() {
  depot_keyed
  sed -i 's/^  court: fix-long-nom$/  court: fix-long-nom\n  perime: fix-disparu/' "$work/depot/$art/sprint-status.yaml"
  ecart_keyed "alias sans cible : perime → fix-disparu (clé absente de development_status)"
}

case_sprint_keyed_rattachement_ambigu() {
  depot_keyed
  sed -i 's/^  court: fix-long-nom$/  court: fix-long-nom\n  feat-direct: fix-long-nom/' "$work/depot/$art/sprint-status.yaml"
  ecart_keyed "feat-direct.md — clé directe ET alias : rattachement ambigu"
}

case_sprint_keyed_statuts_hors_vocabulaire() {
  depot_keyed
  suivi_keyed '  epic-autre: finie
  epic-autre-retrospective: backlog
  fix-autre: draft'
  run controle
  assert_eq 1 "$rc" "trois statuts hors vocabulaire"
  assert_contains "statut d'epic invalide : epic-autre = « finie »" "$out" "l'epic"
  assert_contains "statut de rétrospective invalide : epic-autre-retrospective = « backlog »" "$out" "la rétrospective"
  assert_contains "statut de story invalide : fix-autre = « draft »" "$out" "la story"
}

case_sprint_keyed_epic_non_derive_des_stories() {
  # En keyed, rien ne relie une story à son epic : le statut d'un epic n'est vérifié que contre le
  # vocabulaire. Un epic « backlog » dont des stories sont « done » n'est pas un écart.
  depot_keyed
  sed -i 's/^  epic-outillage: in-progress.*/  epic-outillage: backlog/' "$work/depot/$art/sprint-status.yaml"
  run controle
  assert_eq 0 "$rc" "aucun écart d'epic en keyed (messages : $err$out)"
}

case_sprint_keyed_merge() {
  depot_keyed
  run controle --merge feat-direct
  assert_eq 0 "$rc" "story à done des deux côtés (messages : $err$out)"
  assert_contains "story feat-direct à done, fusion admise" "$out" "la story est nommée"
  run controle --merge fix-long-nom
  assert_eq 1 "$rc" "story à review"
  assert_contains "story fix-long-nom à review dans le suivi : fusion refusée" "$out" "la raison"
  run controle --merge feat-inconnue
  assert_eq 1 "$rc" "story absente"
  assert_contains "story feat-inconnue absente du suivi : fusion refusée" "$out" "la raison"
  run controle --merge chore-sans-fichier
  assert_eq 1 "$rc" "story à done sans fichier"
  assert_contains "story chore-sans-fichier sans fichier de story : fusion refusée" "$out" "la raison"
}

case_sprint_keyed_merge_par_alias() {
  depot_keyed
  sed -i 's/^  fix-long-nom: review$/  fix-long-nom: done/' "$work/depot/$art/sprint-status.yaml"
  printf 'Status: done\n' > "$work/depot/$art/court.md"
  run controle --merge fix-long-nom
  assert_eq 0 "$rc" "la story est à done dans le fichier qui porte l'alias (messages : $err$out)"
}

case_sprint_merge_selon_la_convention() {
  depot_keyed
  run controle --merge 0.1
  assert_eq 2 "$rc" "un numéro n'est pas une clé keyed"
  assert_contains "clé de story attendue après --merge" "$err" "le message dit quoi passer"
  depot_avec
  run controle --merge feat-direct
  assert_eq 2 "$rc" "une clé n'est pas un numéro numbered"
  assert_contains "numéro de story attendu après --merge" "$err" "le message dit quoi passer"
}

case_sprint_keyed_suivi_absent() {
  depot_keyed
  rm "$work/depot/$art/sprint-status.yaml"
  run controle
  assert_eq 2 "$rc" "sans suivi, aucune conclusion"
  assert_contains "absent" "$err" "le contrôle le dit"
}

case_sprint_keyed_liste_illisible() {
  skip_if_root "le dossier des stories"
  depot_keyed
  chmod 311 "$work/depot/$art" # le suivi reste lisible, la liste du dossier ne l est plus
  run controle
  chmod 755 "$work/depot/$art"
  assert_eq 2 "$rc" "dossier illisible : aucune conclusion"
  assert_contains "lecture de la liste des fichiers de story impossible" "$err" "et le contrôle le dit"
}

case_sprint_sans_workflow_config() {
  depot_avec
  rm "$work/depot/workflow.config"
  run controle
  assert_eq 2 "$rc" "sans workflow.config, aucune conclusion"
  assert_contains "absent ou illisible" "$err" "le message nomme le fichier"
}

run_case "$@"
