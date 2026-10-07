#!/usr/bin/env bash
# installer-packer-runner01.sh — prépare runner01 pour construire les images (M03-E15).
# À lancer en root SUR runner01 (copié depuis adm01 : scp puis sudo). Idempotent.
#
#   1. dépôt APT HashiCorp (clé vérifiée par son EMPREINTE, comme sur adm01 en M03-E02) ;
#   2. Packer 1.16 ;
#   3. autorité de pve01 approuvée par le magasin système (le plugin vérifie le TLS) ;
#   4. contrôles : version, plugin installable par gitlab-runner, API de pve01 joignable.
#
# Variables :
#   EMPREINTE_HASHICORP  empreinte attendue de la clé de signature (OBLIGATOIRE : relève-la sur la
#                        page officielle « PGP public keys » de HashiCorp, pas dans ce fichier)
#   CA_PVE01             certificat de l'autorité de pve01 (défaut /tmp/pve01-root-ca.crt,
#                        copié depuis adm01 : ~/.config/workbook/pve-root-ca.pem, l'ancre
#                        conforme de M02-E08)
#   IP_PVE01             adresse de pve01 telle qu'elle figure dans son certificat (<IP-PVE01>)
# Codes retour : 0 · 1 erreur · 2 usage
set -euo pipefail

: "${EMPREINTE_HASHICORP:?empreinte de la clé HashiCorp attendue, voir en-tête}"
: "${IP_PVE01:?adresse de pve01 attendue (<IP-PVE01>)}"
CA_PVE01="${CA_PVE01:-/tmp/pve01-root-ca.crt}"
[[ $EUID -eq 0 ]] || { echo "à lancer en root" >&2; exit 2; }
[[ -s "$CA_PVE01" ]] || { echo "certificat de l'autorité de pve01 absent : $CA_PVE01" >&2; exit 2; }

# --- 1. Dépôt HashiCorp ---------------------------------------------------------------------
t="$(mktemp -d)"
trap 'rm -rf -- "$t"' EXIT
curl -fsSL -o "$t/hashicorp.asc" https://apt.releases.hashicorp.com/gpg
trouvee="$(gpg --show-keys --with-colons "$t/hashicorp.asc" | awk -F: '$1 == "fpr" {print $10; exit}')"
attendue="$(tr -d ' ' <<<"$EMPREINTE_HASHICORP")"
if [[ "$trouvee" != "$attendue" ]]; then
  echo "empreinte de la clé HashiCorp inattendue : $trouvee (attendue $attendue) — ARRÊT" >&2
  exit 1
fi
gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg "$t/hashicorp.asc"
cat >/etc/apt/sources.list.d/hashicorp.sources <<'SOURCES'
Types: deb
URIs: https://apt.releases.hashicorp.com
Suites: trixie
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/hashicorp-archive-keyring.gpg
SOURCES

# --- 2. Packer --------------------------------------------------------------------------------
apt-get update -q
apt-get install -y -q packer
packer version | grep -q '^Packer v1\.16\.' || { echo "Packer 1.16 attendu" >&2; exit 1; }

# --- 3. Autorité de pve01 dans le magasin système ----------------------------------------------
openssl x509 -in "$CA_PVE01" -noout -subject >/dev/null
install -m 644 "$CA_PVE01" /usr/local/share/ca-certificates/pve01-root-ca.crt
update-ca-certificates

# --- 4. Contrôles -----------------------------------------------------------------------------
# TLS vérifié (sans -k) : un 401 sans jeton prouve que la chaîne de confiance est bonne.
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$IP_PVE01:8006/api2/json/version")" || true
[[ "$code" == 401 ]] || { echo "API de pve01 : HTTP $code (attendu 401 sans jeton) — flux 8006 ou TLS ?" >&2; exit 1; }
# Le plugin s'installe dans le HOME de gitlab-runner au premier « packer init » d'un job.
sudo -u gitlab-runner -H packer version >/dev/null
echo "runner01 prêt : $(packer version | head -n 1), autorité de pve01 approuvée, API joignable"
