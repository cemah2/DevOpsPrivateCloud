# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par jq
#
# check-E46.sh — M10-E46 « Mini-projet : cloud MédiSphère v1 » (PLAT-1190, étiquette cloud-v1)
# Contrôle global (à lancer depuis adm01) : nœuds, configuration Kolla en code, services, Ceph
# (acquis du M08 revérifié), TLS, multi-projets, Octavia OVN, libre-service, sauvegarde,
# supervision, sécurité, documentation et hygiène. Lecture seule. Durée : 3 à 6 minutes.
# Les contrôles détaillés de chaque brique restent dans leurs exercices (lab/bin/check 10 XX).

# shellcheck source=_m10-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-production.sh"

title "M10-E46 — Cloud MédiSphère v1 : contrôle global"
require_cmd openstack jq ssh curl openssl git
_m10p_charger
_m10_os="$_M10P_SRC/openstack"
_m10_doc="docs/cloud"

# --- 1. Nœuds -------------------------------------------------------------------------------------
title "1/10 Nœuds OpenStack (pve01)"
_m10_res="$(remote "$WB_PVE_HOST" 'pvesh get /cluster/resources --type vm --output-format json' 2>/dev/null || echo '[]')"
for _m10_v in "2101 osctl01" "2102 oscmp01" "2103 oscmp02"; do
  read -r _m10_id _m10_nom <<<"$_m10_v"
  check_cmd "VM $_m10_id $_m10_nom : démarrée, pool lab, étiquette env-m10" \
    jq -e --argjson id "$_m10_id" --arg n "$_m10_nom" '.[] | select(.vmid == $id)
      | .name == $n and .status == "running" and .pool == "lab" and ((.tags // "") | split(";") | index("env-m10"))' <<<"$_m10_res"
done
check_cmd "nœuds OpenStack décrits dans le code OpenTofu (plateforme/infra, clone ~/src/infra)" bash -c \
  'for i in 2101 2102 2103; do grep -rqsE "(^|[^0-9])$i([^0-9]|\$)" "$1" --include=*.tf || exit 1; done' _ "$_M10P_SRC/infra"

# --- 2. Configuration en code ---------------------------------------------------------------------
title "2/10 Configuration Kolla (plateforme/openstack)"
# _m10_val CLÉ — dernière valeur de CLÉ dans globals.yml puis globals.d/*.yml (ordre de Kolla).
_m10_val() {
  cat "$_m10_os/etc/kolla/globals.yml" "$_m10_os"/etc/kolla/globals.d/*.yml 2>/dev/null \
    | awk -v k="$1" -F': *' '$1 == k { v = $2 } END { sub(/[[:space:]]+#.*/, "", v); gsub(/["'"'"' ]/, "", v); print v }'
}
for _m10_kv in "kolla_base_distro=debian" "neutron_plugin_agent=ovn" "kolla_internal_vip_address=10.10.50.200" \
  "kolla_external_vip_address=10.10.50.201" "keepalived_virtual_router_id=150" "nova_backend_ceph=(yes|true)" \
  "enable_octavia=(yes|true)" "kolla_enable_tls_internal=(yes|true)" "kolla_enable_tls_external=(yes|true)" \
  "enable_mariabackup=(yes|true)"; do
  check_output "globals : ${_m10_kv%%=*} = ${_m10_kv#*=}" "^(${_m10_kv#*=})\$" _m10_val "${_m10_kv%%=*}"
done
check_output "passwords.yml chiffré (Ansible Vault, identité critique)" '^\$ANSIBLE_VAULT;1\.2;AES256;critique$' \
  head -n 1 "$_m10_os/etc/kolla/passwords.yml"
check_cmd "aucune clé privée dans le dépôt plateforme/openstack" bash -c \
  '! git -C "$1" grep -qE "BEGIN ([A-Z]+ )?PRIVATE KEY" HEAD -- . 2>/dev/null && git -C "$1" rev-parse HEAD >/dev/null' _ "$_m10_os"
check_cmd "plateforme/openstack : dernier pipeline de main réussi" _m10p_pipeline_ok plateforme/openstack
_m10_deploye_depuis_depot() {
  gitlab_api "projects/plateforme%2Fopenstack/repository/tags?search=deploye-&per_page=1" 2>/dev/null | jq -e 'length > 0' >/dev/null \
    || gitlab_api "projects/plateforme%2Fopenstack/jobs?scope%5B%5D=success&per_page=100" 2>/dev/null \
       | jq -e 'any(.[]?; .ref == "main" and (.name | test("deploy|deploi")))' >/dev/null
}
check_cmd "déploiement tracé depuis le dépôt (étiquette deploye-* ou job de déploiement réussi)" _m10_deploye_depuis_depot

