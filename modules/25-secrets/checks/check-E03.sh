# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E03.sh — M25-E03 : Installer et initialiser OpenBao sur vault01
# À lancer depuis adm01. Lecture seule : NetBox, DNS, chaîne TLS (racine MédiSphère), état du coffre
# sans jeton (sys/seal-status, sys/health), SSH en consultation sur vault01 (unité, droits,
# configuration), CLI d'adm01, fichiers de plateforme/ansible et plateforme/medisphere (GitLab).
# Aucune part ni aucun jeton n'est lu : seule la FORME du fichier chiffré est contrôlée.

# shellcheck source=_m25-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-decouverte.sh"

title "M25-E03 — Installer et initialiser OpenBao sur vault01"
require_cmd jq curl dig openssl

_m25d_e03_fqdn="vault01.$_M25D_DOMAINE"

# _m25d_e03_nb_cles TEXTE — nombre de clés publiques age distinctes dans le texte.
_m25d_e03_nb_cles() { grep -Eo 'age1[0-9a-z]{58}' <<<"$1" | sort -u | wc -l; }

# _m25d_e03_cles_privees — nombre de fichiers contenant une clé privée age EN CLAIR.
_m25d_e03_cles_privees() {
  grep -rlsF "AGE-SECRET-KEY-" "$HOME/m25" "$HOME/.config/workbook" 2>/dev/null | wc -l
}

# --- 1. La machine et son nom ----------------------------------------------------------------------
check_cmd "NetBox : VM vault01 déclarée (étiquettes socle et role-coffre)" _m25d_json \
  "$(netbox_api "virtualization/virtual-machines/?name=vault01" 2>/dev/null || true)" \
  '.count == 1 and ([.results[0].tags[].slug] | index("socle") != null and index("role-coffre") != null)'
check_dns "A vault01.par1.medisphere.internal → 10.10.20.21" "$_m25d_e03_fqdn" A '^10\.10\.20\.21$'
check_dns "PTR 10.10.20.21 → vault01" 21.20.10.10.in-addr.arpa PTR '^vault01\.par1\.medisphere\.internal\.$'
# Au palier 1 le nom du service vise vault01 ; après M25-E24, la VIP 10.10.20.200.
check_dns "openbao.par1.medisphere.internal → vault01 (ou la VIP 10.10.20.200 après M25-E24)" \
  "openbao.$_M25D_DOMAINE" A '^10\.10\.20\.(21|200)$'

# --- 2. TLS et état du coffre -----------------------------------------------------------------------
check_cmd "vault01:8200 : certificat vérifié jusqu'à la racine MédiSphère pour le nom vault01" \
  _m25d_chaine_tls "$_m25d_e03_fqdn" 8200
check_cmd "vault01:8200 : le même certificat vaut pour le nom du service openbao.par1.medisphere.internal" \
  _m25d_chaine_tls "$_m25d_e03_fqdn" 8200 "openbao.$_M25D_DOMAINE"
check_output "vault01:8200 : aucune réponse en HTTP clair (TLS seul)" '^400$' \
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "http://$_m25d_e03_fqdn:8200/v1/sys/seal-status"

_m25d_e03_etat="$(_m25d_etat)"
if [[ -z "$_m25d_e03_etat" ]]; then
  _ko "OpenBao ne répond pas sur $_M25D_URL/v1/sys/seal-status (service arrêté, flux, nom ?)"
else
  check_cmd "OpenBao 2.6 ou ultérieur, stockage Raft intégré" _m25d_json "$_m25d_e03_etat" \
    '(.version | test("^2\\.([6-9]|[1-9][0-9])\\.")) and .storage_type == "raft"'
  check_cmd "Coffre initialisé" _m25d_json "$_m25d_e03_etat" '.initialized == true'
  check_cmd "Parts de la clé : 5, seuil 3 (Shamir ; clés de récupération après M25-E25)" _m25d_json "$_m25d_e03_etat" \
    '.n == 5 and .t == 3 and (.type == "shamir" or .type == "transit")'
  check_cmd "Coffre descellé (le service répond aux clients)" _m25d_json "$_m25d_e03_etat" '.sealed == false'
fi

# --- 3. Le nœud -------------------------------------------------------------------------------------------
check_ssh "vault01 : openbao.service actif, lancé au démarrage, sous l'utilisateur openbao" "$_M25D_VAULT01" \
  "systemctl is-active --quiet openbao.service && systemctl is-enabled --quiet openbao.service && [ \"\$(systemctl show -p User --value openbao.service)\" = openbao ]"
