#!/usr/bin/env bash
# pki-provisoire.sh — CA provisoire MédiSphère et certificat serveur de git01 (M01-E04).
#
# À lancer sur adm01, en utilisateur admin (pas en root) :
#   pki-provisoire.sh ca        crée la CA (refuse d'écraser une CA existante)
#   pki-provisoire.sh git01     crée ou renouvelle la clé et le certificat de git01
#   pki-provisoire.sh racine    installe la racine dans le magasin système de adm01 (sudo)
#
# Choix d'algorithme : ECDSA P-256 pour la CA et le serveur (clés courtes, signatures rapides,
# accepté par tous les clients TLS actuels, dont Git, curl, les navigateurs et GitLab Runner).
# RSA 4096 serait aussi valable : remplacer les deux appels à genpkey (voir cle_ec), et
# ajouter keyEncipherment dans keyUsage de v3_serveur_git01.
#
# La configuration (sujets, extensions, SAN) est dans pki-provisoire.cnf, dans le même dossier.
set -euo pipefail

PKI="${PKI:-$HOME/pki-provisoire}"
CNF="$PKI/pki-provisoire.cnf"
JOURS_CA=730        # 2 ans
JOURS_SERVEUR=397   # plafond CA/Browser Forum pour un certificat serveur

umask 077

cle_ec() { openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$1"; }

preparer() {
  install -d -m 700 "$PKI"
  [[ -f "$CNF" ]] || { echo "Configuration absente : $CNF (copie pki-provisoire.cnf)." >&2; exit 1; }
}

creer_ca() {
  preparer
  if [[ -e "$PKI/ca.key" ]]; then
    echo "Refus : $PKI/ca.key existe déjà. Une nouvelle CA invaliderait tous les certificats émis." >&2
    exit 1
  fi
  cle_ec "$PKI/ca.key"
  openssl req -x509 -new -config "$CNF" -key "$PKI/ca.key" \
    -days "$JOURS_CA" -extensions v3_ca -out "$PKI/ca.crt"
  chmod 644 "$PKI/ca.crt"         # public ; le dossier reste en 700
  openssl x509 -in "$PKI/ca.crt" -noout -subject -enddate -nameopt oneline,-esc_msb
}

creer_git01() {
  preparer
  [[ -f "$PKI/ca.key" ]] || { echo "CA absente : lance d'abord « $0 ca »." >&2; exit 1; }
  # Nouvelle clé à chaque émission : un renouvellement est aussi une rotation de clé.
  cle_ec "$PKI/git01.key"
  openssl req -new -config "$CNF" -section req_git01 -key "$PKI/git01.key" -out "$PKI/git01.csr"
  openssl x509 -req -in "$PKI/git01.csr" -CA "$PKI/ca.crt" -CAkey "$PKI/ca.key" -CAcreateserial \
    -days "$JOURS_SERVEUR" -sha256 -extfile "$CNF" -extensions v3_serveur_git01 -out "$PKI/git01.crt"
  # Chaîne servie par NGINX : certificat serveur, puis certificat de la CA
  cat "$PKI/git01.crt" "$PKI/ca.crt" > "$PKI/git01-chaine.crt"
  chmod 644 "$PKI/git01.crt" "$PKI/git01-chaine.crt"
  openssl verify -CAfile "$PKI/ca.crt" "$PKI/git01.crt"
  openssl x509 -in "$PKI/git01.crt" -noout -subject -enddate -ext subjectAltName -nameopt oneline,-esc_msb
}

installer_racine() {
  sudo install -m 644 "$PKI/ca.crt" /usr/local/share/ca-certificates/medisphere-provisoire.crt
  sudo update-ca-certificates
  ls -l /etc/ssl/certs/medisphere-provisoire.pem
}

case "${1:-}" in
  ca)     creer_ca ;;
  git01)  creer_git01 ;;
  racine) installer_racine ;;
  *) echo "Usage : $0 ca|git01|racine" >&2; exit 2 ;;
esac
