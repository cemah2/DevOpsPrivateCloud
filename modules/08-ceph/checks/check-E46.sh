# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E46.sh — M08-E46 « Mini-projet : stockage MédiSphère v1 »
# Contrôle global du stockage v1 (à lancer depuis adm01) : cluster et services, consommateurs
# préparés (OpenStack, Kubernetes), sécurité, exploitation, acquis de M07 utilisés par le stockage
# (MTU 9000 de bout en bout sur les VLAN 30 et 31), absence de ceph04 et des ressources d'essai,
# documentation et livraison. Lecture seule : commandes Ceph de lecture sur l'hôte _admin, qm/pvesh
# en lecture, ip link et ping depuis les nœuds, lsblk, curl/openssl, dig, API GitLab et NetBox en GET,
# datastore de pbs01 (find). Les contrôles détaillés restent dans leurs exercices. Durée : 3 à 5 minutes.

# shellcheck source=_m08-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-production.sh"

title "M08-E46 — Stockage MédiSphère v1 : contrôle global"
require_cmd jq curl openssl dig git
_m08p_charger
check_cmd "le cluster répond depuis $_M08P_ADMIN (ceph status)" _m08p_joignable

# Contrôles dont la sourdine temporaire est admise à la livraison (clients qui ne peuvent pas encore
# utiliser le nouveau type de clé, ticket daté) : voir E27.
_m08_e46_sourdines_admises='^AUTH_INSECURE_(CLIENT_KEY_TYPE|KEYS_CREATABLE|KEYS_ALLOWED)$'

# --- 1. Cluster ----------------------------------------------------------------------------------
title "1/10 Cluster ceph-par1"
check_cmd "HEALTH_OK" _m08p_sante_ok
check_cmd "sourdines : temporaires, et seulement $_m08_e46_sourdines_admises" \
  _m08p_sourdines_temporaires "$_m08_e46_sourdines_admises"
check_cmd "3 MON en quorum (ceph01, ceph02, ceph03)" _m08p_jq _M08P_STATUS \
  '(.quorum_names | sort) == ["ceph01","ceph02","ceph03"]'
check_cmd "MGR : un actif et au moins un en attente" _m08p_jq _M08P_STATUS \
  '(.mgrmap.available == true) and ((.mgrmap.num_standbys // 0) >= 1)'
check_cmd "9 OSD, tous up et in" _m08p_jq _M08P_STATUS \
  '.osdmap.num_osds == 9 and .osdmap.num_up_osds == 9 and .osdmap.num_in_osds == 9'
check_cmd "tous les PG active+clean" _m08p_jq _M08P_STATUS \
  '(.pgmap.num_pgs > 0) and ([.pgmap.pgs_by_state[]? | select(.state_name == "active+clean") | .count] | add) == .pgmap.num_pgs'
check_cmd "démons Ceph (mon, mgr, osd, mds, rgw, crash) en $_M08P_VERSION" \
  _m08p_jq _M08P_PS "[.[] | select(.daemon_type | test(\"^(mon|mgr|osd|mds|rgw|crash)$\"))] | length > 0 and all(.[]; (.version // \"\") == \"$_M08P_VERSION\")"
for _m08_e46_h in "${_M08P_NOEUDS[@]}"; do
  check_ssh_output "$_m08_e46_h : commande cephadm (paquet) en $_M08P_VERSION" "$_m08_e46_h" "${_M08P_VERSION//./\\.}" \
    'sudo -n cephadm version 2>&1 | head -n 3'
done
check_cmd "autoscaler actif sur tous les pools" _m08p_jq _M08P_POOLS 'length > 0 and all(.[]; .pg_autoscale_mode == "on")'
check_cmd "osd_memory_target = 1 Gio au niveau osd, réglage automatique désactivé" \
  bash -c '[ "$1" = 0 ] && [ "$2" = false ]' _ \
  "$(_m08p_config_valeur osd osd_memory_target "$_M08P_MEM_OSD"; echo $?)" "$(_m08p_config_get osd osd_memory_target_autotune)"
