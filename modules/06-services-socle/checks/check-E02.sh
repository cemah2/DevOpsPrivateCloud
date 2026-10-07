# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E02.sh — M06-E02 : Déployer ca01 et initialiser step-ca
# À lancer depuis adm01. Lecture seule : qm config sur pve01, fichiers de ~/pki-racine et des
# clones de travail, état de ca01 en SSH, points publics de l'API step-ca (/health, /roots.pem,
# /provisioners, ACME, /ssh/roots), API GitLab en GET.

# shellcheck source=_m06-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-decouverte.sh"

title "M06-E02 — Déployer ca01 et initialiser step-ca"
require_cmd jq curl openssl dig

_m06d_e02_url="https://ca01.par1.medisphere.internal"
_m06d_e02_racine="$(_m06d_racine)"

# --- 1. La VM, créée par OpenTofu ----------------------------------------------------------
_m06d_e02_conf="$(_m06d_qm 1003)"
check_cmd "VM 1003 nommée ca01" _m06d_qm_a "$_m06d_e02_conf" name 'ca01$'
check_cmd "ca01 : étiquettes socle et role-pki" _m06d_etiquettes "$_m06d_e02_conf" socle role-pki
check_cmd "ca01 : membre du pool lab" _m06d_dans_pool 1003
check_cmd "ca01 : 1 vCPU, 1024 Mo" bash -c 'grep -q "^cores: 1$" <<<"$1" && grep -q "^memory: 1024$" <<<"$1"' _ "$_m06d_e02_conf"
check_cmd "ca01 : sur vinfra en 10.10.20.11/24" bash -c 'grep -Eq "^net0: .*bridge=vinfra" <<<"$1" && grep -q "ip=10.10.20.11/24" <<<"$1"' _ "$_m06d_e02_conf"
check_cmd "ca01 : démarrage automatique et protection contre la suppression" \
  bash -c 'grep -q "^onboot: 1$" <<<"$1" && grep -q "^protection: 1$" <<<"$1"' _ "$_m06d_e02_conf"
check_cmd "ca01 : déclarée dans l'état socle de plateforme/infra (vm_id = 1003)" _m06d_declaree_iac 1003

# --- 2. Nom ---------------------------------------------------------------------------------
check_dns "DNS : ca01.par1.medisphere.internal → 10.10.20.11" ca01.par1.medisphere.internal A '^10\.10\.20\.11$' "$_M06D_DNS"
check_dns "DNS : 10.10.20.11 → ca01.par1.medisphere.internal" 11.20.10.10.in-addr.arpa PTR '^ca01\.par1\.medisphere\.internal\.$' "$_M06D_DNS"

# --- 3. La racine, hors ligne -----------------------------------------------------------------
check_cmd "adm01 : pki-racine existe en 700" bash -c '[[ "$(stat -c %a "$1" 2>/dev/null)" == 700 ]]' _ "$_M06D_PKI_RACINE"
check_cmd "adm01 : pki-racine : une clé de racine CHIFFRÉE, en 600" \
  bash -c 'for f in "$1"/*key*; do [[ -f "$f" ]] || continue; grep -q ENCRYPTED "$f" && [[ "$(stat -c %a "$f")" == 600 ]] && exit 0; done; exit 1' _ "$_M06D_PKI_RACINE"
check_cmd "adm01 : pki-racine : au moins une archive chiffrée (gpg)" \
  bash -c 'compgen -G "$1/archives/*.gpg" >/dev/null' _ "$_M06D_PKI_RACINE"
check_output "Racine publique du dépôt Ansible (pki/) : sujet « MédiSphère Root CA »" 'CN ?= ?MédiSphère Root CA' \
  openssl x509 -in "$_m06d_e02_racine" -noout -subject -nameopt utf8,sep_comma_plus_space
check_cmd "Racine : auto-signée et autorité de certification (CA:TRUE)" \
  bash -c 'openssl verify -no-CApath -no-CAstore -CAfile "$1" "$1" >/dev/null 2>&1 && openssl x509 -in "$1" -noout -ext basicConstraints | grep -q "CA:TRUE"' _ "$_m06d_e02_racine"
check_cmd "Racine : encore valable dans 5 ans" openssl x509 -in "$_m06d_e02_racine" -noout -checkend $((5 * 365 * 86400))
_m06d_e02_inter="$_M06D_ANSIBLE/pki/medisphere-intermediate-ca.crt"
check_cmd "Intermédiaire du dépôt : signé par la racine" \
  openssl verify -no-CApath -no-CAstore -CAfile "$_m06d_e02_racine" "$_m06d_e02_inter"
check_output "Intermédiaire : « MédiSphère Intermediate CA », ne peut signer que des certificats finaux (pathlen 0)" \
  'CA:TRUE, pathlen:0' openssl x509 -in "$_m06d_e02_inter" -noout -ext basicConstraints

# --- 4. ca01 -----------------------------------------------------------------------------------
check_ssh "ca01 : service step-ca actif et lancé au démarrage" ca01 \
  'systemctl is-active --quiet step-ca && systemctl is-enabled --quiet step-ca'
