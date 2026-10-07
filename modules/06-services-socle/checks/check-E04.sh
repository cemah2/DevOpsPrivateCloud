# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E04.sh — M06-E04 : Déployer NetBox sur nbx01
# À lancer depuis adm01. Lecture seule : qm config sur pve01, état de nbx01 en SSH, API NetBox
# avec le jeton v2 des checks (GET), certificat présenté, API GitLab en GET.

# shellcheck source=_m06-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-decouverte.sh"

title "M06-E04 — Déployer NetBox sur nbx01"
require_cmd jq curl openssl dig

_m06d_e04_jeton="${WB_NETBOX_TOKEN_FILE:-$_M06D_CFG/netbox-checks.token}"

# --- 1. La VM, créée par OpenTofu -----------------------------------------------------------
_m06d_e04_conf="$(_m06d_qm 1005)"
check_cmd "VM 1005 nommée nbx01" _m06d_qm_a "$_m06d_e04_conf" name 'nbx01$'
check_cmd "nbx01 : étiquettes socle et role-netbox" _m06d_etiquettes "$_m06d_e04_conf" socle role-netbox
check_cmd "nbx01 : membre du pool lab" _m06d_dans_pool 1005
check_cmd "nbx01 : 2 vCPU, 4096 Mo" bash -c 'grep -q "^cores: 2$" <<<"$1" && grep -q "^memory: 4096$" <<<"$1"' _ "$_m06d_e04_conf"
check_cmd "nbx01 : sur vinfra en 10.10.20.13/24" bash -c 'grep -Eq "^net0: .*bridge=vinfra" <<<"$1" && grep -q "ip=10.10.20.13/24" <<<"$1"' _ "$_m06d_e04_conf"
check_cmd "nbx01 : déclarée dans l'état socle de plateforme/infra (vm_id = 1005)" _m06d_declaree_iac 1005
check_dns "DNS : nbx01.par1.medisphere.internal → 10.10.20.13" nbx01.par1.medisphere.internal A '^10\.10\.20\.13$' "$_M06D_DNS"
check_dns "DNS : 10.10.20.13 → nbx01.par1.medisphere.internal" 13.20.10.10.in-addr.arpa PTR '^nbx01\.par1\.medisphere\.internal\.$' "$_M06D_DNS"

# --- 2. La pile sur nbx01 ------------------------------------------------------------------------
for _m06d_e04_s in netbox netbox-rq nginx valkey-server postgresql@17-main; do
  check_ssh "nbx01 : service $_m06d_e04_s actif" nbx01 "systemctl is-active --quiet $_m06d_e04_s"
done
check_ssh "nbx01 : NetBox et sa file de tâches lancés au démarrage" nbx01 \
  'systemctl is-enabled --quiet netbox && systemctl is-enabled --quiet netbox-rq'
check_ssh_output "nbx01 : /opt/netbox désigne une installation 4.6.x versionnée" nbx01 '^/opt/netbox-4\.6\.[0-9]+$' \
  'readlink -f /opt/netbox'
check_ssh "nbx01 : configuration.py illisible par les autres comptes (root:netbox, 640)" nbx01 \
  '[ "$(stat -c %U:%G:%a /opt/netbox/netbox/netbox/configuration.py)" = "root:netbox:640" ]'
check_ssh "nbx01 : PostgreSQL, Valkey et gunicorn n'écoutent que sur la boucle locale" nbx01 \
  's=$(ss -Hltn); ! grep -Eq "(0\.0\.0\.0|\*|\[::\]):(5432|6379|8001)[[:space:]]" <<<"$s" && grep -Eq "127\.0\.0\.1:8001[[:space:]]" <<<"$s"'
check_ssh "nbx01 : poivre des jetons API v2 configuré" nbx01 \
  'sudo -n grep -Eq "^API_TOKEN_PEPPERS[[:space:]]*=[[:space:]]*\{" /opt/netbox/netbox/netbox/configuration.py'

# --- 3. HTTPS, vu depuis adm01 ---------------------------------------------------------------------
check_http "https://nbx01.par1.medisphere.internal/login/ répond 200 (TLS vérifié)" \
  "https://nbx01.par1.medisphere.internal/login/" 200 --noproxy '*'
check_cmd "nbx01:443 : chaîne de la PKI MédiSphère, nom valide" _m06d_chaine_ok nbx01.par1.medisphere.internal 443
check_http "http:// redirige vers https://" "http://nbx01.par1.medisphere.internal/" 301 --noproxy '*'

# --- 4. L'API et les jetons --------------------------------------------------------------------------
check_cmd "Jeton des checks : fichier en 600, jeton v2 (nbt_…)" \
  bash -c '[[ "$(stat -c %a "$1" 2>/dev/null)" == 600 ]] && grep -q "^nbt_[A-Za-z0-9]*\." "$1"' _ "$_m06d_e04_jeton"
_m06d_e04_statut="$(netbox_api status/ 2>/dev/null || true)"
check_cmd "API : /api/status/ répond avec le jeton des checks" jq -e '."netbox-version"' <<<"$_m06d_e04_statut"
check_cmd "API : NetBox 4.6.x sur Python 3.13" \
  jq -e '(."netbox-version" | startswith("4.6.")) and (."python-version" | startswith("3.13."))' <<<"$_m06d_e04_statut"
check_cmd "API : au moins un worker de file de tâches (netbox-rq) en service" \
  jq -e '."rq-workers-running" >= 1' <<<"$_m06d_e04_statut"
# Le jeton des checks ne doit pas pouvoir écrire : la liste des jetons du compte indique write_enabled.
_m06d_e04_cle="$(sed -n 's/^nbt_\([A-Za-z0-9]*\)\..*/\1/p' "$_m06d_e04_jeton" 2>/dev/null || true)"
_m06d_e04_lecture_seule() {
  [[ -n "$_m06d_e04_cle" ]] || return 1
  netbox_api "users/tokens/?key=$_m06d_e04_cle" | jq -e '.results | length == 1 and (.[0].write_enabled == false)' >/dev/null
}
check_cmd "Jeton des checks : en lecture seule (write_enabled = false)" _m06d_e04_lecture_seule

# --- 5. Le code ---------------------------------------------------------------------------------------
check_cmd "plateforme/ansible (main) : rôle netbox" _m06d_fichier_main roles/netbox/tasks/main.yml
check_cmd "plateforme/ansible (main) : scénario Molecule netbox" _m06d_fichier_main molecule/netbox/molecule.yml
check_cmd "Secrets de NetBox chiffrés sous l'identité « critique »" _m06d_vault_critique inventories/lab/group_vars/role_netbox/vault-critique.yml
