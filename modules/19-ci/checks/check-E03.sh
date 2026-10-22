# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E03.sh — M19-E03 : mon01 et Mailpit, la messagerie du lab
# À lancer depuis adm01. Lecture seule : « qm config », « pvesh » et « pvesm list » sur pve01, DNS,
# consultation en SSH sur mon01 et git01 (systemctl show, sha256sum, grep d'un fichier généré), TLS
# et SMTP depuis adm01 (aucun message n'est déposé : la session sans STARTTLS doit être REFUSÉE),
# API de Mailpit en GET (compte wb-checks), fichiers de main en GET sur l'API GitLab.

# shellcheck source=_m19-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-decouverte.sh"

title "M19-E03 — mon01 et Mailpit : la messagerie du lab"
require_cmd jq curl dig openssl timeout

_m19d_e03_mp="${WB_MAILPIT_URL:-https://mon01.par1.medisphere.internal:8025}"
_m19d_e03_mpf="${WB_MAILPIT_CHECKS_FILE:-$HOME/.config/workbook/mailpit-checks.env}"

# --- 1. La VM et ses noms ------------------------------------------------------------------------
_m19d_e03_conf="$(_m19d_qm 1014)"
check_output "VM 1014 nommée mon01" '^name: mon01$' printf '%s\n' "$_m19d_e03_conf"
check_cmd "mon01 : 2 vCPU, 3072 Mo" bash -c 'grep -q "^cores: 2$" <<<"$1" && grep -q "^memory: 3072$" <<<"$1"' _ "$_m19d_e03_conf"
check_cmd "mon01 : étiquettes socle et role-supervision" _m19d_etiquettes "$_m19d_e03_conf" socle role-supervision
check_output "mon01 démarre avec pve01 (onboot)" '^onboot: 1$' printf '%s\n' "$_m19d_e03_conf"
_m19d_e03_pool() {
  remote "${WB_PVE_HOST:-pve01}" "pvesh get /pools/lab --output-format json" 2>/dev/null \
    | jq -e '(.members // .[0].members // []) | any(.vmid == 1014)' >/dev/null
}
check_cmd "mon01 dans le pool lab" _m19d_e03_pool
check_dns "mon01.par1.medisphere.internal → 10.10.20.19" mon01.par1.medisphere.internal A '^10\.10\.20\.19$'
check_dns "10.10.20.19 → mon01.par1.medisphere.internal (PTR)" 19.20.10.10.in-addr.arpa PTR '^mon01\.par1\.medisphere\.internal\.$'
check_dns "smtp.par1.medisphere.internal est un CNAME vers mon01" smtp.par1.medisphere.internal CNAME '^mon01\.par1\.medisphere\.internal\.$'
check_ssh_output "une sauvegarde PBS de la VM 1014 existe (${WB_PBS_STORAGE:-pbs-par2})" "${WB_PVE_HOST:-pve01}" \
  'backup/vm/1014/' "pvesm list ${WB_PBS_STORAGE:-pbs-par2} --vmid 1014"

# --- 2. Le service Mailpit ------------------------------------------------------------------------
if remote "$_M19D_MON01" true >/dev/null 2>&1; then
  check_ssh "mon01 : service mailpit actif" "$_M19D_MON01" 'systemctl is-active --quiet mailpit'
  check_ssh_output "mon01 : mailpit tourne sous l'utilisateur mailpit, sans nouveaux privilèges" "$_M19D_MON01" \
    '^User=mailpit;NoNewPrivileges=yes$' \
    'systemctl show mailpit -p User -p NoNewPrivileges | sort -r | paste -sd ";"'
  check_ssh_output "mon01 : seule capacité possible CAP_NET_BIND_SERVICE" "$_M19D_MON01" \
    '^CapabilityBoundingSet=cap_net_bind_service$' 'systemctl show mailpit -p CapabilityBoundingSet'
  check_ssh_output "mon01 : processus mailpit non root" "$_M19D_MON01" '^mailpit$' \
    'ps -o user= -C mailpit | sort -u'
  _m19d_e03_ver="$(remote "$_M19D_MON01" '/usr/local/bin/mailpit version --no-release-check' 2>/dev/null || true)"
  check_cmd "Mailpit 1.31.6 ou plus récent (1.31.x)" bash -c '
    v="$(grep -oE "v1\.31\.[0-9]+" <<<"$1" | head -n 1)"; [[ -n "$v" && "${v##*.}" -ge 6 ]]' _ "$_m19d_e03_ver"
  # Empreinte de l'archive installée = celle de l'inventaire (host_vars/mon01/ ou défauts du rôle).
  _m19d_e03_attendue="$( { _m19d_contenu_main plateforme/ansible inventories/lab/host_vars/mon01/mailpit.yml
                          _m19d_contenu_main plateforme/ansible roles/mailpit/defaults/main.yml; } \
                        | sed -n 's/^mailpit_sha256: *"\{0,1\}\([0-9a-f]\{64\}\)"\{0,1\}.*/\1/p' | head -n 1)"
  _m19d_e03_reelle="$(remote "$_M19D_MON01" \
    'v=$(readlink -f /usr/local/bin/mailpit); sha256sum "$(dirname "$v")"/mailpit-linux-amd64.tar.gz 2>/dev/null' 2>/dev/null \
    | cut -d' ' -f1 || true)"
  check_cmd "l'archive installée a l'empreinte SHA-256 de l'inventaire (main)" \
    bash -c '[[ -n "$1" && "$1" == "$2" ]]' _ "$_m19d_e03_attendue" "$_m19d_e03_reelle"