check_ssh_output "ca01 : step-ca tourne sous le compte « step »" ca01 '^step$' 'ps -o user= -C step-ca | sort -u'
check_ssh_output "ca01 : step-ca écoute sur le port 443" ca01 ':443[[:space:]]' 'ss -Hltnp "sport = :443"'
check_ssh "ca01 : aucune clé de racine sur la CA en ligne" ca01 \
  '! sudo -n find /etc /root /home /opt /srv /var/tmp /tmp -xdev \( -name "root_ca_key*" -o -name "*root*ca*.key" \) -print -quit 2>/dev/null | grep -q .'
check_ssh_output "ca01 : secrets/ ne contient que les clés en ligne (intermédiaire, CA SSH)" ca01 \
  '^intermediate_ca_key ssh_host_ca_key ssh_user_ca_key $' \
  'sudo -n ls /etc/step-ca/secrets | sort | tr "\n" " "'
check_ssh "ca01 : mot de passe des clés lisible par step seul" ca01 \
  'm=$(sudo -n stat -c %a:%U /etc/step-ca/password.txt) && [[ "$m" =~ ^[46]00:step$ ]]'

# --- 5. Le service, vu depuis adm01 avec la seule racine ---------------------------------------
check_http "API : /health répond, TLS vérifié par la racine MédiSphère seule" "$_m06d_e02_url/health" 200 \
  --cacert "$_m06d_e02_racine" --noproxy '*'
check_cmd "API : la chaîne présentée remonte à la racine (via l'intermédiaire)" \
  _m06d_chaine_ok ca01.par1.medisphere.internal 443
_m06d_e02_roots="$(curl -s --max-time "$WB_TIMEOUT" --noproxy '*' --cacert "$_m06d_e02_racine" "$_m06d_e02_url/roots.pem" 2>/dev/null || true)"
check_cmd "API : /roots.pem publie la racine du dépôt (même empreinte)" \
  bash -c '[[ -n "$1" ]] && [[ "$(openssl x509 -noout -fingerprint -sha256 <<<"$1" 2>/dev/null)" == "$(openssl x509 -in "$2" -noout -fingerprint -sha256)" ]]' \
  _ "$_m06d_e02_roots" "$_m06d_e02_racine"
_m06d_e02_prov="$(curl -s --max-time "$WB_TIMEOUT" --noproxy '*' --cacert "$_m06d_e02_racine" "$_m06d_e02_url/provisioners" 2>/dev/null || true)"
for _m06d_e02_p in "admin:JWK" "acme:ACME" "sshpop:SSHPOP"; do
  check_cmd "Provisioner ${_m06d_e02_p%%:*} (${_m06d_e02_p##*:}) déclaré" \
    jq -e --arg n "${_m06d_e02_p%%:*}" --arg t "${_m06d_e02_p##*:}" \
    '.provisioners | map(select(.name == $n and (.type | ascii_upcase) == $t)) | length == 1' <<<"$_m06d_e02_prov"
done
# Durée maximale ACME (claims du provisioner, sinon claims globales non visibles : refus).
# Forme Go « 720h0m0s » : on ne garde que les heures.
check_cmd "Provisioner acme : certificats de 30 jours (720 h) au plus" \
  jq -e '.provisioners[] | select(.name == "acme") | .claims.maxTLSCertDuration // "" | capture("^(?<h>[0-9]+)h") | .h | tonumber <= 720' \
  <<<"$_m06d_e02_prov"
check_http "ACME : annuaire du provisioner « acme » publié" "$_m06d_e02_url/acme/acme/directory" 200 \
  --cacert "$_m06d_e02_racine" --noproxy '*'
check_cmd "CA SSH : clés publiques d'hôte et d'utilisateur publiées (/ssh/roots)" \
  bash -c 'curl -s --max-time 5 --noproxy "*" --cacert "$2" "$1/ssh/roots" | jq -e "(.hostKey | length) >= 1 and (.userKey | length) >= 1" >/dev/null' \
  _ "$_m06d_e02_url" "$_m06d_e02_racine"

# --- 6. Poste d'administration ------------------------------------------------------------------
check_cmd "adm01 : client step configuré pour ca01, empreinte de la racine du dépôt" \
  bash -c 'd="$HOME/.step/config/defaults.json"; jq -e --arg f "$1" --arg u "https://ca01.par1.medisphere.internal" \
    "(.\"ca-url\" | rtrimstr(\"/\")) == \$u and .fingerprint == \$f" "$d" >/dev/null' _ "$(_m06d_empreinte "$_m06d_e02_racine")"
check_cmd "adm01 : mot de passe du provisioner admin en 600" _m06d_mode "$_M06D_CFG/step-admin.pass" 600

# --- 7. Le code ---------------------------------------------------------------------------------
check_cmd "plateforme/ansible (main) : rôle step_ca" _m06d_fichier_main roles/step_ca/tasks/main.yml
check_cmd "plateforme/ansible (main) : scénario Molecule step_ca" _m06d_fichier_main molecule/step_ca/molecule.yml
_m06d_e02_pki_main() {
  _m06d_fichier_main pki/medisphere-root-ca.crt && _m06d_fichier_main pki/medisphere-intermediate-ca.crt
}
check_cmd "plateforme/ansible (main) : racine et intermédiaire publics dans pki/" _m06d_e02_pki_main
check_cmd "Secrets de la PKI chiffrés sous l'identité « critique »" _m06d_vault_critique inventories/lab/group_vars/role_pki/vault-critique.yml