check_ssh_output "vault01 : paquet openbao installé en version 2.6 ou ultérieure (paquet amont)" "$_M25D_VAULT01" \
  '^2\.([6-9]|[1-9][0-9])\.' "dpkg-query -W -f '\${Version}' openbao"
check_ssh_output "vault01 : données Raft dans /var/lib/openbao, réservées à openbao (700)" "$_M25D_VAULT01" \
  '^700 openbao openbao$' "stat -c '%a %U %G' /var/lib/openbao"
check_ssh_output "vault01 : openbao.hcl lisible par root et le groupe openbao seulement (640)" "$_M25D_VAULT01" \
  '^640 root openbao$' "stat -c '%a %U %G' /etc/openbao/openbao.hcl"
_m25d_e03_hcl="$(_m25d_ssh "$_M25D_VAULT01" "sudo -n cat /etc/openbao/openbao.hcl")"
if [[ -z "$_m25d_e03_hcl" ]]; then
  _ko "vault01 : /etc/openbao/openbao.hcl illisible (sudo -n cat) : configuration non contrôlée"
else
  check_cmd "openbao.hcl : stockage raft dans /var/lib/openbao, node_id vault01" _m25d_contient \
    "$(tr -d '[:space:]' <<<"$_m25d_e03_hcl")" 'storage"raft"\{path="/var/lib/openbao"node_id="vault01"'
  check_cmd "openbao.hcl : api_addr et cluster_addr au nom de vault01" _m25d_contient "$_m25d_e03_hcl" \
    'cluster_addr *= *"https://vault01\.par1\.medisphere\.internal:8201"'
  check_cmd "openbao.hcl : ni tls_disable, ni disable_mlock (clé retirée d'OpenBao), ni stockage file" \
    _m25d_aucun '^[[:space:]]*(tls_disable|disable_mlock)|storage +"file"' "$_m25d_e03_hcl"
fi
check_ssh_output "vault01 : pas de vidage mémoire possible (LimitCORE=0)" "$_M25D_VAULT01" '^0$' \
  "systemctl show -p LimitCORE --value openbao.service"
check_ssh_output "vault01 : pas de swap pour le service (MemorySwapMax=0)" "$_M25D_VAULT01" '^0$' \
  "systemctl show -p MemorySwapMax --value openbao.service"
check_ssh "vault01 : renouvellement automatique du certificat (cert-renewer@openbao.timer actif)" "$_M25D_VAULT01" \
  "systemctl is-active --quiet cert-renewer@openbao.timer"
check_ssh "vault01 : le renouvellement RECHARGE OpenBao (reload, jamais restart)" "$_M25D_VAULT01" \
  "systemctl cat cert-renewer@openbao.service | grep -q 'reload openbao' && ! systemctl cat cert-renewer@openbao.service | grep -Eq 'restart openbao|try-reload-or-restart'"

# --- 4. Le poste d'administration et les traces de l'initialisation ------------------------------------------
check_output "adm01 : CLI bao 2.6 ou ultérieure" '^OpenBao v2\.([6-9]|[1-9][0-9])\.' bao version
check_output "adm01 : BAO_ADDR vers le nom du service dans ~/.bashrc" \
  'BAO_ADDR=https://openbao\.par1\.medisphere\.internal:8200' cat "$HOME/.bashrc"
_m25d_e03_init="$(_m25d_contenu_main plateforme/ansible secrets/openbao-init.yml)"
check_cmd "plateforme/ansible : secrets/openbao-init.yml chiffré par Ansible Vault (identité critique)" \
  _m25d_contient "$(head -n 1 <<<"$_m25d_e03_init")" '^[$]ANSIBLE_VAULT;1\.2;AES256;critique$'
check_cmd "plateforme/ansible : aucune part ni jeton en clair dans openbao-init.yml" \
  _m25d_aucun 'unseal_keys|root_token|BEGIN AGE|"part"' "$_m25d_e03_init"
check_output "plateforme/ansible : pki/openbao-depositaires.txt liste 5 clés publiques age distinctes" '^5$' \
  _m25d_e03_nb_cles "$(_m25d_contenu_main plateforme/ansible pki/openbao-depositaires.txt)"
check_cmd "plateforme/medisphere : docs/securite/secrets/garde-des-parts.md (décision et procès-verbal)" \
  _m25d_contient "$(_m25d_contenu_main plateforme/medisphere docs/securite/secrets/garde-des-parts.md)" '[Dd]épositaire'
# Les clés privées simulées ont quitté adm01 (seule une clé chiffrée par phrase de passe peut rester).
check_output "adm01 : aucune clé privée age en clair dans ~/m25 ni ~/.config/workbook" '^0$' _m25d_e03_cles_privees
