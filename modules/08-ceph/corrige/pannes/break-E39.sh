# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M08-E39 « Panne : le client RBD est refusé »
#
# Témoin : client.sonde, image rbd-test/sonde montée sur cephcli01:/mnt/sonde. L'injection simule le
# redémarrage planifié du client : sync, démontage et « unmap » propres, puis la panne ; la tentative
# de « rbd device map » qui suit échoue.
# Variantes :
#   1. droits cephx de client.sonde réécrits avec une faute dans le nom du pool (pool=rbd-tests) ;
#   2. trousseau de client.sonde sur cephcli01 remplacé par une clé valide en forme mais inconnue
#      du cluster (« restauration d'une vieille sauvegarde de /etc/ceph ») ;
#   3. fonctionnalité « journaling » activée sur l'image (non prise en charge par le pilote noyau krbd).
# Rien n'est effacé : droits d'origine sauvegardés (local), trousseau d'origine copié sous
# /var/lib/workbook/ de cephcli01, fonctionnalité désactivée à l'annulation. L'annulation remonte
# aussi le volume (m08_temoins) si la panne est encore là ; une réparation n'est jamais défaite.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m08-commun.sh
source "$WB_ROOT/modules/08-ceph/corrige/pannes/_m08-commun.sh"

_E39_CAPS_FAUSSES="profile rbd pool=${_M08_POOL}s"

# _e39_demonter — sync, démontage et unmap propres du témoin RBD sur cephcli01.
_e39_demonter() {
  m08_wb_exec "$_M08_CLIENT" P="$_M08_POOL" <<'EOF'
sync
if mountpoint -q /mnt/sonde; then timeout 60 umount /mnt/sonde || exit 1; fi
dev="$(rbd device list --format json 2>/dev/null | py_ '
for x in d:
    if x.get("pool") == "'"$P"'" and x.get("name") == "sonde":
        print(x["device"]); break' 2>/dev/null)"
if [ -n "$dev" ]; then timeout 60 rbd device unmap "$dev" || exit 1; fi
journal "témoin RBD démonté et libéré (simulation du redémarrage planifié)"
EOF
}

# _e39_map_echoue — 0 si une tentative de map par client.sonde échoue (et ne laisse rien de mappé).
_e39_map_echoue() {
  m08_wb_exec "$_M08_CLIENT" P="$_M08_POOL" >/dev/null 2>&1 <<'EOF'
if dev="$(timeout 60 rbd device map --id sonde -o ms_mode=prefer-crc "$P/sonde" </dev/null 2>/dev/null)"; then
  rbd device unmap "$dev" >/dev/null 2>&1 || true
  exit 1
fi
exit 0
EOF
}

_e39_caps_osd() {
  m08_ceph auth get client.sonde -f json 2>/dev/null | jq -r '.[0].caps.osd // empty'
}

_mE39_une() {
  local n="$1" rc=0
  case "$n" in
    1)
      m08_ecrire E39 caps_osd "$(_e39_caps_osd)"
      [[ -n "$(m08_lire E39 caps_osd)" ]] || return 1
      _e39_demonter >/dev/null || return 1
      m08_ceph auth caps client.sonde mon 'profile rbd' osd "$_E39_CAPS_FAUSSES" >/dev/null 2>&1 || return 1
      ;;
    2)
      _e39_demonter >/dev/null || return 1
      m08_wb_exec "$_M08_CLIENT" >/dev/null <<'EOF' || rc=$?
f=/etc/ceph/ceph.client.sonde.keyring
[ -s "$f" ] || exit 10
sauver "$f"
k="$(ceph-authtool --gen-print-key 2>/dev/null)" || k="$(head -c 16 /dev/urandom | base64)"
printf '[client.sonde]\n\tkey = %s\n' "$k" >"$f"
chmod 600 "$f"
touch -d "2025-11-04 03:12" "$f"
sha256sum "$f" | cut -d' ' -f1 >"$WB_DIR/M08-E39.injecte"
journal "trousseau de client.sonde remplacé par une clé inconnue du cluster"
EOF
      ((rc == 0)) || return "$rc"
      ;;
    3)
      _e39_demonter >/dev/null || return 1
      m08_ceph_rbd feature enable "$_M08_POOL/sonde" journaling >/dev/null 2>&1 || return 10
      ;;
  esac
  if ! _e39_map_echoue; then
    _e39_defaire "$n"
    return 10
  fi
  m08_journal E39 "variante $n posée"
}