check_cmd "orchestrateur : 3 hôtes, aucun en erreur ou en maintenance" \
  _m08p_jq _M08P_HOTES '([.[].hostname] | sort) == ["ceph01","ceph02","ceph03"] and all(.[]; (.status // "") == "")'

# --- 2. Rien de provisoire -------------------------------------------------------------------------
title "2/10 Rien de provisoire (ceph04, essais)"
check_cmd "ceph04 absent de la carte CRUSH" bash -c \
  'jq -e "[.nodes[]? | select(.type == \"host\") | .name] | index(\"ceph04\") | not" >/dev/null <<<"$1"' _ "$(_m08p_json 'osd tree')"
check_cmd "VM 2084 (ceph04) détruite" _m08p_vm_absente 2084
_m08_e46_nb_ceph04() {
  netbox_api "virtualization/virtual-machines/?name=ceph04" | jq -e '.count == 0 or (.results[0].status.value != "active")' >/dev/null
}
check_cmd "NetBox : ceph04 absent ou non actif" _m08_e46_nb_ceph04
check_cmd "DNS : ceph04 n'est plus publié" bash -c '[ -z "$(dig +short +time=3 @10.10.20.10 ceph04.par1.medisphere.internal A)" ]'
check_cmd "pool de mesure « bench » absent" _m08p_pool_absent bench
_m08_e46_pas_de_restau() { local l; l="$(_m08p_rbd 'ls rbd-test')" || return 1; ! grep -q '^restau-' <<<"$l"; }
check_cmd "aucune image restau-* dans rbd-test" _m08_e46_pas_de_restau
check_output "suppression de pool interdite (mon_allow_pool_delete)" '^false$' _m08p_config_get mon mon_allow_pool_delete
check_cmd "aucune panne M08 encore active (lab/bin/break)" _m08p_aucune_panne_active

# --- 3. Sécurité --------------------------------------------------------------------------------------
title "3/10 Sécurité"
for _m08_e46_o in ms_cluster_mode ms_service_mode ms_client_mode; do
  check_output "$_m08_e46_o = secure" '^secure$' _m08p_config_get osd "$_m08_e46_o"
done
check_output "ms_mon_service_mode = secure" '^secure$' _m08p_config_get mon ms_mon_service_mode
check_output "spécification des OSD : encrypted: true" 'encrypted: *true' _m08p_ceph 'orch ls osd --export'
for _m08_e46_h in "${_M08P_NOEUDS[@]}"; do
  check_cmd "$_m08_e46_h : trois OSD chiffrés (périphériques crypt)" _m08p_crypt "$_m08_e46_h" 3
done
for _m08_e46_c in AUTH_INSECURE_SERVICE_KEY_TYPE AUTH_INSECURE_SERVICE_TICKETS; do
  check_cmd "contrôle $_m08_e46_c absent" _m08p_controle_absent "$_m08_e46_c"
done
# Identités « clientes » : tout client.* hors administration et démons gérés par cephadm.
_m08_e46_clients_sobres() {
  _m08p_jq _M08P_AUTH '[.[] | select(.entity | test("^client\\.") and (test("^client\\.(admin|bootstrap-|crash\\.|rgw\\.|nfs\\.|ceph-exporter\\.|mds\\.|iscsi\\.|nvmeof\\.)") | not))
      | select(.caps | to_entries | any(.value | test("allow \\*|allow rwx")))] | length == 0'
}
check_cmd "aucune identité cliente avec « allow * » / « allow rwx »" _m08_e46_clients_sobres
check_cmd "identité de secours client.admin-backup absente" _m08p_entite_absente client.admin-backup
while read -r _m08_e46_h; do
  [[ -n "$_m08_e46_h" ]] || continue
  check_cmd "tableau de bord $_m08_e46_h:8443 : certificat PKI MédiSphère valide (> 10 jours)" \
    _m08p_cert "$_m08_e46_h.$_M08P_ZONE" 8443 10
done <<<"$(_m08p_hotes_type mgr 2>/dev/null || true)"

