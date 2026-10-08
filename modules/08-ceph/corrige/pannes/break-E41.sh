# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M08-E41 « Panne : le montage CephFS est figé »
#
# Témoin : client.sonde-fs, CephFS « cephfs » monté sur cephcli01:/mnt/sonde-fs (client noyau).
# Variantes :
#   1. tous les démons MDS du système de fichiers arrêtés et masqués, et standby_count_wanted mis à 0
#      (« économie de mémoire ») → plus aucun MDS actif, le montage se fige ;
#   2. session du client évincée par le MDS (après un sync) → le client est mis en liste de blocage
#      (blocklist) ; son montage ne répond plus que par des erreurs ou des attentes ;
#   3. droits cephx de client.sonde-fs réécrits avec un chemin MDS restreint (path=/medidoc), puis
#      remontage (simulation d'un redémarrage) → le montage de la racine est refusé.
# Aucune donnée n'est effacée : le client est synchronisé avant l'éviction, les droits d'origine et
# standby_count_wanted sont sauvegardés (local), les entrées de blocklist ajoutées sont mémorisées.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m08-commun.sh
source "$WB_ROOT/modules/08-ceph/corrige/pannes/_m08-commun.sh"

_E41_MDS_FAUX="allow rw fsname=${_M08_FS} path=/medidoc"

# _e41_ecrit — 0 si une écriture sur /mnt/sonde-fs aboutit en moins de 15 s.
_e41_ecrit() {
  m08_wb_exec "$_M08_CLIENT" >/dev/null 2>&1 <<'EOF'
mountpoint -q /mnt/sonde-fs || exit 1
( date -Is >/mnt/sonde-fs/essai && sync /mnt/sonde-fs/essai ) &
p=$!
i=0
while kill -0 "$p" 2>/dev/null && [ "$i" -lt 15 ]; do sleep 1; i=$((i + 1)); done
kill -0 "$p" 2>/dev/null && exit 1
wait "$p"
EOF
}
_e41_en_panne() { ! _e41_ecrit; }

# _e41_cap mds|mon|osd — droit cephx de client.sonde-fs pour ce type de démon.
_e41_cap() {
  m08_ceph auth get client.sonde-fs -f json 2>/dev/null | jq -r --arg t "$1" '.[0].caps[$t] // empty'
}

_mE41_une() {
  local n="$1" h d liste
  case "$n" in
    1)
      liste="$(m08_demons mds 2>/dev/null)"
      [[ -n "$liste" ]] || return 10
      m08_ecrire E41 demons "$liste"
      m08_ecrire E41 standby "$(m08_ceph fs get "$_M08_FS" -f json 2>/dev/null | jq -r '.mdsmap.standby_count_wanted')"
      m08_ceph fs set "$_M08_FS" standby_count_wanted 0 >/dev/null 2>&1 || return 1
      # Tous les MDS (actif et standby) : un standby restant reprendrait aussitôt le rang 0.
      while read -r h d; do
        [[ -n "${d:-}" ]] || continue
        m08_arreter "$h" "$d" masquer >/dev/null || { _e41_defaire 1; return 1; }
      done <<<"$liste"
      ;;
    2)
      m08_wb_exec "$_M08_CLIENT" >/dev/null <<'EOF' || return 1
sync
mountpoint -q /mnt/sonde-fs
EOF
      m08_ecrire E41 blocklist_avant "$(m08_ceph osd blocklist ls -f json 2>/dev/null | jq -c '[.[].addr]')"
      m08_admin F="$_M08_FS" >/dev/null <<'EOF' || return 1
id="$(ceph_ tell "mds.$F:0" session ls -f json | py_ '
for s in d:
    if s.get("client_metadata", {}).get("entity_id") == "sonde-fs":
        print(s["id"]); break')"
[ -n "$id" ] || exit 1
ceph_ tell "mds.$F:0" client evict "id=$id" >/dev/null
journal "session $id (client.sonde-fs) évincée"
EOF
      ;;
    3)
      m08_ecrire E41 cap_mds "$(_e41_cap mds)"
      m08_ecrire E41 cap_mon "$(_e41_cap mon)"
      m08_ecrire E41 cap_osd "$(_e41_cap osd)"
      [[ -n "$(m08_lire E41 cap_mds)" && -n "$(m08_lire E41 cap_osd)" ]] || return 1
      m08_wb_exec "$_M08_CLIENT" >/dev/null <<'EOF' || return 1
sync
if mountpoint -q /mnt/sonde-fs; then timeout 60 umount /mnt/sonde-fs || exit 1; fi
journal "CephFS démonté (simulation du redémarrage)"
EOF
      m08_admin MDS="$_E41_MDS_FAUX" F="$_M08_FS" >/dev/null <<'EOF' || { _e41_defaire 3; return 1; }
