#!/bin/sh
# Fournit jq à une étape de CI, et affiche le DOSSIER où il se trouve (à mettre en tête de PATH).
# Repris de scripts/ci-ensure-jq.sh, en phase B de `calculette#outillage-14` (procedures/secrets.md,
# « Citer un projet »), sans changement de comportement.
#
# ⚠️ Le runner partagé exécute les jobs en mode hôte, dans un conteneur sans jq ni apt-get (constaté le
# 03/10/2026). On n'installe RIEN sur le runner : on télécharge un binaire statique ÉPINGLÉ (version +
# SHA-256) dans un dossier temporaire du job, et on refuse tout fichier dont l'empreinte diffère.
#
# Usage :
#   JQ_DIR=$(sh ci/ensure-jq.sh) && PATH="$JQ_DIR:$PATH"
#   sh ci/ensure-jq.sh --download <dossier>   télécharge même si jq est déjà présent
#
# Codes : 0 jq disponible (dossier affiché) ; 2 impossible de le fournir (rien n'est vérifié
# ensuite — l'appelant DOIT échouer, jamais continuer sans jq).
#
# Pour monter de version : changer JQ_VERSION et JQ_SHA256 ENSEMBLE, l'empreinte étant relevée
# dans le sha256sum.txt de la release amont ET recalculée sur le binaire téléchargé.
#
# POSIX sh : il tourne avant toute vérification de l'environnement du job.

set -u

JQ_VERSION=1.8.1
JQ_SHA256=020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d
JQ_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64"

die() { printf '::error::ensure-jq : %s\n' "$*" >&2; exit 2; }

DEST=""
if [ "${1:-}" = "--download" ]; then
    DEST=${2:-}
    [ -n "$DEST" ] || die "--download exige un dossier."
elif _jq=$(command -v jq 2>/dev/null) && [ -n "$_jq" ]; then
    dirname "$_jq"
    exit 0
else
    DEST="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/jq-${JQ_VERSION}"
fi

[ "$(uname -m)" = "x86_64" ] || die "architecture $(uname -m) non prévue (binaire épinglé : linux-amd64)."
command -v curl >/dev/null 2>&1 || die "curl introuvable."
command -v sha256sum >/dev/null 2>&1 || die "sha256sum introuvable : empreinte invérifiable, jq refusé."

mkdir -p "$DEST" || die "dossier $DEST impossible à créer."
_tmp="$DEST/jq.download"
rm -f "$_tmp" "$DEST/jq"
curl -fsSL --retry 3 -o "$_tmp" "$JQ_URL" || { rm -f "$_tmp"; die "téléchargement de jq ${JQ_VERSION} impossible."; }
_sum=$(sha256sum "$_tmp" | cut -d' ' -f1)
if [ "$_sum" != "$JQ_SHA256" ]; then
    rm -f "$_tmp"
    die "empreinte SHA-256 inattendue pour jq ${JQ_VERSION} (attendu $JQ_SHA256, obtenu $_sum) : binaire refusé."
fi
{ chmod 755 "$_tmp" && mv "$_tmp" "$DEST/jq"; } || die "installation de jq dans $DEST impossible."
"$DEST/jq" --version >/dev/null 2>&1 || die "le binaire jq téléchargé ne s'exécute pas."
printf '%s\n' "$DEST"