# --- 4. Consommateurs ----------------------------------------------------------------------------------
title "4/10 Consommateurs préparés (OpenStack, Kubernetes)"
for _m08_e46_p in "images ssd" "volumes ssd" "vms ssd" "k8s-rbd ssd" "backups hdd"; do
  read -r _m08_e46_n _m08_e46_cl <<<"$_m08_e46_p"
  check_cmd "pool $_m08_e46_n : application rbd" _m08p_pool_app "$_m08_e46_n" rbd
  check_cmd "pool $_m08_e46_n : règle de la classe $_m08_e46_cl" _m08p_pool_classe "$_m08_e46_n" "$_m08_e46_cl"
  check_cmd "pool $_m08_e46_n : quota posé" _m08p_pool_quota_min "$_m08_e46_n" 1
done
check_cmd "client.glance : profil rbd sur images (OSD et mgr)" bash -c \
  '[ "$1" = 0 ] && [ "$2" = 0 ]' _ "$(_m08p_caps client.glance osd 'profile rbd pool=images'; echo $?)" \
  "$(_m08p_caps client.glance mgr 'profile rbd pool=images'; echo $?)"
check_cmd "client.cinder : volumes et vms en écriture, images en lecture seule" bash -c \
  '[ "$1$2$3" = 000 ]' _ "$(_m08p_caps client.cinder osd 'profile rbd pool=volumes'; echo $?)" \
  "$(_m08p_caps client.cinder osd 'profile rbd pool=vms'; echo $?)" \
  "$(_m08p_caps client.cinder osd 'profile rbd-read-only pool=images'; echo $?)"
check_cmd "client.cinder-backup : profil rbd sur backups" _m08p_caps client.cinder-backup osd 'profile rbd pool=backups'
check_cmd "client.k8s : profil rbd sur k8s-rbd (OSD et mgr)" bash -c \
  '[ "$1" = 0 ] && [ "$2" = 0 ]' _ "$(_m08p_caps client.k8s osd 'profile rbd pool=k8s-rbd'; echo $?)" \
  "$(_m08p_caps client.k8s mgr 'profile rbd pool=k8s-rbd'; echo $?)"
for _m08_e46_c in client.glance client.cinder client.cinder-backup client.k8s; do
  check_cmd "$_m08_e46_c : aucune capacité « allow * » / « allow rwx »" _m08p_sans_allow_tout "$_m08_e46_c"
done

# --- 5. Objet et fichier -------------------------------------------------------------------------------
title "5/10 Objet (RGW) et fichier (CephFS)"
check_dns "rgw.par1.medisphere.internal → VIP 10.10.30.200" rgw.par1.medisphere.internal A '^10\.10\.30\.200$' 10.10.20.10
check_cmd "S3 en HTTPS : certificat PKI MédiSphère au nom de rgw.par1…, > 10 jours" \
  _m08p_cert rgw.par1.medisphere.internal 443 10
check_http "S3 répond par le nom (requête anonyme)" "https://rgw.par1.medisphere.internal/" 200 --cacert "$_M08P_RACINE"
check_ssh_output "cephcli01 joint le S3 en HTTPS (code HTTP)" cephcli01 '^200$' \
  'curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://rgw.par1.medisphere.internal/'
check_cmd "compte RGW de MédiDoc présent" bash -c 'jq -e ".id | startswith(\"RGW\")" >/dev/null <<<"$1"' _ \
  "$(_m08p_rgw 'account get --account-name=medidoc' 2>/dev/null || echo null)"
