#!/usr/bin/env bash
# outils/ca-partenaires.sh — autorité « MédiSphère Partenaires » et certificats clients des centres
# partenaires (M15-E33, SEC-1633). À lancer sur adm01 uniquement. step CLI 0.31 (M06).
#
#   outils/ca-partenaires.sh init                 crée l'autorité (une fois)
#   outils/ca-partenaires.sh emettre <CENTRE>     émet un certificat client de 30 jours pour <CENTRE>
#
# Fichiers (~/.config/workbook/, 600, jamais dans un dépôt) :
#   ca-partenaires.key   clé privée de l'autorité, chiffrée par ca-partenaires.pass (copie en Vault critique)
#   ca-partenaires.pass  phrase de passe de la clé
#   partenaire-<CENTRE>.crt / .key   certificat et clé du centre (à remettre par un canal chiffré, puis
#                                     à supprimer d'adm01 ; le centre de test reste pour les vérifications)
# Le certificat PUBLIC de l'autorité est versionné : composants/reseau/partenaires/ca-partenaires.crt.
#
# Pas de liste de révocation dans ce montage : un accès se retire en N'ÉMETTANT PLUS le certificat suivant ;
# d'où une durée courte (30 jours) et un renouvellement mensuel. Retrait d'urgence : rotation de
# l'autorité (init sur un nouveau nom, nouvelle ConfigMap, réémission pour tous les autres centres).
set -euo pipefail
umask 077

dir="$HOME/.config/workbook"
depot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ca_pub="$depot/composants/reseau/partenaires/ca-partenaires.crt"
ca_key="$dir/ca-partenaires.key"
ca_pass="$dir/ca-partenaires.pass"

modele="$(mktemp)"
trap 'rm -f "$modele"' EXIT
# Modèle step : usage CLIENT seulement (le modèle « leaf » par défaut ajoute serverAuth).
cat >"$modele" <<'FIN'
{
  "subject": {"commonName": {{ toJson .Subject.CommonName }}, "organization": ["MédiSphère partenaires"]},
  "keyUsage": ["digitalSignature"],
  "extKeyUsage": ["clientAuth"]
}
FIN

case "${1:-}" in
  init)
    [[ ! -e "$ca_key" ]] || { echo "l'autorité existe déjà : $ca_key" >&2; exit 1; }
    [[ -s "$ca_pass" ]] || { echo "phrase de passe absente : $ca_pass (crée-la, 600, et copie-la en Vault)" >&2; exit 1; }
    step certificate create "MédiSphère Partenaires" "$ca_pub" "$ca_key" \
      --profile root-ca --kty EC --curve P-256 --not-after 43800h \
      --password-file "$ca_pass"
    chmod 644 "$ca_pub"
    echo "Autorité créée. Versionne $ca_pub ; copie $ca_key et $ca_pass en Vault critique."
    ;;
  emettre)
    centre="${2:?nom du centre attendu, ex. centre-test-01}"
    [[ "$centre" =~ ^[a-z0-9-]{3,40}$ ]] || { echo "nom de centre invalide : $centre" >&2; exit 2; }
    step certificate create "$centre" "$dir/partenaire-$centre.crt" "$dir/partenaire-$centre.key" \
      --template "$modele" --ca "$ca_pub" --ca-key "$ca_key" --ca-password-file "$ca_pass" \
      --kty EC --curve P-256 --not-after 720h --no-password --insecure
    chmod 600 "$dir/partenaire-$centre.crt" "$dir/partenaire-$centre.key"
    step certificate inspect --short "$dir/partenaire-$centre.crt"
    ;;
  *)
    sed -n '2,9p' "$0" >&2
    exit 2
    ;;
esac
