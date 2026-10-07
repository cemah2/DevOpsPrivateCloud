#!/usr/bin/env bash
# installer-opentofu.sh — installe OpenTofu 1.13.x depuis le dépôt APT officiel (M05-E02).
# À lancer avec sudo sur adm01 (puis sur runner01, M05-E26). Rejouable.
#
# Ce que fait le script, dans l'ordre :
#   1. télécharge les deux clés publiées par OpenTofu et VÉRIFIE leur empreinte complète
#      (une clé de dépôt peut signer n'importe quel paquet installable sur la machine) ;
#   2. déclare le dépôt avec « signed-by » : ces clés ne valent QUE pour lui ;
#   3. épingle la série 1.13 (préférences APT) : « apt upgrade » apporte les correctifs
#      1.13.x, jamais une 1.14 sans décision (MR qui change aussi required_version) ;
#   4. installe le paquet « tofu ».
#
# Empreintes relevées le 2026-10-07 (à recontrôler sur la documentation officielle :
# https://opentofu.org/docs/intro/install/deb/ et le script d'installation officiel) :
#   E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80  OpenTofu <core@opentofu.org>
#   F4AF70F66EAC4337EEECC97407D3DFCD4C61499F  packagecloud.io/opentofu/tofu (signe le dépôt)
set -euo pipefail

SERIE="${SERIE:-1.13}"
EMPREINTE_OPENTOFU="E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80"
EMPREINTE_DEPOT="F4AF70F66EAC4337EEECC97407D3DFCD4C61499F"
TROUSSEAUX=/etc/apt/keyrings

[[ $EUID -eq 0 ]] || { echo "à lancer en root (sudo)" >&2; exit 1; }
for c in curl gpg; do command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 1; }; done

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

# --- 1. Clés : téléchargement et contrôle d'empreinte -------------------------------------
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/opentofu.gpg -o "$tmp/opentofu.gpg"
curl --proto '=https' --tlsv1.2 -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey -o "$tmp/depot.asc"

# empreinte FICHIER — empreinte de la clé principale (format « fpr » de gpg --with-colons)
empreinte() {
  gpg --show-keys --with-colons --with-fingerprint "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'
}
[[ "$(empreinte "$tmp/opentofu.gpg")" == "$EMPREINTE_OPENTOFU" ]] \
  || { echo "empreinte inattendue pour opentofu.gpg : ARRÊT" >&2; exit 1; }
[[ "$(empreinte "$tmp/depot.asc")" == "$EMPREINTE_DEPOT" ]] \
  || { echo "empreinte inattendue pour la clé du dépôt : ARRÊT" >&2; exit 1; }

install -m 0755 -d "$TROUSSEAUX"
install -m 0644 "$tmp/opentofu.gpg" "$TROUSSEAUX/opentofu.gpg"
gpg --batch --yes --dearmor -o "$tmp/opentofu-repo.gpg" "$tmp/depot.asc"
install -m 0644 "$tmp/opentofu-repo.gpg" "$TROUSSEAUX/opentofu-repo.gpg"

# --- 2. Dépôt (forme documentée par OpenTofu), clés limitées à ce dépôt --------------------
cat >/etc/apt/sources.list.d/opentofu.list <<SOURCES
deb [signed-by=$TROUSSEAUX/opentofu.gpg,$TROUSSEAUX/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
SOURCES
chmod 0644 /etc/apt/sources.list.d/opentofu.list

# --- 3. Épinglage de la série --------------------------------------------------------------
cat >/etc/apt/preferences.d/opentofu <<PREFS
# OpenTofu : série $SERIE seulement (M05-E02). Changer de série = MR dans plateforme/infra
# (required_version) ET mise à jour de ce fichier sur adm01 et runner01.
Package: tofu
Pin: version $SERIE.*
Pin-Priority: 1001
PREFS

# --- 4. Installation ---------------------------------------------------------------------------
apt-get update -q
apt-get install -y -q tofu
tofu version
apt-cache policy tofu