else
  check_ssh "connexion SSH à mon01 (alias $_M19D_MON01)" "$_M19D_MON01" true
  skip "contrôles du service sur mon01" "connexion SSH impossible"
fi

# --- 3. Réseau et TLS, vus de adm01 ----------------------------------------------------------------
check_port "SMTP joignable : smtp.par1.medisphere.internal:25" smtp.par1.medisphere.internal 25
check_port "interface joignable : mon01.par1.medisphere.internal:8025" mon01.par1.medisphere.internal 8025
_m19d_e03_tls() {  # PORT [-starttls smtp] — certificat présenté, vérifié par la racine MédiSphère
  local port="$1"; shift
  timeout 10 openssl s_client "$@" -connect "smtp.par1.medisphere.internal:$port" -servername smtp.par1.medisphere.internal \
    -CAfile "$_M19D_RACINE" -verify_return_error -verify_hostname smtp.par1.medisphere.internal </dev/null 2>&1
}
check_output "STARTTLS sur 25 : certificat valide pour smtp.par1.medisphere.internal, chaîne MédiSphère" \
  'Verify return code: 0 \(ok\)' _m19d_e03_tls 25 -starttls smtp
check_output "HTTPS sur 8025 : certificat valide pour smtp.par1.medisphere.internal, chaîne MédiSphère" \
  'Verify return code: 0 \(ok\)' _m19d_e03_tls 8025
# Session SMTP en clair : MAIL FROM doit être refusé (530) avant tout dépôt. Rien n'est envoyé.
_m19d_e03_clair() {
  timeout 10 bash -c '
    exec 3<>/dev/tcp/smtp.par1.medisphere.internal/25 || exit 1
    read -r -t 5 _ <&3
    printf "EHLO adm01.par1.medisphere.internal\r\n" >&3; sleep 1
    printf "MAIL FROM:<wb-checks@medisphere.internal>\r\n" >&3; sleep 1
    printf "QUIT\r\n" >&3
    timeout 3 cat <&3' 2>/dev/null || true
}
check_output "Mailpit refuse une session SMTP sans STARTTLS (530)" '^530 ' _m19d_e03_clair
check_output "l'API de Mailpit refuse une requête sans mot de passe (401)" '^401$' \
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" --cacert "$_M19D_RACINE" "$_m19d_e03_mp/api/v1/info"

# --- 4. Le message de GitLab -----------------------------------------------------------------------
check_cmd "$_m19d_e03_mpf en 600" _m19d_local600 "$_m19d_e03_mpf"
if [[ -r "$_m19d_e03_mpf" ]]; then
  _m19d_e03_msg="$(mailpit_api 'search?query=subject%3A%22M19-E03%22&limit=50' 2>/dev/null || true)"
  check_cmd "Mailpit : un message dont le sujet contient M19-E03, envoyé par gitlab@medisphere.internal" \
    _m19d_json "$_m19d_e03_msg" 'any(.messages[]?; (.From.Address // "") == "gitlab@medisphere.internal")'
else
  skip "message de test de GitLab dans Mailpit" "$_m19d_e03_mpf illisible"
fi
check_ssh_output "git01 : GitLab envoie à smtp.par1.medisphere.internal (réglages générés)" git01 \
  'smtp\.par1\.medisphere\.internal' 'sudo -n cat /var/opt/gitlab/gitlab-rails/etc/smtp_settings.rb'
check_ssh "git01 : STARTTLS automatique et certificat vérifié (pas de verify_mode « none »)" git01 '
  f=/var/opt/gitlab/gitlab-rails/etc/smtp_settings.rb
  sudo -n grep -Eq "enable_starttls_auto: *true" "$f" && ! sudo -n grep -Eiq "openssl_verify_mode: *.?none" "$f"'

# --- 5. Le code et la documentation sur main -------------------------------------------------------
check_cmd "plateforme/infra (main) : socle/mon01.tf (VMID 1014, CNAME smtp)" bash -c \
  'grep -q "1014" <<<"$1" && grep -q "smtp" <<<"$1"' _ "$(_m19d_contenu_main plateforme/infra socle/mon01.tf)"
check_cmd "plateforme/ansible (main) : rôle mailpit" _m19d_fichier_main plateforme/ansible roles/mailpit/tasks/main.yml
check_cmd "plateforme/ansible (main) : playbook de role_supervision" \
  _m19d_grep_main plateforme/ansible '^playbooks/.*\.ya?ml$' 'hosts: *role_supervision'
check_cmd "plateforme/ansible (main) : la bordure laisse les nœuds K8s joindre mon01:25" \
  _m19d_grep_main plateforme/ansible '^inventories/lab/group_vars/role_routeur/pare_feu\.ya?ml$' '10\.10\.20\.19|\$MON01'
check_cmd "plateforme/medisphere (main) : docs/socle/messagerie.md" \
  _m19d_fichier_main plateforme/medisphere docs/socle/messagerie.md
check_cmd "plateforme/medisphere (main) : la matrice des flux cite mon01 et le port 25" bash -c \
  'grep -i "mon01" <<<"$1" | grep -q "25"' _ "$(_m19d_contenu_main plateforme/medisphere docs/socle/matrice-flux.md)"
