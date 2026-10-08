# shellcheck shell=bash
# _m08-expert.sh — fonctions partagées par les vérifications du palier 4 du module 08 (check-E35 à
# check-E44). Sourcé par ces scripts, jamais lancé seul. Lecture seule : commandes ceph/rbd/
# radosgw-admin de consultation (status, dump, get, info, ls), lectures sur les nœuds et sur le client.
# Préfixe _m08x_ : évite les collisions quand check-E43 charge plusieurs checks.
#
# Le nœud qui porte le trousseau admin est WB_CEPH_ADMIN (ceph01 par défaut) ; le client est
# WB_CEPH_CLIENT (cephcli01 par défaut). Les commandes ceph passent par la CLI du nœud si elle existe,
# sinon par « cephadm shell ».

_m08x_admin="${WB_CEPH_ADMIN:-ceph01}"
_m08x_client="${WB_CEPH_CLIENT:-cephcli01}"
_m08x_noeuds=(ceph01 ceph02 ceph03)
_m08x_pool=rbd-test
_m08x_fs=cephfs
_m08x_rgw=rgw.par1.medisphere.internal
# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
declare -A _m08x_ip_clu=([ceph01]=10.10.31.51 [ceph02]=10.10.31.52 [ceph03]=10.10.31.53)
# shellcheck disable=SC2034
declare -A _m08x_ip_pub=([ceph01]=10.10.30.51 [ceph02]=10.10.30.52 [ceph03]=10.10.30.53)

# _m08x_ceph_sh 'script' — exécute le script (bash) sur le nœud admin, dans l'environnement ceph.
_m08x_ceph_sh() {
  local s
  s="$(printf '%q' "$1")"
  remote "$_m08x_admin" "sudo -n bash -s" 2>/dev/null <<EOF
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
s=$s
if command -v ceph >/dev/null 2>&1 && [ -r /etc/ceph/ceph.client.admin.keyring ]; then
  timeout 150 bash -c "\$s" </dev/null
else
  timeout 180 cephadm shell -- bash -c "\$s" </dev/null 2>/dev/null
fi
EOF
}

# _m08x_ceph ARGS… — une commande ceph de consultation (sortie standard).
_m08x_ceph() {
  _m08x_ceph_sh "ceph --connect-timeout 15 $(printf '%q ' "$@")"
}

# _m08x_etat — instantané JSON du cluster (mis en cache pour tout le check) :
#   status, osd (osd dump), health (health detail), df (osd df), pools (osd pool ls detail),
#   fs (fs get cephfs), config (config dump), sonde / sondefs (droits seuls, jamais la clé),
#   rgw_sonde (suspended seulement), orch (ceph orch ps : type, nom, hôte, état).
# Valeur « null » pour une partie illisible ; tout « null » si les MON ne répondent pas.
# Cache partagé (check-E43 charge plusieurs checks) : rempli dans le shell courant, jamais dans un
# sous-shell (sinon chaque contrôle relirait tout le cluster).
_M08X_ETAT="${_M08X_ETAT:-}"
_m08x_charger() {
  if [[ -z "$_M08X_ETAT" ]]; then
    # shellcheck disable=SC2016  # script évalué dans l'environnement ceph du nœud admin
    _M08X_ETAT="$(_m08x_ceph_sh '
c() { ceph --connect-timeout 15 "$@"; }
j() { o="$(timeout 40 "$@" 2>/dev/null)" && [ -n "$o" ] && printf "%s" "$o" || printf null; }
droits() { timeout 30 ceph --connect-timeout 15 auth get "$1" -f json 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d[0][\"caps\"]))" 2>/dev/null || printf null; }
s="$(timeout 40 ceph --connect-timeout 15 status -f json 2>/dev/null)"
if [ -z "$s" ]; then printf "{\"status\":null}"; exit 0; fi
printf "{\"status\":%s" "$s"
printf ",\"osd\":"; j c osd dump -f json
printf ",\"health\":"; j c health detail -f json
printf ",\"df\":"; j c osd df -f json
printf ",\"pools\":"; j c osd pool ls detail -f json
printf ",\"rules\":"; j c osd crush rule dump -f json
printf ",\"classes\":"; j c osd crush class ls -f json
printf ",\"fs\":"; j c fs get cephfs -f json
printf ",\"config\":"; j c config dump -f json
printf ",\"blocklist\":"; j c osd blocklist ls -f json
printf ",\"quota\":"; j c osd pool get-quota rbd-test -f json
printf ",\"sonde\":"; droits client.sonde
printf ",\"sondefs\":"; droits client.sonde-fs
printf ",\"rgw_sonde\":"; timeout 40 radosgw-admin user info --uid=sonde-s3 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps({\"suspended\": d.get(\"suspended\")}))" 2>/dev/null || printf null
printf ",\"orch\":"; timeout 60 ceph --connect-timeout 15 orch ps -f json 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps([{\"type\": x.get(\"daemon_type\"), \"nom\": x.get(\"daemon_name\") or (x.get(\"daemon_type\",\"\") + \".\" + x.get(\"daemon_id\",\"\")), \"hote\": x.get(\"hostname\"), \"etat\": x.get(\"status_desc\")} for x in d]))" 2>/dev/null || printf null
printf "}"
')"
    jq -e . >/dev/null 2>&1 <<<"$_M08X_ETAT" || _M08X_ETAT='{"status":null}'
  fi
}
_m08x_etat() {
  _m08x_charger
  printf '%s\n' "$_M08X_ETAT"
}

# _m08x_jq 'filtre jq' — 0 si le filtre, appliqué à l'instantané, est vrai.
_m08x_jq() {
  _m08x_charger
  jq -e "$1" >/dev/null 2>&1 <<<"$_M08X_ETAT"
}

# _m08x_noeud HÔTE 'commande' — commande de lecture en root (sudo -n) sur un nœud ou le client.
_m08x_noeud() {
  remote "$1" "sudo -n bash -c $(printf '%q' "$2")" >/dev/null 2>&1
}

# _m08x_temoins — 0 si les témoins du palier 4 existent sur le client (créés à la première panne).
_m08x_temoins() {
  remote "$_m08x_client" "sudo -n test -s /etc/ceph/ceph.client.sonde.keyring -a -x /usr/local/sbin/wb-sonde-stockage" >/dev/null 2>&1
}

# _m08x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M08-* si aucune) n'est marquée.
_m08x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M08-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M08-$e" ]] || return 1
  done
}

# _m08x_cluster_repond — garde-fou commun : les MON répondent au nœud admin.
_m08x_cluster_repond() {
  _m08x_jq '.status != null'
}

# Commande distante : unités ceph-*@… masquées ou en échec sur l'hôte (aucune attendue).
# shellcheck disable=SC2016,SC2034
_m08x_cmd_unites_saines='! systemctl list-units --all --no-legend "ceph-*@*" 2>/dev/null | grep -Eq "[[:space:]](masked|failed)[[:space:]]" && ! systemctl list-unit-files --no-legend "ceph-*@*" 2>/dev/null | grep -q masked'
