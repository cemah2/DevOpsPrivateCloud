# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S05.sh — F5-S05 « La confiance et les secrets hors de PAR1 » : certificat de l'autorité de PAR2
# publié et valide, procès-verbal de cérémonie, bao-par2 en veille, copie 3501 détruite, kms01 de PAR1
# intact, enveloppe sans secret, RB-355 et compte rendu de répétition. Lecture seule (GitLab ou miroir,
# openssl local, SSH root vers hp01 et pve01 en consultation, sys/seal-status de kms01 sans jeton).

# shellcheck source=_f5-par2.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-par2.sh"

title "F5-S05 — La confiance et les secrets hors de PAR1"
require_cmd openssl curl jq ssh

_f5_s05_racine="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
_f5_s05_crt="$(_f5p_fichier "$_f5p_projet_doc" "$_f5p_doc_dir/pki/medisphere-par2-intermediate-ca.crt" 2>/dev/null || true)"

# --- Autorité de PAR2 ------------------------------------------------------------------------------------
check_cmd "pki/medisphere-par2-intermediate-ca.crt publié sur main (certificat PEM)" \
  grep -q -- '-----BEGIN CERTIFICATE-----' <<<"$_f5_s05_crt"
_f5_s05_cn() { openssl x509 -noout -subject -nameopt utf8,sep_comma_plus <<<"$_f5_s05_crt" 2>/dev/null | grep -q 'CN=MédiSphère PAR2 Intermediate CA'; }
check_cmd "CN « MédiSphère PAR2 Intermediate CA »" _f5_s05_cn
if [[ -r "$_f5_s05_racine" ]]; then
  _f5_s05_signe() { openssl verify -CAfile "$_f5_s05_racine" <(printf '%s\n' "$_f5_s05_crt") >/dev/null 2>&1; }
  check_cmd "signé par « MédiSphère Root CA » ($_f5_s05_racine)" _f5_s05_signe
else
  skip "signature par la racine" "racine illisible : $_f5_s05_racine (WB_RACINE_PKI)"
fi
_f5_s05_ca() { openssl x509 -noout -ext basicConstraints <<<"$_f5_s05_crt" 2>/dev/null | grep -Eq 'CA:TRUE, *pathlen:0'; }
check_cmd "autorité de certification avec pathlen 0 (signe des certificats finaux seulement)" _f5_s05_ca
_f5_s05_valide() { openssl x509 -noout -checkend 0 <<<"$_f5_s05_crt" >/dev/null 2>&1; }
check_cmd "valide aujourd'hui (non expiré)" _f5_s05_valide
_f5_s05_pv() {
  local pv
  pv="$(_f5p_fichier "$_f5p_projet_doc" docs/securite/identite/ceremonie-ca.md 2>/dev/null)" || return 1
  grep -Eqi 'PAR2' <<<"$pv" && grep -Eq '([0-9A-Fa-f]{2}:){15,}|[0-9a-f]{64}' <<<"$pv" && _f5p_sans_secret "$pv"
}
check_cmd "procès-verbal docs/securite/identite/ceremonie-ca.md : cérémonie PAR2 avec empreinte, sans secret" _f5_s05_pv

# --- Coffre de secours ------------------------------------------------------------------------------------
check_output "bao-par2 (1055) existe et est ARRÊTÉ (veille)" '^stopped$' _f5p_vm_etat 1055
check_output "bao-par2 (1055) dans le pool par2" '^par2$' _f5p_vm_pool 1055
check_output "la copie de kms01 (3501) n'existe plus après la répétition" '^absente$' _f5p_vm_etat 3501

# --- kms01 de PAR1 intact ---------------------------------------------------------------------------------
if remote "$WB_PVE_HOST" true >/dev/null 2>&1; then
  check_output "pve01 : kms01 (1024) en marche" 'status: running' remote "$WB_PVE_HOST" 'qm status 1024'
else
  skip "kms01 (1024) en marche sur pve01" "pve01 injoignable depuis $(hostname -s)"
fi
_f5_s05_descelle() {
  local o=()
  [[ -r "$_f5_s05_racine" ]] && o=(--cacert "$_f5_s05_racine")
  curl -sf --max-time "$WB_TIMEOUT" "${o[@]}" "$_f5p_kms01_url/v1/sys/seal-status" | jq -e '.sealed == false' >/dev/null
}
check_cmd "kms01 de PAR1 répond « descellé » ($_f5p_kms01_url)" _f5_s05_descelle

# --- Enveloppe, runbook, répétition -----------------------------------------------------------------------
_f5_s05_env="$(_f5p_fichier "$_f5p_projet_doc" "$_f5p_doc_dir/enveloppe.md" 2>/dev/null || true)"
check_cmd "enveloppe.md publié" test -n "$_f5_s05_env"
_f5_s05_contenu() {
  local m
  for m in 'shamir|kms01' 'PBS' 'kopia' 'bris de glace|root@pam' 'admin\.conf' 'gardien|d(é|e)tenteur' 'v(é|e)rifi'; do
    grep -Eqi -- "$m" <<<"$_f5_s05_env" || return 1
  done
}
check_cmd "enveloppe.md : parts Shamir, clé PBS, phrase Kopia, bris de glace, admin.conf, gardiens, vérification" _f5_s05_contenu
check_cmd "enveloppe.md : aucun secret reconnaissable (clé privée, clé age, jeton)" _f5p_sans_secret "$_f5_s05_env"
check_cmd "RB-355 : restauration de kms01 en 3501 / 10.20.20.24 dans un bac à sable, durées" \
  _f5p_doc runbooks/RB-355-coffre-de-secours.md '3501' '10\.20\.20\.24' 'bac (à|a) sable|isol' 'dur(é|e)e|min'
check_cmd "mesures/repetition-coffre-<AAAA-MM-JJ>.md : durées et RPO du coffre mesurés" \
  _f5p_doc_motif mesures '^repetition-coffre-[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$' 'RPO' '[0-9]+ ?(s|min)\b'
