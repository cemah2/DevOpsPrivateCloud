# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E46.sh — M06-E46 « Mini-projet : socle MédiSphère v1 »
# Contrôle global du socle v1 (à lancer depuis adm01) : services socle du module 06, acquis des
# modules 00 à 05 encore valables (ce que le module 06 a remplacé — dnsmasq de dns01, CA provisoire —
# est au contraire vérifié absent), documentation et hygiène. Lecture seule : dig, curl, openssl,
# ssh (commandes de lecture), API GitLab et NetBox en GET, ansible-inventory, qm/pvesh en lecture.
# Les contrôles détaillés de chaque brique restent dans leurs exercices. Durée : 2 à 4 minutes.

# shellcheck source=_m06-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-expert.sh"

title "M06-E46 — Socle MédiSphère v1 : contrôle global"
require_cmd dig curl openssl jq git ssh ssh-keygen

_m06_e46_depot="${WB_DEPOT:-$HOME/medisphere}"
_m06_e46_doc="$_m06_e46_depot/docs/socle"

# --- 1. VMs du socle ---------------------------------------------------------------------------
title "1/11 VMs du socle (pve01)"
_m06_e46_res="$(remote "$WB_PVE_HOST" 'pvesh get /cluster/resources --type vm --output-format json' 2>/dev/null)" || _m06_e46_res='[]'
_m06_e46_vm() {
  jq -e --argjson id "$1" --arg r "$2" '.[] | select(.vmid == $id)
    | .status == "running" and .pool == "lab"
      and (((.tags // "") | split(";")) as $t | ($t | index("socle")) and ($t | index($r)))' >/dev/null <<<"$_m06_e46_res"
}
for _m06_e46_v in "1000 role-routeur" "1001 role-bastion" "1002 role-dns" "1003 role-pki" "1004 role-gitlab" \
  "1005 role-netbox" "1006 role-s3" "1007 role-runner" "1008 role-dns"; do
  read -r _m06_e46_id _m06_e46_role <<<"$_m06_e46_v"
  check_cmd "VM $_m06_e46_id : démarrée, pool lab, étiquettes socle et $_m06_e46_role" _m06_e46_vm "$_m06_e46_id" "$_m06_e46_role"
done
check_ssh "VMs 1000-1008 : démarrage automatique et agent QEMU" "$WB_PVE_HOST" \
  'for i in 1000 1001 1002 1003 1004 1005 1006 1007 1008; do qm config "$i" | grep -q "^onboot: 1" && qm guest cmd "$i" ping || exit 1; done'
check_cmd "ca01, nbx01 et dns02 décrits dans le code OpenTofu (~/src/infra/socle)" \
  bash -c 'for i in 1003 1005 1008; do grep -rqsE "(^|[^0-9])$i([^0-9]|\$)" "$1"/*.tf || exit 1; done' _ "${WB_SRC:-$HOME/src}/infra/socle"
_m06_e46_pas_env() { ! jq -e '.[] | select(.vmid >= 2000 and .vmid <= 2069)' >/dev/null <<<"$_m06_e46_res"; }
_m06_e46_current() {
  [[ "$(jq '[.[] | select(.template == 1 and (((.tags // "") | split(";")) as $t
    | ($t | index("current")) and ($t | index("debian13"))))] | length' <<<"$_m06_e46_res")" == 1 ]]
}
check_cmd "aucune VM d'environnement du bloc A restante (2000-2069)" _m06_e46_pas_env
check_cmd "image dorée Debian 13 « current » unique" _m06_e46_current

# --- 2. PKI ---------------------------------------------------------------------------------------
title "2/11 PKI (step-ca)"
check_http "ca01 : step-ca en bonne santé (/health)" "https://ca01.$_m06x_zone/health" 200
check_ssh "ca01 : provisioners ACME, JWK et SSH configurés" ca01 \
  'c=$(sudo -n cat /etc/step-ca/config/ca.json); for t in ACME JWK; do echo "$c" | grep -Eq "\"type\"[[:space:]]*:[[:space:]]*\"$t\"" || exit 1; done; echo "$c" | grep -Eq "\"enableSSHCA\"[[:space:]]*:[[:space:]]*true"'
check_ssh "ca01 : la clé de la racine n'est pas sur la CA en ligne" ca01 \
  '! sudo -n find /etc/step-ca -iname "*root*key*" | grep -q .'
check_cmd "adm01 : racine MédiSphère installée, CA provisoire retirée" \
  bash -c 'test -s /usr/local/share/ca-certificates/medisphere-root-ca.crt && ! test -e /usr/local/share/ca-certificates/medisphere-provisoire.crt && ! test -e /etc/ssl/certs/medisphere-provisoire.pem'
for _m06_e46_h in "${_m06x_hotes[@]}"; do
  check_ssh "$_m06_e46_h : racine MédiSphère installée, CA provisoire retirée" "$_m06_e46_h" \
    'test -s /usr/local/share/ca-certificates/medisphere-root-ca.crt && ! test -e /usr/local/share/ca-certificates/medisphere-provisoire.crt && ! test -e /etc/ssl/certs/medisphere-provisoire.pem'
done
_m06_e46_tls() { _m06x_https_ok "$@" && _m06x_emis_par_pki "$@"; }
for _m06_e46_s in "git01 443" "nbx01 443" "s3-01 8333"; do
  read -r _m06_e46_h _m06_e46_p <<<"$_m06_e46_s"
  check_cmd "$_m06_e46_h:$_m06_e46_p : HTTPS vérifié, émis par l'intermédiaire MédiSphère" \
    _m06_e46_tls "$_m06_e46_h.$_m06x_zone" "${_m06x_ip[$_m06_e46_h]}" "$_m06_e46_p"
  check_cmd "$_m06_e46_h:$_m06_e46_p : certificat ≤ 31 jours, plus de 10 jours restants (ACME renouvelé)" \
    _m06x_duree_ok "$_m06_e46_h.$_m06x_zone" "${_m06x_ip[$_m06_e46_h]}" "$_m06_e46_p"
done

# --- 3. SSH par certificats -----------------------------------------------------------------------
title "3/11 SSH par certificats"
_m06_e46_ca_hotes="$(mktemp)"
grep -h '^@cert-authority' "$HOME/.ssh/known_hosts" /etc/ssh/ssh_known_hosts 2>/dev/null >"$_m06_e46_ca_hotes" || true
check_cmd "adm01 : CA d'hôte déclarée (@cert-authority dans known_hosts)" test -s "$_m06_e46_ca_hotes"
_m06_e46_ssh_ca() {
  # Connexion avec, pour seule confiance, la CA d'hôte : prouve le certificat d'hôte.
  ssh -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$_m06_e46_ca_hotes" -o GlobalKnownHostsFile=/dev/null \
    -o HostKeyAlias="$1.$_m06x_zone" "${_m06x_ip[$1]}" true >/dev/null 2>&1
}
for _m06_e46_h in dns01 ca01 git01 nbx01 s3-01 runner01 dns02; do
  check_cmd "$_m06_e46_h : certificat d'hôte reconnu par la seule CA, connexion par certificat d'utilisateur" \
    _m06_e46_ssh_ca "$_m06_e46_h"
done
rm -f "$_m06_e46_ca_hotes"
# step-ca antidate les certificats SSH (« backdate », 1 min par défaut) : 16 h + 5 min de tolérance.
check_cmd "adm01 : certificat d'utilisateur de 16 h au plus" bash -c '
  c=$(ls "$HOME"/.ssh/*-cert.pub 2>/dev/null | head -n 1); [ -n "$c" ] || exit 1
  v=$(ssh-keygen -Lf "$c" | sed -nE "s/.*Valid: from ([0-9T:-]+) to ([0-9T:-]+).*/\1 \2/p")
  set -- $v; [ $# = 2 ] && [ $(( $(date -d "$2" +%s) - $(date -d "$1" +%s) )) -le 57900 ]'

# --- 4. NetBox ---------------------------------------------------------------------------------
title "4/11 NetBox, source de vérité"
_m06_e46_nb_statut() { netbox_api status/ | jq -e '(."netbox-version" | startswith("4.6.")) and ."rq-workers-running" >= 1' >/dev/null; }
check_cmd "API NetBox 4.6.x, workers actifs" _m06_e46_nb_statut
_m06_e46_nb_vm() {
  netbox_api "virtualization/virtual-machines/?name=$1" | jq -e --arg ip "$2" --argjson id "$3" \
    '.count == 1 and (.results[0].primary_ip4.address // "" | startswith($ip + "/"))
      and (.results[0].custom_fields.vmid == $id) and (.results[0].status.value == "active")' >/dev/null
}
for _m06_e46_h in gw01 adm01 dns01 ca01 git01 nbx01 s3-01 runner01 dns02; do
  check_cmd "NetBox : $_m06_e46_h (vmid ${_m06x_vmid[$_m06_e46_h]}, ${_m06x_ip[$_m06_e46_h]}, active)" \
    _m06_e46_nb_vm "$_m06_e46_h" "${_m06x_ip[$_m06_e46_h]}" "${_m06x_vmid[$_m06_e46_h]}"
done
_m06_e46_ipam() {
  local p
  for p in 10.10.20.0/24 10.10.99.0/24; do
    netbox_api "ipam/prefixes/?prefix=$p" | jq -e '.count == 1' >/dev/null || return 1
  done
  netbox_api "ipam/ip-ranges/?start_address=10.10.99.100" | jq -e '.count >= 1' >/dev/null
}
check_cmd "NetBox : préfixes 10.10.20.0/24 et 10.10.99.0/24, plage DHCP du VLAN 99" _m06_e46_ipam
_m06_e46_inv="$(_m06x_inv_netbox 2>/dev/null || true)"
_m06_e46_inv_json='{}'
if [[ -n "$_m06_e46_inv" ]]; then
  _m06_e46_inv_json="$(_m06x_ansible ansible-inventory -i "$_m06_e46_inv" --list 2>/dev/null)" || _m06_e46_inv_json='{}'
fi
_m06_e46_socle_complet() {
  local s h
  s="$(_m06x_hotes_groupe "$1" socle)"
  for h in gw01 adm01 dns01 ca01 git01 nbx01 s3-01 runner01 dns02; do grep -qx "$h" <<<"$s" || return 1; done
}
check_cmd "inventaire Ansible NetBox : les 9 hôtes du socle dans le groupe socle" _m06_e46_socle_complet "$_m06_e46_inv_json"

# --- 5. DNS ------------------------------------------------------------------------------------
title "5/11 DNS (PowerDNS)"
_m06_e46_deux() { _m06x_resout "$1" "$2" 10.10.20.10 && _m06x_resout "$1" "$2" 10.10.20.16; }
for _m06_e46_h in gw01 adm01 dns01 ca01 git01 nbx01 s3-01 runner01 dns02; do
  check_cmd "dns01 et dns02 : $_m06_e46_h → ${_m06x_ip[$_m06_e46_h]}" \
    _m06_e46_deux "$_m06_e46_h.$_m06x_zone" "${_m06x_ip[$_m06_e46_h]}"
done
check_dns "inverse de 10.10.20.16 (dns02)" 16.20.10.10.in-addr.arpa PTR '^dns02\.par1\.medisphere\.internal\.$' 10.10.20.10
check_dns "pbs01.par2.medisphere.internal" pbs01.par2.medisphere.internal A '^10\.20\.10\.10$' 10.10.20.10
check_output "récursion vers Internet" '^NOERROR$' _m06x_statut 10.10.20.10 deb.debian.org A
_m06_e46_dnssec() { _m06x_valide 10.10.20.10 "$_m06x_zone" SOA && _m06x_valide 10.10.20.16 "$_m06x_zone" SOA; }
check_cmd "zone $_m06x_zone validée DNSSEC par dns01 et dns02 (drapeau ad)" _m06_e46_dnssec
_m06_e46_serie() { dig +short +time=3 @"$1" -p 5300 "$_m06x_zone" SOA 2>/dev/null | awk '{ print $3 }'; }
check_cmd "secondaire à jour : même numéro de série sur dns01 et dns02" bash -c \
  '[ -n "$1" ] && [ "$1" = "$2" ]' _ "$(_m06_e46_serie 10.10.20.10)" "$(_m06_e46_serie 10.10.20.16)"
_m06_e46_axfr() {
  local n
  n="$(dig +noall +answer +time=3 +tries=1 @10.10.20.10 -p 5300 "$_m06x_zone" AXFR 2>/dev/null | awk '$4 == "SOA"' | wc -l)"
  ((n < 2))
}
check_cmd "transfert de zone sans TSIG refusé (depuis adm01)" _m06_e46_axfr
check_ssh "dns01 : dnsmasq désinstallé" dns01 \
  '[ "$(dpkg-query -W -f="\${Status}" dnsmasq 2>/dev/null)" != "install ok installed" ]'
check_cmd "projet Ansible : le rôle dnsmasq ne figure plus dans site.yml" \
  bash -c '! grep -Eq "(^|[[:space:]/])dnsmasq([[:space:]]*\$|[[:space:]]*#)" "$1/playbooks/site.yml"' _ "$_m06x_ansible_dir"

# --- 6. DHCP -----------------------------------------------------------------------------------
title "6/11 DHCP (Kea)"
for _m06_e46_h in dns01 dns02; do
  check_ssh "$_m06_e46_h : kea-dhcp4 actif, configuration valide, haute disponibilité (libdhcp_ha)" "$_m06_e46_h" \
    "$_m06x_kea4"'; [ -n "$k" ] && systemctl is-active -q "$k" && sudo -n kea-dhcp4 -t /etc/kea/kea-dhcp4.conf >/dev/null 2>&1 && sudo -n grep -q "libdhcp_ha.so" /etc/kea/kea-dhcp4.conf'
done
check_ssh "dns01 : kea-dhcp-ddns actif" dns01 "$_m06x_d2"'; [ -n "$d" ] && systemctl is-active -q "$d"'
check_ssh "gw01 : relais du VLAN 99 vers dns01 et dns02" gw01 \
  'c=$(grep -Ehs "^[[:space:]]*dhcp-relay=10\.10\.99\.1," /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf); echo "$c" | grep -q "10\.10\.20\.10" && echo "$c" | grep -q "10\.10\.20\.16"'

# --- 7. Temps ----------------------------------------------------------------------------------
title "7/11 Temps"
check_ssh "gw01 : sources Internet authentifiées par NTS" gw01 'sudo -n chronyc -n authdata | grep -q NTS'
for _m06_e46_h in dns01 ca01 nbx01 dns02; do
  check_ssh_output "$_m06_e46_h : synchronisé sur la passerelle du VLAN" "$_m06_e46_h" '^\^\*' "chronyc -n sources"
done

# --- 8. Sauvegardes ----------------------------------------------------------------------------
title "8/11 Sauvegardes applicatives (PBS, espaces de noms par1/<hôte>)"
# git01 : sauvegarde applicative de GitLab (M01-E28), acquis revérifié.
for _m06_e46_h in git01 ca01 nbx01 dns01; do
  check_ssh "pbs01 : instantané de moins de 48 h dans par1/$_m06_e46_h" "$WB_PBS_HOST" '
    p=$(proxmox-backup-manager datastore show ds-lab --output-format json | sed -nE "s/.*\"path\" *: *\"([^\"]+)\".*/\1/p")
    [ -n "$p" ] && find "$p/ns/par1/ns/'"$_m06_e46_h"'" -mindepth 3 -maxdepth 3 -type d -mmin -2880 2>/dev/null | grep -q .'
done
check_ssh "pve01 : stockage pbs-par2 actif" "$WB_PVE_HOST" 'pvesm status --storage pbs-par2 | grep -Eq "^pbs-par2[[:space:]]+pbs[[:space:]]+active"'
check_cmd "test de restauration des services socle consigné (tests/restauration.md)" bash -c \
  'grep -Eqi "netbox|nbx01|powerdns|dns0[12]|kea|step-ca|ca01" "$1" && grep -Eq "([0-9]+ ?min|RTO)" "$1"' _ "$_m06_e46_doc/tests/restauration.md"

# --- 9. Supervision ----------------------------------------------------------------------------
title "9/11 Supervision"
_m06_e46_timer() {
  local u=ms-verif-services
  if systemctl cat "$u.timer" >/dev/null 2>&1; then
    systemctl is-active -q "$u.timer" && [[ "$(systemctl show "$u.service" -p Result --value)" == success ]]
  else
    remote runner01 "systemctl is-active -q $u.timer && [ \"\$(systemctl show $u.service -p Result --value)\" = success ]"
  fi
}
check_cmd "sondes ms-verif-services planifiées (adm01 ou runner01), dernier passage réussi" _m06_e46_timer

# --- 10. Acquis des modules 01 à 05 ------------------------------------------------------------
title "10/11 Acquis des modules 01 à 05"
_m06_e46_gitlab() { gitlab_api version | jq -e '.version | startswith("19.4.")' >/dev/null; }
_m06_e46_runner() {
  gitlab_api 'runners/all?type=instance_type&tag_list=shell,socle&per_page=100' \
    | jq -e 'any(.[]; .status == "online" and (.paused | not))' >/dev/null
}
# « manual » = réussi, avec des jobs manuels non lancés (apply d'OpenTofu, appliquer d'Ansible).
_m06_e46_pipeline() {
  gitlab_api "projects/plateforme%2F$1/pipelines?ref=main&per_page=1" \
    | jq -e '.[0].status == "success" or .[0].status == "manual"' >/dev/null
}
check_cmd "GitLab 19.4.x répond (API, jeton des checks)" _m06_e46_gitlab
check_cmd "runner d'instance shell+socle en ligne" _m06_e46_runner
for _m06_e46_p in medisphere outils images ansible infra tofu-modules; do
  check_cmd "plateforme/$_m06_e46_p : dernier pipeline de main réussi" _m06_e46_pipeline "$_m06_e46_p"
done
check_cmd "medictl répond (API Proxmox)" bash -c 'medictl vm list --pool lab --format json 2>/dev/null | jq -e "length > 0" >/dev/null'
check_cmd "inventaire Proxmox (M04) : socle complet" _m06_e46_socle_complet \
  "$(_m06x_ansible ansible-inventory -i inventories/lab/proxmox.yml --list 2>/dev/null || echo '{}')"
check_cmd "aucune panne des modules 00 à 06 encore active" \
  bash -c '! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/{E,M0}* >/dev/null 2>&1'

# --- 11. Documentation et livraison ------------------------------------------------------------
title "11/11 Documentation (plateforme/medisphere)"
check_cmd "docs/socle/services.md présent (PKI, NetBox, DNS, DHCP, temps)" bash -c \
  'for m in step-ca NetBox PowerDNS Kea chrony; do grep -qi "$m" "$1" || exit 1; done' _ "$_m06_e46_doc/services.md"
check_cmd "politique de certification présente" test -s "$_m06_e46_doc/pki/politique-certification.md"
check_cmd "ADR-0060 et RB-060 présents" bash -c \
  'ls "$1"/adr/ADR-0060*.md >/dev/null 2>&1 && ls "$1"/runbooks/RB-060*.md >/dev/null 2>&1' _ "$_m06_e46_doc"
check_cmd "post-mortem de l'astreinte INC-3350 présent" bash -c 'ls "$1"/post-mortems/*INC-3350*.md >/dev/null 2>&1' _ "$_m06_e46_doc"
check_cmd "inventaire : ca01, nbx01 et dns02 avec leurs adresses" bash -c \
  'for m in ca01 10.10.20.11 nbx01 10.10.20.13 dns02 10.10.20.16; do grep -qF "$m" "$1" || exit 1; done' _ "$_m06_e46_doc/inventaire.md"
check_cmd "registre des secrets : jetons NetBox, clés TSIG, clé d'API PowerDNS, PKI" bash -c \
  'for m in netbox tsig powerdns step; do grep -qi "$m" "$1" || exit 1; done' _ "$_m06_e46_doc/registre-secrets.md"
check_cmd "code de gw01 (host_vars/gw01) : relais DHCP et flux vers dns02 déclarés" bash -c \
  'grep -rqs "10\.10\.20\.16" "$1/inventories/lab/host_vars/gw01/"' _ "$_m06x_ansible_dir"
check_cmd "matrice des flux documentée : dns02 et ca01 présents" bash -c \
  'grep -q "10\.10\.20\.16" "$1" && grep -q "10\.10\.20\.11" "$1"' _ "$_m06_e46_doc/matrice-flux.md"
check_output "dépôt de documentation : aucune modification non commitée" '^$' git -C "$_m06_e46_depot" status --porcelain
_m06_e46_etiquette() { gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/socle-v1' | jq -e '.name == "socle-v1"' >/dev/null; }
check_cmd "plateforme/medisphere : étiquette socle-v1 publiée" _m06_e46_etiquette
check_cmd "aucun secret évident dans docs/socle (clé privée, jeton NetBox, jeton GitLab)" bash -c \
  '! grep -REq "(BEGIN [A-Z ]*PRIVATE KEY|nbt_[A-Za-z0-9]{8,}\.[A-Za-z0-9]{16,}|glpat-[A-Za-z0-9_-]{20})" "$1"' _ "$_m06_e46_doc"
check_cmd "aucune panne M06 encore active (lab/bin/break)" _m06x_aucune_panne_active
# Secrets seulement (*.env, *.token, *.pass) : pve-root-ca.pem (public, M00) peut rester en 640.
check_cmd "fichiers de secrets de ~/.config/workbook en mode 600" \
  bash -c '! find "$HOME/.config/workbook" -maxdepth 1 -type f \( -name "*.env" -o -name "*.token" -o -name "*.pass" \) ! -perm 600 | grep -q .'