# m08_ceph_rbd ARGS… — commande rbd sur le nœud admin.
m08_ceph_rbd() {
  local a
  a="$(printf '%q ' "$@")"
  m08_admin A="$a" <<'EOF'
ceph_sh "rbd $A"
EOF
}

_e39_journaling() {
  m08_ceph_rbd info "$_M08_POOL/sonde" --format json 2>/dev/null | jq -e '.features | index("journaling")' >/dev/null 2>&1
}

# _e39_defaire N — retire la variante N si elle est encore en place, puis remonte le témoin.
_e39_defaire() {
  local orig
  case "$1" in
    1)
      orig="$(m08_lire E39 caps_osd)"
      if [[ -n "$orig" && "$(_e39_caps_osd)" == "$_E39_CAPS_FAUSSES" ]]; then
        m08_ceph auth caps client.sonde mon 'profile rbd' osd "$orig" >/dev/null 2>&1 || wb_avert "annulation : droits de client.sonde non rétablis"
      fi
      ;;
    2)
      m08_wb_exec "$_M08_CLIENT" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur cephcli01 (trousseau)"
f=/etc/ceph/ceph.client.sonde.keyring
[ -f "$WB_DIR/M08-E39.injecte" ] || { restaurer_fichiers; exit 0; }
if [ "$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)" = "$(cat "$WB_DIR/M08-E39.injecte")" ]; then
  restaurer_fichiers
  journal "annulation : trousseau d'origine de client.sonde restauré"
else
  rm -f "$WB_DIR/M08-E39.manifeste" "$WB_DIR"/M08-E39.*.orig
  journal "annulation : trousseau modifié depuis l'injection (réparation), laissé tel quel"
fi
rm -f "$WB_DIR/M08-E39.injecte"
EOF
      ;;
    3)
      if _e39_journaling; then
        m08_ceph_rbd feature disable "$_M08_POOL/sonde" journaling >/dev/null 2>&1 || wb_avert "annulation : journaling non désactivé sur $_M08_POOL/sonde"
      fi
      ;;
  esac
  # Remontage du témoin (sans effet s'il est déjà monté par l'apprenant).
  m08_temoins >/dev/null 2>&1 || wb_avert "témoin RBD non remonté sur cephcli01 : sudo wb-sonde-stockage pour voir"
}

_e39_injecter() {
  m08_preparer || return 1
  m08_essayer E39 3 "$1"
}

panne_E39_v1() { _e39_injecter 1; }
panne_E39_v2() { _e39_injecter 2; }
panne_E39_v3() { _e39_injecter 3; }

verifier_E39() { _e39_map_echoue; }

annuler_E39() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e39_defaire "$WB_VAR" ;;
    *) _e39_defaire 3; _e39_defaire 2; _e39_defaire 1 ;;
  esac
  m08_journal E39 "annulation"
  rm -rf -- "$(m08_etat E39)"
}

resume_E39() {
  echo "Après le redémarrage planifié de cephcli01, le volume RBD /mnt/sonde ne se remonte plus (rbd device map refusé)."
}

symptome_E39() {
  wb_symptome "Ticket INC-3545 — De : Julien Petit" \
    "Après le redémarrage planifié de cette nuit, le volume RBD de test de cephcli01 n'est plus" \
    "monté : /mnt/sonde est vide et « sudo rbd device map --id sonde rbd-test/sonde » échoue." \
    "Le compte client.sonde n'a pas changé depuis des semaines, paraît-il. Remonte le volume" \
    "(sans recréer l'image ni le compte : les données de l'image doivent rester intactes)." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 08 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 08 E39 3 "$@"; }
fi
