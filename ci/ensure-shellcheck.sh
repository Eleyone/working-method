#!/bin/sh
# Fournit shellcheck, à la version épinglée, à une étape de CI ou au poste, et affiche le DOSSIER où il
# se trouve. Jumeau de ci/ensure-jq.sh : mêmes gardes (architecture, curl, sha256sum, empreinte,
# binaire exécutable), une de plus ci-dessous.
#
# ⚠️ Le runner partagé exécute les jobs en mode hôte, dans un conteneur sans shellcheck ni apt-get. On
# n'installe RIEN sur le runner : on télécharge l'archive ÉPINGLÉE (version + SHA-256) dans un dossier
# temporaire du job, et on refuse toute archive dont l'empreinte diffère.
#
# ⭐ Différence voulue avec ensure-jq.sh : un shellcheck déjà présent n'est retenu que s'il est
# EXACTEMENT de la version épinglée. Les constats dépendent de la version ; une autre version sur le
# poste rendrait un vert que la CI ne rendrait pas, ou l'inverse. Sinon, l'archive épinglée est
# téléchargée, quelle que soit la version présente.
#
# Usage :
#   SC_DIR=$(sh ci/ensure-shellcheck.sh) && PATH="$SC_DIR:$PATH"
#
# Codes : 0 shellcheck disponible (dossier affiché) ; 2 impossible de le fournir (l'appelant DOIT
# échouer, jamais continuer sans shellcheck).
#
# Pour monter de version : changer SHELLCHECK_VERSION et SHELLCHECK_SHA256 ENSEMBLE, l'empreinte étant
# relevée dans la release amont (champ « digest » de l'API des releases) ET recalculée sur l'archive
# téléchargée.
#
# ENSURE_SHELLCHECK_URL remplace l'adresse de l'archive pour les tests seulement : l'empreinte, elle,
# n'est jamais remplaçable, si bien qu'aucune archive non épinglée ne peut passer.
#
# POSIX sh : il tourne avant toute vérification de l'environnement du job. « set -e » en plus de
# l'aîné : une commande sans « || die » (un nettoyage, par exemple) ne peut pas échouer en silence.

set -eu

SHELLCHECK_VERSION=0.11.0
SHELLCHECK_SHA256=b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6
SHELLCHECK_URL=${ENSURE_SHELLCHECK_URL:-"https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.gz"}

die() { printf '::error::ensure-shellcheck : %s\n' "$*" >&2; exit 2; }

[ $# -eq 0 ] || die "aucun argument attendu."

# version d'un binaire shellcheck, lue sur sa ligne « version: X.Y.Z » ; vide si illisible
version_of() { "$1" --version 2>/dev/null | sed -n 's/^version: *//p'; }

if _sc=$(command -v shellcheck 2>/dev/null) && [ -n "$_sc" ]; then
    if [ "$(version_of "$_sc")" = "$SHELLCHECK_VERSION" ]; then
        dirname "$_sc"
        exit 0
    fi
    printf 'ensure-shellcheck : shellcheck présent mais pas en version %s : la version épinglée est téléchargée.\n' \
        "$SHELLCHECK_VERSION" >&2
fi

DEST="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/shellcheck-${SHELLCHECK_VERSION}"

[ "$(uname -m)" = "x86_64" ] || die "architecture $(uname -m) non prévue (archive épinglée : linux.x86_64)."
command -v curl >/dev/null 2>&1 || die "curl introuvable."
command -v sha256sum >/dev/null 2>&1 || die "sha256sum introuvable : empreinte invérifiable, shellcheck refusé."
command -v tar >/dev/null 2>&1 || die "tar introuvable."

mkdir -p "$DEST" || die "dossier $DEST impossible à créer."
_tmp="$DEST/shellcheck.tar.gz.download"
_x="$DEST/extraction"
rm -rf "$_tmp" "$_x" "$DEST/shellcheck"
curl -fsSL --retry 3 -o "$_tmp" "$SHELLCHECK_URL" \
    || { rm -f "$_tmp"; die "téléchargement de shellcheck ${SHELLCHECK_VERSION} impossible."; }
_sum=$(sha256sum "$_tmp" | cut -d' ' -f1)
if [ "$_sum" != "$SHELLCHECK_SHA256" ]; then
    rm -f "$_tmp"
    die "empreinte SHA-256 inattendue pour shellcheck ${SHELLCHECK_VERSION} (attendu $SHELLCHECK_SHA256, obtenu $_sum) : archive refusée."
fi
mkdir -p "$_x" || { rm -f "$_tmp"; die "dossier $_x impossible à créer."; }
tar -xzf "$_tmp" -C "$_x" || { rm -rf "$_tmp" "$_x"; die "archive de shellcheck illisible."; }
rm -f "$_tmp"
_bin="$_x/shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
[ -f "$_bin" ] || { rm -rf "$_x"; die "binaire absent de l'archive (shellcheck-v${SHELLCHECK_VERSION}/shellcheck)."; }
{ chmod 755 "$_bin" && mv "$_bin" "$DEST/shellcheck"; } \
    || { rm -rf "$_x"; die "installation de shellcheck dans $DEST impossible."; }
rm -rf "$_x"
[ "$(version_of "$DEST/shellcheck")" = "$SHELLCHECK_VERSION" ] \
    || { rm -f "$DEST/shellcheck"; die "le binaire shellcheck téléchargé ne s'exécute pas, ou n'est pas en version ${SHELLCHECK_VERSION}."; }
printf '%s\n' "$DEST"
