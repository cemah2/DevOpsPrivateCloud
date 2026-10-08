# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes et filtres entre apostrophes sont évalués ailleurs
#
# check-E10.sh — M10-E10 : Brancher OpenStack sur Ceph
# À lancer depuis adm01. Lecture seule : API OpenStack, GitLab, cephadm shell sur ceph01, virsh sur oscmp01.

# shellcheck source=_m10-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-operationnel.sh"

title "M10-E10 — Brancher OpenStack sur Ceph"
require_cmd openstack jq curl

# --- Dépôt -------------------------------------------------------------------------------------------
_m10o_g="$(_m10o_globals)"
for _m10o_v in enable_cinder enable_cinder_backup; do
  check_cmd "globals.yml (main) : $_m10o_v activé" _m10o_globals_vaut "$_m10o_g" "$_m10o_v" 'yes|true|True'
done
for _m10o_v in glance_backend_ceph cinder_backend_ceph nova_backend_ceph; do
  check_cmd "globals.yml (main) : $_m10o_v activé" _m10o_globals_vaut "$_m10o_g" "$_m10o_v" 'yes|true|True'
done
check_cmd "globals.yml (main) : Nova utilise sa propre clé (ceph_nova_user: nova)" \
  _m10o_globals_vaut "$_m10o_g" ceph_nova_user 'nova'
_m10o_sans_admin() { [[ -n "$1" ]] && ! grep -Eq '^ceph_[a-z_]*user:[[:space:]]*["'"'"']?admin' <<<"$1"; }
check_cmd "globals.yml (main) : aucun service ne se connecte à Ceph en client.admin" _m10o_sans_admin "$_m10o_g"

# Aucune clé cephx (base64 de 40 caractères commençant par AQ et finissant par ==) ni trousseau client.admin dans
# etc/kolla/config/ sur main.
_m10o_cles_en_clair() {
  local f contenu trouve=0 n=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    n=$((n + 1))
    contenu="$(_m10o_contenu_main "$_M10O_PROJET_OS" "$f")"
    grep -q '^\$ANSIBLE_VAULT' <<<"$contenu" && continue
    if grep -Eq 'AQ[A-Za-z0-9+/]{36}==|\[client\.admin\]' <<<"$contenu"; then trouve=1; fi
  done < <(_m10o_arbre_main "$_M10O_PROJET_OS" etc/kolla/config)
  [[ "$n" -gt 0 && "$trouve" -eq 0 ]]
}
_m10o_trousseaux_presents() {
  _m10o_arbre_main "$_M10O_PROJET_OS" etc/kolla/config | grep -q 'nova/ceph\.client\.nova\.keyring$'
}
check_cmd "dépôt : trousseau de client.nova présent pour Nova" _m10o_trousseaux_presents
check_cmd "dépôt : aucune clé cephx en clair ni trousseau client.admin sous etc/kolla/config" _m10o_cles_en_clair

# --- Ceph : droits des clés ----------------------------------------------------------------------------
for _m10o_c in glance cinder cinder-backup nova; do
  _m10o_caps="$(_m10o_ceph ceph auth get "client.$_m10o_c")"
  check_output "ceph-par1 : client.$_m10o_c existe et ses droits OSD sont limités par profil rbd" \
    'caps osd = "profile rbd' echo "$_m10o_caps"
done

# --- Services ------------------------------------------------------------------------------------------
_m10o_vs="$(_m10o_os volume service list -f json || true)"
check_cmd "cinder-volume (backend rbd-1) : enabled et up" \
  jq -e 'map(select(.Binary == "cinder-volume" and (.Host | test("@rbd-1")) and .Status == "enabled" and .State == "up")) | length > 0' <<<"$_m10o_vs"
check_cmd "cinder-backup : enabled et up" \
  jq -e 'map(select(.Binary == "cinder-backup" and .Status == "enabled" and .State == "up")) | length > 0' <<<"$_m10o_vs"
check_output "oscmp01 : deux secrets Ceph dans libvirt (Nova et Cinder)" '^[2-9]$' \
  remote oscmp01 'sudo -n docker exec nova_libvirt virsh secret-list | grep -c ceph'

# --- Images ----------------------------------------------------------------------------------------------
_m10o_images_ok() {
  local id ids n=0 img
  ids="$(_m10o_os image list --status active -f value -c ID || true)"
  [[ -n "$ids" ]] || return 1
  for id in $ids; do
    img="$(_m10o_os image show -f json "$id" || true)"
    jq -e '.disk_format == "raw"
           and ((.stores // "") | tostring | test("rbd"))
           and (((.direct_url // .properties.direct_url // "") | tostring) | startswith("rbd://"))' <<<"$img" >/dev/null 2>&1 \
      || { echo "image non conforme : $(jq -r .name <<<"$img")"; n=$((n + 1)); }
  done
  [[ "$n" -eq 0 ]]
}
check_cmd "toutes les images actives : raw, magasin rbd, emplacement Ceph publié" _m10o_images_ok

# --- Instances ----------------------------------------------------------------------------------------------
_m10o_vm="$(_m10o_serveur e10-vm)"
_m10o_vm_id="$(jq -r '.id // empty' <<<"$_m10o_vm" 2>/dev/null || true)"
if [[ -n "$_m10o_vm_id" ]]; then
  check_output "e10-vm : disque vms/${_m10o_vm_id}_disk, clone d'une image du pool images" 'parent: images/' \
    _m10o_ceph rbd info "vms/${_m10o_vm_id}_disk"
else
  _ko "e10-vm : instance introuvable (ou plusieurs du même nom)"
fi
_m10o_vol="$(_m10o_serveur e10-vol)"
_m10o_vol_disque="$(jq -r '[.volumes_attached // [] | .[]? | .id] | first // empty' <<<"$_m10o_vol" 2>/dev/null || true)"
if [[ -n "$_m10o_vol_disque" ]]; then
  check_cmd "e10-vol : démarre depuis un volume du pool volumes (volume-$_m10o_vol_disque)" \
    bash -c '[[ -n "$1" ]]' _ "$(_m10o_ceph rbd info "volumes/volume-$_m10o_vol_disque" | grep -m1 'size')"
else
  _ko "e10-vol : instance introuvable, ou sans volume attaché"
fi