_m08_e46_fs="$(_m08p_json 'fs dump')"
check_cmd "CephFS « cephfs » : un MDS actif et au moins un en attente" bash -c \
  'jq -e "any(.filesystems[]?; .mdsmap.fs_name == \"cephfs\" and ([.mdsmap.info[]? | select(.state == \"up:active\")] | length >= 1))
          and ((.standbys // []) | length >= 1)" >/dev/null <<<"$1"' _ "$_m08_e46_fs"
for _m08_e46_g in mediagenda medidoc medinotif; do
  check_cmd "cephfs : groupe de sous-volumes $_m08_e46_g plafonné" bash -c \
    'jq -e "(.bytes_quota | type) == \"number\" and .bytes_quota > 0" >/dev/null <<<"$1"' _ \
    "$(_m08p_json "fs subvolumegroup info cephfs $_m08_e46_g")"
done

# --- 6. Exploitation --------------------------------------------------------------------------------------
title "6/10 Exploitation"
check_cmd "sonde ms-verif-ceph : timer actif, dernier passage réussi" bash -c \
  'systemctl is-active -q ms-verif-ceph.timer && [ "$(systemctl show ms-verif-ceph.service -p Result --value)" = success ]'
check_cmd "sonde ms-verif-ceph : le cluster va bien maintenant" timeout 180 /usr/local/bin/ms-verif-ceph --quiet
check_cmd "module prometheus : standby_behaviour = error" _m08p_config_valeur mgr mgr/prometheus/standby_behaviour error
check_cmd "pbs01 : volumes RBD sauvegardés dans par1/ceph il y a moins de 48 h" _m08p_pbs_recent '*rbd*.didx' 48
check_cmd "pbs01 : configuration du cluster sauvegardée il y a moins de 48 h" _m08p_pbs_recent '*config*.didx' 48
check_ssh "cephcli01 : dernier passage de la sauvegarde réussi" cephcli01 \
  '[ "$(systemctl show wb-backup-ceph.service -p Result --value)" = success ]'
check_cmd "aucun plantage non acquitté" bash -c 'jq -e "length == 0" >/dev/null <<<"$1"' _ "$(_m08p_json 'crash ls-new')"

# --- 7. Réseau (acquis M07) ----------------------------------------------------------------------------
title "7/10 Réseau : MTU 9000 de bout en bout (VLAN 30 et 31)"
for _m08_e46_v in "2081 ceph01" "2082 ceph02" "2083 ceph03"; do
  read -r _m08_e46_id _m08_e46_h <<<"$_m08_e46_v"
  check_cmd "VM $_m08_e46_id : cartes net0 et net1 en mtu=9000 (Proxmox)" bash -c \
    '[ "$1$2" = 00 ]' _ "$(_m08p_vm_mtu "$_m08_e46_id" net0; echo $?)" "$(_m08p_vm_mtu "$_m08_e46_id" net1; echo $?)"
  check_cmd "$_m08_e46_h : ens18 et ens19 en MTU 9000" bash -c \
    '[ "$1$2" = 00 ]' _ "$(_m08p_mtu "$_m08_e46_h" ens18 9000; echo $?)" "$(_m08p_mtu "$_m08_e46_h" ens19 9000; echo $?)"
done
check_cmd "VM 2085 (cephcli01) : carte net0 en mtu=9000" _m08p_vm_mtu 2085 net0
for _m08_e46_d in 10.10.30.52 10.10.30.53 10.10.31.52 10.10.31.53 10.10.30.20; do
  check_cmd "ceph01 → $_m08_e46_d : 9000 octets sans fragmentation" _m08p_ping_jumbo ceph01 "$_m08_e46_d"
done
check_cmd "cephcli01 → passerelle du VLAN 30 (10.10.30.1) : 9000 octets sans fragmentation" \
  _m08p_ping_jumbo cephcli01 10.10.30.1

# --- 8. NetBox et DNS -------------------------------------------------------------------------------------
title "8/10 Inventaire (NetBox, DNS)"
_m08_e46_nb_vm() {
  netbox_api "virtualization/virtual-machines/?name=$1" | jq -e --arg ip "$2" \
    '.count == 1 and (.results[0].primary_ip4.address // "" | startswith($ip + "/")) and (.results[0].status.value == "active")' >/dev/null
}
for _m08_e46_h in ceph01 ceph02 ceph03 cephcli01; do
  check_cmd "NetBox : $_m08_e46_h actif, ${_M08P_IP_PUB[$_m08_e46_h]} en adresse primaire" \
    _m08_e46_nb_vm "$_m08_e46_h" "${_M08P_IP_PUB[$_m08_e46_h]}"
  check_dns "DNS : $_m08_e46_h.$_M08P_ZONE → ${_M08P_IP_PUB[$_m08_e46_h]}" "$_m08_e46_h.$_M08P_ZONE" A \
    "^${_M08P_IP_PUB[$_m08_e46_h]//./\\.}\$" 10.10.20.10
done
_m08_e46_nb_vip() { netbox_api "ipam/ip-addresses/?address=10.10.30.200" | jq -e '.count >= 1' >/dev/null; }
check_cmd "NetBox : VIP 10.10.30.200 (RGW) déclarée" _m08_e46_nb_vip

# --- 9. Code ----------------------------------------------------------------------------------------------
title "9/10 Code et pipelines"
for _m08_e46_p in ceph ansible infra outils medisphere; do
  check_cmd "plateforme/$_m08_e46_p : dernier pipeline de main réussi" _m08p_pipeline_ok "plateforme/$_m08_e46_p"
done
for _m08_e46_f in specs/osd.yaml specs/rgw.yaml specs/ingress.yaml; do
  _m08_e46_spec() { [[ -n "$(_m08p_fichier_main plateforme/ceph "$1" 2>/dev/null)" ]]; }
  check_cmd "plateforme/ceph : $_m08_e46_f sur main" _m08_e46_spec "$_m08_e46_f"
done
_m08_e46_osd_chiffre_code() { _m08p_fichier_main plateforme/ceph specs/osd.yaml 2>/dev/null | grep -Eq 'encrypted: *true'; }
check_cmd "plateforme/ceph : specs/osd.yaml porte encrypted: true" _m08_e46_osd_chiffre_code
check_cmd "plateforme/ceph : pools des consommateurs décrits dans le code" _m08p_recherche_main plateforme/ceph k8s-rbd

# --- 10. Documentation et livraison -------------------------------------------------------------------------
title "10/10 Documentation et livraison (plateforme/medisphere)"
check_cmd "docs/stockage/architecture.md (démons, réseaux, pools, pannes)" \
  _m08p_doc_main docs/stockage/architecture.md 'MON' 'OSD' '10\.10\.31' 'ingress'
check_cmd "politique de stockage" _m08p_doc_main docs/stockage/politique-stockage.md 'classe' 'sant'
check_cmd "ADR-0080 présent" _m08p_doc_prefixe docs/stockage/adr ADR-0080
for _m08_e46_r in RB-080 RB-081 RB-082; do
  check_cmd "$_m08_e46_r présent" _m08p_doc_prefixe docs/stockage/runbooks "$_m08_e46_r"
done
check_cmd "registre des allocations : équipes et consommateurs" \
  _m08p_doc_main docs/stockage/allocations.md mediagenda medidoc medinotif 'k8s-rbd' 'volumes'
check_cmd "test de restauration consigné (RTO)" _m08p_doc_main docs/stockage/tests/restauration-ceph.md 'RTO' 'RPO'
check_cmd "matrice des flux : cephcli01 et VIP RGW" \
  _m08p_doc_main docs/socle/matrice-flux.md '10\.10\.30\.20([^0-9]|$)' '10\.10\.30\.200'
check_cmd "inventaire : nœuds Ceph et client" \
  _m08p_doc_main docs/socle/inventaire.md 'ceph01' '10\.10\.30\.51' 'cephcli01' '10\.10\.30\.20([^0-9]|$)'
check_cmd "registre des secrets : cephx, tableau de bord, LUKS, clé SSH de cephadm, sauvegardes" \
  _m08p_doc_main docs/socle/registre-secrets.md 'cephx' 'dashboard|tableau de bord' 'luks' 'cephadm' 'pbs'
_m08_e46_etiquette() { gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/stockage-v1' | jq -e '.name == "stockage-v1"' >/dev/null; }
check_cmd "plateforme/medisphere : étiquette stockage-v1 publiée" _m08_e46_etiquette
check_output "dépôt de documentation local : aucune modification non commitée" '^$' git -C "$_M08P_DEPOT" status --porcelain
check_cmd "aucun secret évident dans docs/ (clé privée, clé cephx, clé d'accès S3)" bash -c \
  '! grep -REq "(BEGIN [A-Z ]*PRIVATE KEY|key = AQ[A-Za-z0-9+/]{30,}={0,2}|aws_secret_access_key *= *[A-Za-z0-9/+]{30,})" "$1/docs"' _ "$_M08P_DEPOT"
