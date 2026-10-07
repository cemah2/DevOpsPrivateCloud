#!/usr/bin/env bash
# emettre-s3-01.sh — clé et certificat de la passerelle S3 de s3-01, signés par la CA
# provisoire (M05-E10). Même procédure que git01 (pki-provisoire.sh, M01-E04).
# À lancer sur adm01 en admin, APRÈS avoir ajouté pki-provisoire-s3-01.cnf à pki-provisoire.cnf.
# Le certificat et la clé partent ensuite dans le coffre Ansible (host_vars/s3-01/vault.yml) :
# ils ne sont jamais copiés à la main sur s3-01.
set -euo pipefail

PKI="${PKI:-$HOME/pki-provisoire}"
CNF="$PKI/pki-provisoire.cnf"
JOURS=397
umask 077

[[ -f "$PKI/ca.key" ]] || { echo "CA provisoire absente : $PKI/ca.key" >&2; exit 1; }
grep -q '^\[req_s3_01\]' "$CNF" || { echo "Sections s3-01 absentes de $CNF" >&2; exit 1; }

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$PKI/s3-01.key"
openssl req -new -config "$CNF" -section req_s3_01 -key "$PKI/s3-01.key" -out "$PKI/s3-01.csr"
openssl x509 -req -in "$PKI/s3-01.csr" -CA "$PKI/ca.crt" -CAkey "$PKI/ca.key" -CAcreateserial \
  -days "$JOURS" -sha256 -extfile "$CNF" -extensions v3_serveur_s3_01 -out "$PKI/s3-01.crt"
chmod 644 "$PKI/s3-01.crt"

openssl verify -CAfile "$PKI/ca.crt" "$PKI/s3-01.crt"
openssl x509 -in "$PKI/s3-01.crt" -noout -subject -enddate -ext subjectAltName -nameopt oneline,-esc_msb