ceph_ auth caps client.sonde-fs mds "$MDS" mon "allow r fsname=$F" osd "allow rw tag cephfs data=$F"
EOF
      # Tentative de remontage, comme au démarrage : elle doit échouer.
      m08_wb_exec "$_M08_CLIENT" >/dev/null 2>&1 <<'EOF' || true
fsid="$(sed -nE 's/^[[:space:]]*fsid[[:space:]]*=[[:space:]]*//p' /etc/ceph/ceph.conf | head -n 1)"
timeout 30 mount -t ceph "sonde-fs@$fsid.cephfs=/" /mnt/sonde-fs -o secretfile=/etc/ceph/sonde-fs.secret,ms_mode=prefer-crc </dev/null
EOF
      ;;
  esac
  if ! m08_attendre 60 _e41_en_panne; then
    _e41_defaire "$n"
    return 10
  fi
  m08_journal E41 "variante $n posée"
}

# _e41_defaire N — retire la variante N si elle est encore en place, puis remonte le témoin.
_e41_defaire() {
  local h d avant sb
  case "$1" in
    1)
      while read -r h d; do
        [[ -n "${d:-}" ]] || continue
        m08_relancer "$h" "$d" >/dev/null
      done <<<"$(m08_lire E41 demons)"
      sb="$(m08_lire E41 standby)"
      if [[ -n "$sb" && "$(m08_ceph fs get "$_M08_FS" -f json 2>/dev/null | jq -r '.mdsmap.standby_count_wanted')" == 0 ]]; then
        m08_ceph fs set "$_M08_FS" standby_count_wanted "$sb" >/dev/null 2>&1 || true
      fi
      ;;
    2)
      avant="$(m08_lire E41 blocklist_avant)"
      # Entrées ajoutées par la panne : adresse de cephcli01, absentes avant l'injection.
      m08_ceph osd blocklist ls -f json 2>/dev/null \
        | jq -r --argjson av "${avant:-[]}" '.[].addr | select(startswith("10.10.30.20:")) | select(. as $a | $av | index($a) | not)' \
        | while read -r a; do
          m08_ceph osd blocklist rm "$a" >/dev/null 2>&1 || true
        done
      # Le montage évincé est inutilisable : démontage paresseux avant remontage.
      m08_wb_exec "$_M08_CLIENT" >/dev/null 2>&1 <<'EOF' || true
if mountpoint -q /mnt/sonde-fs; then
  ( ls /mnt/sonde-fs >/dev/null ) & p=$!; sleep 5
  if kill -0 "$p" 2>/dev/null || ! wait "$p"; then umount -l /mnt/sonde-fs; journal "annulation : montage évincé détaché (umount -l)"; fi
fi
EOF
      ;;
    3)
      if [[ -n "$(m08_lire E41 cap_mds)" && "$(_e41_cap mds)" == "$_E41_MDS_FAUX" ]]; then
        m08_admin MDS="$(m08_lire E41 cap_mds)" MON="$(m08_lire E41 cap_mon)" OSD="$(m08_lire E41 cap_osd)" >/dev/null <<'EOF' || wb_avert "annulation : droits de client.sonde-fs non rétablis"
ceph_ auth caps client.sonde-fs mds "$MDS" mon "$MON" osd "$OSD"
EOF
      fi
      ;;
  esac
  m08_temoins >/dev/null 2>&1 || wb_avert "témoin CephFS non remonté sur cephcli01 : sudo wb-sonde-stockage pour voir"
}

_e41_injecter() {
  m08_preparer || return 1
  m08_essayer E41 3 "$1"
}

panne_E41_v1() { _e41_injecter 1; }
panne_E41_v2() { _e41_injecter 2; }
panne_E41_v3() { _e41_injecter 3; }

verifier_E41() { _e41_en_panne; }

annuler_E41() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e41_defaire "$WB_VAR" ;;
    *) _e41_defaire 3; _e41_defaire 2; _e41_defaire 1 ;;
  esac
  m08_journal E41 "annulation"
  rm -rf -- "$(m08_etat E41)"
}

resume_E41() {
  echo "Le partage CephFS de cephcli01 (/mnt/sonde-fs) ne répond plus (figé ou absent)."
}

symptome_E41() {
  wb_symptome "Ticket INC-3547 — De : Nadia Roussel" \
    "Le partage CephFS de cephcli01 (/mnt/sonde-fs) ne répond plus : un « ls » reste bloqué ou" \
    "échoue, et la sonde (« sudo wb-sonde-stockage ») est rouge sur la ligne CephFS. Les volumes" \
    "RBD et le S3 vont bien. Ne redémarre pas cephcli01 « pour voir » : je veux comprendre." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 08 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 08 E41 3 "$@"; }
fi
