#!/usr/bin/env bash
# emettre-certificat.sh — certificat serveur émis À LA MAIN par step-ca (provisioner admin, M06-E03).
#
# Solution transitoire : ACME prend le relais en M06-E18. Durée par défaut 90 jours (plafond du
# provisioner admin) : note l'échéance dans l'inventaire et le registre des secrets.
#
#   emettre-certificat.sh NOM IP [DUREE]
#     NOM    nom court de l'hôte du socle (ex. git01) ; le FQDN est NOM.par1.medisphere.internal
#     IP     adresse de l'hôte (ajoutée aux SAN)
#     DUREE  durée (défaut 2160h)
#
# Produit dans ~/m06/certs/ (700) :
#   NOM.crt          certificat serveur suivi de l'intermédiaire (chaîne à servir)
#   NOM.key          clé privée en clair (600) — à déposer sur l'hôte ou dans Vault, puis à SUPPRIMER ici
#
# Prérequis : step-cli ; « step ca bootstrap » déjà fait (~/.step/config/defaults.json pointe
# vers https://ca01.par1.medisphere.internal) ; mot de passe du provisioner dans
# ~/.config/workbook/step-admin.pass (600).
set -euo pipefail

DOMAINE="par1.medisphere.internal"
SORTIE="${SORTIE:-$HOME/m06/certs}"
MDP_PROVISIONER="${MDP_PROVISIONER:-$HOME/.config/workbook/step-admin.pass}"

die() { echo "emettre-certificat : $*" >&2; exit 1; }

[[ $# -ge 2 && $# -le 3 ]] || { echo "Usage : $0 NOM IP [DUREE]" >&2; exit 2; }
nom="$1"; ip="$2"; duree="${3:-2160h}"
[[ "$nom" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || die "nom invalide : $nom"
[[ "$ip" =~ ^10\.(10|20)\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || die "adresse hors du lab : $ip"
[[ -r "$MDP_PROVISIONER" ]] || die "mot de passe du provisioner illisible : $MDP_PROVISIONER"
[[ "$(stat -c %a "$MDP_PROVISIONER")" == "600" ]] || die "$MDP_PROVISIONER doit être en 600"
command -v step >/dev/null || die "step (paquet step-cli) introuvable"

umask 077
install -d -m 700 "$SORTIE"

# step ca certificate : clé neuve à chaque émission (un renouvellement est aussi une rotation),
# certificat suivi de l'intermédiaire (« bundle »), clé non chiffrée (un service la lit au démarrage).
step ca certificate "$nom.$DOMAINE" "$SORTIE/$nom.crt" "$SORTIE/$nom.key" \
  --provisioner admin --provisioner-password-file "$MDP_PROVISIONER" \
  --san "$nom.$DOMAINE" --san "$nom" --san "$ip" \
  --not-after "$duree" --force

chmod 600 "$SORTIE/$nom.key"
chmod 644 "$SORTIE/$nom.crt"

echo
step certificate inspect "$SORTIE/$nom.crt" --short
echo "Certificats dans le fichier : $(grep -c 'BEGIN CERTIFICATE' "$SORTIE/$nom.crt") (serveur + intermédiaire attendus)"
step certificate verify "$SORTIE/$nom.crt" --roots "$(step path)/certs/root_ca.crt" --host "$nom.$DOMAINE"
echo "Échéance : $(step certificate inspect "$SORTIE/$nom.crt" --format json | jq -r '.validity.end')"
echo "Rappel : dépose la clé, puis supprime $SORTIE/$nom.key de adm01."