# --- 3. Services ----------------------------------------------------------------------------------
title "3/10 Services OpenStack"
for _m10_h in "${_M10P_NOEUDS[@]}"; do
  check_cmd "$_m10_h : aucun conteneur unhealthy, arrêté ou en redémarrage" _m10p_conteneurs_sains "$_m10_h"
done
check_cmd "services de calcul : tous activés et « up »" _m10p_calcul_up
check_cmd "agents OVN : tous vivants, passerelle présente" _m10p_agents_vivants
check_cmd "services Cinder (scheduler, volume, backup) : « up »" _m10p_volumes_up
_m10_ovn_seul() {
  local l
  l="$(_m10p_os loadbalancer provider list)" || return 1
  jq -e 'any(.[]; .name == "ovn") and (any(.[]; .name == "amphora") | not)' >/dev/null <<<"$l"
}
check_cmd "Octavia : fournisseur ovn seul" _m10_ovn_seul

# --- 4. Ceph (acquis du M08) ------------------------------------------------------------------------
title "4/10 Stockage ceph-par1 (acquis du M08)"
check_ssh_output "ceph-par1 : HEALTH_OK" ceph01 '^HEALTH_OK' 'sudo -n cephadm shell -- ceph health 2>/dev/null'
check_ssh "pools images, volumes, vms, backups présents" ceph01 \
  'p=$(sudo -n cephadm shell -- ceph osd pool ls 2>/dev/null); for x in images volumes vms backups; do printf "%s\n" "$p" | grep -qx "$x" || exit 1; done'

# --- 5. TLS ---------------------------------------------------------------------------------------
title "5/10 TLS"
for _m10_p in 443 5000; do
  check_cmd "VIP externe :$_m10_p : certificat PKI MédiSphère valide plus de 10 jours, 31 jours au plus" \
    _m10p_cert_vip "$_M10P_NOM_EXT" "$_M10P_VIP_EXT" "$_m10_p"
done
check_cmd "VIP interne :5000 : certificat PKI MédiSphère valide" _m10p_cert_vip "$_M10P_NOM_INT" "$_M10P_VIP_INT" 5000

# --- 6. Multi-projets ---------------------------------------------------------------------------------
title "6/10 Domaines, projets, quotas"
_m10_pl="$(_m10p_os project list --domain medisphere 2>/dev/null || echo '[]')"
for _m10_p in plateforme mediagenda-dev mediagenda-prod; do
  check_cmd "projet $_m10_p (domaine medisphere)" jq -e --arg n "$_m10_p" 'any(.[]; .Name == $n)' <<<"$_m10_pl"
done
_m10_gl="$(_m10p_os group list --domain medisphere 2>/dev/null || echo '[]')"
check_cmd "groupes equipe-plateforme et equipe-mediagenda" \
  jq -e 'any(.[]; .Name == "equipe-plateforme") and any(.[]; .Name == "equipe-mediagenda")' <<<"$_m10_gl"
_m10_quota_mediagenda() {
  local id r
  id="$(jq -r '.[] | select(.Name == "mediagenda-dev") | .ID' <<<"$_m10_pl")"
  [[ -n "$id" ]] || return 1
  r="$(_m10p_quota "$id" ram)" || return 1
  # Quota de mémoire explicitement réduit (défaut de Nova : 51200 Mo, au-delà de la capacité du lab).
  [[ "$r" =~ ^[0-9]+$ ]] && ((r < 51200))
}
check_cmd "mediagenda-dev : quota de mémoire fixé sous le défaut de Nova" _m10_quota_mediagenda

# --- 7. Libre-service ----------------------------------------------------------------------------------
title "7/10 Libre-service (recette de MédiAgenda)"
_m10_lb="$(_m10p_os loadbalancer list 2>/dev/null | jq -c '[.[] | select(.name == "agenda-recette-lb")] | .[0] // null' 2>/dev/null || echo null)"
check_cmd "agenda-recette-lb : fournisseur ovn, ACTIVE, ONLINE" \
  jq -e '.provider == "ovn" and .provisioning_status == "ACTIVE" and .operating_status == "ONLINE"' <<<"$_m10_lb"
