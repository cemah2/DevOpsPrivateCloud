#!/usr/bin/env bash
# preparer-pve-pxe.sh — prépare l'installateur de Proxmox VE pour un démarrage PXE (M11-E14).
#
# Usage : outils/preparer-pve-pxe.sh <iso> <fichier-jeton> <dossier-de-sortie>
#   <iso>           ISO officielle déposée et vérifiée (somme SHA-256 et signature, comme au M09)
#   <fichier-jeton> fichier 600 contenant « <nom>:<secret> » (extrait du Vault, supprimé ensuite)
#
# ⚠️ Exception documentée au registre des secrets : prepare-iso ne lit le jeton que depuis sa
# ligne de commande (visible dans /proc pendant l'exécution) et l'écrit EN CLAIR dans l'initrd.
# On lance donc l'outil sur adm01 (mono-utilisateur), le moins longtemps possible ; le jeton ne
# donne accès qu'aux fichiers de réponse (empreintes de mot de passe, pas de mots de passe).
#
# L'empreinte du certificat de pxe01 change à CHAQUE renouvellement ACME (30 jours) : préparer
# l'initrd juste avant l'installation, jamais le garder d'un mois sur l'autre.
set -euo pipefail

[[ $# -eq 3 ]] || { echo "Usage : $0 <iso> <fichier-jeton> <dossier-de-sortie>" >&2; exit 2; }
iso="$1" jeton_f="$2" sortie="$3"
fqdn=pxe01.par1.medisphere.internal
url="https://$fqdn/pve/reponse"

[[ -r "$iso" ]] || { echo "ISO illisible : $iso" >&2; exit 1; }
[[ "$(stat -c %a "$jeton_f")" == 600 ]] || { echo "$jeton_f doit être en 600" >&2; exit 1; }
command -v proxmox-auto-install-assistant >/dev/null || { echo "proxmox-auto-install-assistant absent" >&2; exit 1; }

# Empreinte SHA-256 du certificat PRÉSENTÉ par pxe01, après vérification de la chaîne par le
# magasin système d'adm01 (racine MédiSphère) : on n'épingle pas un certificat non vérifié.
pem="$(openssl s_client -connect "$fqdn:443" -servername "$fqdn" -verify_return_error </dev/null 2>/dev/null \
  | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p')"
[[ -n "$pem" ]] || { echo "Certificat de $fqdn non vérifiable" >&2; exit 1; }
empreinte="$(openssl x509 -noout -fingerprint -sha256 <<<"$pem" | cut -d= -f2)"
fin="$(openssl x509 -noout -enddate <<<"$pem" | cut -d= -f2)"
echo "Certificat de $fqdn : $empreinte (valide jusqu'au $fin)"

mkdir -p "$sortie"
proxmox-auto-install-assistant prepare-iso "$iso" \
  --fetch-from http \
  --url "$url" \
  --cert-fingerprint "$empreinte" \
  --answer-auth-token "$(<"$jeton_f")" \
  --pxe-loader ipxe \
  --output "$sortie"

echo "Fichiers produits :"
(cd "$sortie" && ls -l && sha256sum -- * 2>/dev/null)
echo "Recopie les arguments de la ligne « kernel » du script iPXE produit dans pve_noyau_arguments."