check_cmd "mediagenda/recette-infra : dernier pipeline de main réussi" _m10p_pipeline_ok mediagenda/recette-infra

# --- 8. Exploitation ------------------------------------------------------------------------------------
title "8/10 Sauvegarde et supervision"
check_cmd "adm01 : wb-openstack-mariabackup (timer actif, dernier passage réussi)" _m10p_unite_ok local wb-openstack-mariabackup
check_cmd "osctl01 : wb-backup-socle (timer actif, dernier passage réussi)" _m10p_unite_ok osctl01 wb-backup-socle
check_ssh "pbs01 : instantané de moins de 48 h dans par1/openstack" "$WB_PBS_HOST" '
  p=$(proxmox-backup-manager datastore show ds-lab --output-format json | sed -nE "s/.*\"path\" *: *\"([^\"]+)\".*/\1/p")
  [ -n "$p" ] && find "$p/ns/par1/ns/openstack" -mindepth 3 -maxdepth 3 -type d -mmin -2880 2>/dev/null | grep -q .'
check_cmd "adm01 : ms-verif-openstack (timer actif, dernier passage réussi)" _m10p_unite_ok local ms-verif-openstack
check_cmd "ms-verif-openstack conclut, maintenant, que le cloud va bien" timeout 300 /usr/local/bin/ms-verif-openstack --quiet

# --- 9. Sécurité ------------------------------------------------------------------------------------------
title "9/10 Sécurité"
check_ssh "Keystone : verrouillage des comptes (5 échecs)" osctl01 \
  'sudo -n grep -Eq "^lockout_failure_attempts[[:space:]]*=[[:space:]]*5$" /etc/kolla/keystone/keystone.conf'
_m10_internes() {
  local l
  l="$(_m10p_os endpoint list --interface internal)" || return 1
  jq -e 'type == "array" and length > 0 and all(.[]; .URL | startswith("https://"))' >/dev/null <<<"$l"
}
check_cmd "catalogue : points « internal » en HTTPS" _m10_internes
check_output "secure.yaml (~/.config/openstack) en 600" '^[4-7]00$' stat -c '%a' "$HOME/.config/openstack/secure.yaml"
check_cmd "fichiers de secrets de ~/.config/workbook en 600" \
  bash -c '! find "$HOME/.config/workbook" -maxdepth 1 -type f \( -name "*.env" -o -name "*.token" -o -name "*.pass" \) ! -perm 600 | grep -q .'

# --- 10. Documentation, livraison, hygiène ----------------------------------------------------------------
title "10/10 Documentation, livraison, hygiène"
check_cmd "docs/cloud/guide-utilisateur.md (accès, projets, catalogue, limites)" \
  _m10p_fichier_contient plateforme/medisphere "$_m10_doc/guide-utilisateur.md" 'horizon|tableau de bord' 'quota' 'ovn'
for _m10_rb in RB-100 RB-101 RB-102; do
  check_cmd "$_m10_rb dans $_m10_doc/runbooks/" _m10p_doc_motif "$_m10_doc/runbooks" "$_m10_rb"
done
check_cmd "ADR-0100 dans $_m10_doc/adr/" _m10p_doc_motif "$_m10_doc/adr" ADR-0100
for _m10_f in haute-disponibilite.md sauvegarde-restauration.md securite.md libre-service.md; do
  check_cmd "$_m10_doc/$_m10_f présent" _m10p_fichier_existe plateforme/medisphere "$_m10_doc/$_m10_f"
done
_m10_etiquette() { gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/cloud-v1' 2>/dev/null | jq -e '.name == "cloud-v1"' >/dev/null; }
check_cmd "plateforme/medisphere : étiquette cloud-v1 publiée" _m10_etiquette
check_output "dépôt de documentation (~/medisphere) : aucune modification non commitée" '^$' git -C "$_M10P_DEPOT" status --porcelain
for _m10_p in ha-essai secu-essai maj-essai evac-essai; do
  check_cmd "plus aucune instance $_m10_p*" _m10p_aucune_instance "$_m10_p"
done
check_cmd "environnement chronométré retiré (projet medinotif-essai absent)" _m10p_projet_absent medinotif-essai medisphere
check_cmd "projet essai-restauration absent" _m10p_projet_absent essai-restauration medisphere
check_cmd "aucune panne M10 encore active (lab/bin/break)" _m10p_aucune_panne_active
check_cmd "plateforme/infra : dernier pipeline de main réussi (acquis du M05)" _m10p_pipeline_ok plateforme/infra
