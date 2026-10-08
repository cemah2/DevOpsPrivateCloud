# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M10-E38 « Panne : le volume ne s'attache pas »
#
# Préparation : dans le projet plateforme, instance m10-e38-sonde (m1.petit, sans réseau) et volume
# m10-e38-vol (1 Gio, vide), créés AVANT l'injection.
# Variantes :
#   1. calculs : la valeur du secret libvirt de client.cinder (UUID cinder_rbd_secret_uuid, usage
#      « ceph-persistent-cinder ») remplacée à chaud dans nova_libvirt par une clé cephx qui n'est
#      celle de personne (« essai de rotation de clé ») → QEMU ne s'authentifie plus auprès de Ceph ;
#   2. ceph-par1 (par ceph01) : les droits (caps) de client.cinder perdent l'accès au pool volumes ;
#   3. osctl01 : ceph.conf de cinder-volume (/etc/kolla/cinder-volume/ceph/ceph.conf) avec des
#      adresses de moniteurs fausses (10.10.30.5x → 10.10.30.1x), cinder_volume redémarré.
# Constat : « openstack server add volume m10-e38-sonde m10-e38-vol » ne mène pas à in-use.
# Sauvegardes : /var/lib/workbook/M10-E38.* sur les hôtes touchés (UUID du secret, droits d'origine
# de client.cinder, texte d'origine de ceph.conf). --annuler rétablit ce qui est encore cassé ET
# supprime l'instance et le volume de test.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m10-commun.sh
source "$WB_ROOT/modules/10-openstack/corrige/pannes/_m10-commun.sh"

_e38_statut_vol() { m10_osp volume show m10-e38-vol -f value -c status 2>/dev/null; }
_e38_disponible() { [[ "$(_e38_statut_vol)" == available ]]; }

_e38_nettoyer() {
  local st
  m10_osp server remove volume m10-e38-sonde m10-e38-vol >/dev/null 2>&1 || true
  m10_osp server delete --wait m10-e38-sonde >/dev/null 2>&1 || true
  st="$(_e38_statut_vol)"
  if [[ -n "$st" && "$st" != available && "$st" != error ]]; then
    # Volume resté « attaching »/« reserved » : remise à l'état available par l'administrateur.
    m10_os volume set --state available m10-e38-vol >/dev/null 2>&1 || true
  fi
  m10_osp volume delete m10-e38-vol >/dev/null 2>&1 || m10_os volume delete --force m10-e38-vol >/dev/null 2>&1 || true
}

_e38_precondition() {
  local img
  m10_prerequis || return 1
  if ! m10_os volume service list -f json 2>/dev/null | jq -e '[.[] | select(.Binary == "cinder-volume" and .State == "up")] | length > 0' >/dev/null; then
    wb_avert "aucun cinder-volume « up » avant la panne : lab/bin/check 10 11"
    return 1
  fi
  if ! m10_existe "$_M10_CEPH"; then
    wb_avert "$_M10_CEPH ne répond pas en SSH (ceph-par1 doit être démarré pendant le module)"
    return 1
  fi
  _e38_nettoyer
  img="$(m10_image_sonde)" || { wb_avert "image Debian 13 introuvable (M10-E06)"; return 1; }
  echo "Création de l'instance et du volume de test (1 à 3 minutes)…"
  m10_osp server create --flavor "$_M10_GABARIT" --image "$img" --no-network --wait m10-e38-sonde >/dev/null 2>&1 || {
    wb_avert "l'instance de test ne démarre pas avant la panne : lab/bin/check 10 07"
    return 1
  }
  m10_osp volume create --size 1 m10-e38-vol >/dev/null 2>&1 || return 1
  if ! m10_attendre 120 _e38_disponible; then
    wb_avert "le volume de test n'est pas « available » avant la panne : lab/bin/check 10 11"
    return 1
  fi
}

_mE38_une() {
  local n="$1" rc=0 h
  case "$n" in
    1)
      for h in "${_M10_CMP[@]}"; do
        m10_exec "$h" >/dev/null <<'EOF' || rc=$?
d=/etc/kolla/nova-libvirt/secrets
u="$(grep -l 'ceph-persistent-cinder' "$d"/*.xml 2>/dev/null | head -n 1)"
[ -n "$u" ] || exit 10
u="$(basename "$u" .xml)"
ctr_actif nova_libvirt || exit 10
printf '%s\n' "$u" >"$WB_DIR/M10-E38.secret"
cle_cephx_bidon | docker exec -i nova_libvirt sh -c 'cat > /tmp/.wb-e38 && virsh -q secret-set-value --secret "$1" --file /tmp/.wb-e38; r=$?; rm -f /tmp/.wb-e38; exit $r' _ "$u" >/dev/null || exit 1
docker exec nova_libvirt virsh -q secret-get-value "$u" </dev/null | sha256sum | cut -d' ' -f1 >"$WB_DIR/M10-E38.secret-pose"
journal "secret libvirt $u (client.cinder) remplacé à chaud dans nova_libvirt"
EOF
        ((rc == 0)) || break
      done
      ;;
    2)
      m10_exec "$_M10_CEPH" >/dev/null <<'EOF' || rc=$?
j="$(ceph auth get client.cinder -f json)" || exit 10
[ -n "$j" ] || exit 10
# Droits seuls (jamais la clé) : un fichier « type<TAB>droits » par ligne.
[ -f "$WB_DIR/M10-E38.caps" ] || printf '%s' "$j" | python3 -c '
import json, sys
e = json.load(sys.stdin)
e = e[0] if isinstance(e, list) else e
for k, v in sorted(e.get("caps", {}).items()):
    print("%s\t%s" % (k, v))' >"$WB_DIR/M10-E38.caps"
grep -q 'pool=volumes' "$WB_DIR/M10-E38.caps" || exit 10
args="$(python3 - "$WB_DIR/M10-E38.caps" <<'PY'
import shlex, sys
out = []
for l in open(sys.argv[1], encoding="utf-8"):
    k, v = l.rstrip("\n").split("\t", 1)
    if k in ("osd", "mgr"):
        v = ", ".join(p.strip() for p in v.split(",") if "pool=volumes" not in p)
    out += [k, v]
print(" ".join(shlex.quote(x) for x in out))
PY
)"
eval "set -- $args"
ceph auth caps client.cinder "$@" >/dev/null 2>&1 || exit 1
ceph auth get client.cinder -f json | python3 -c '
import json, sys
e = json.load(sys.stdin); e = e[0] if isinstance(e, list) else e
print(e["caps"].get("osd", ""))' >"$WB_DIR/M10-E38.caps-pose"
journal "droits de client.cinder : accès au pool volumes retiré"
EOF
      ;;
    3)
      m10_exec "$_M10_CTL" >/dev/null <<'EOF' || rc=$?
f=/etc/kolla/cinder-volume/ceph/ceph.conf
[ -f "$f" ] || exit 10
subst "$f" '10\.10\.30\.5([1-4])' '10.10.30.1\1' || exit $?
while subst "$f" '10\.10\.30\.5([1-4])' '10.10.30.1\1'; do :; done
ctr_redemarrer cinder_volume || exit 1
journal "$f : adresses des moniteurs modifiées, cinder_volume redémarré"
EOF
      ((rc != 0)) || sleep 20
      ;;
  esac
  ((rc == 0)) || return "$rc"
  if ! _e38_constat; then
    _e38_defaire "$n"
    m10_osp server remove volume m10-e38-sonde m10-e38-vol >/dev/null 2>&1 || true
    return 10
  fi
}

# _e38_constat — l'attachement demandé n'aboutit pas (le volume ne passe pas « in-use » en 90 s).
_e38_constat() {
  m10_osp server add volume m10-e38-sonde m10-e38-vol >/dev/null 2>&1 || return 0
  # shellcheck disable=SC2016  # $1 est évalué par le bash -c lancé à chaque essai
  ! m10_attendre 90 bash -c '[[ "$(openstack --os-cloud "$1" volume show m10-e38-vol -f value -c status 2>/dev/null)" == in-use ]]' _ "$_M10_CLOUD_PROJET"
}

_e38_defaire() {
  local h
  case "$1" in
    1)
      for h in "${_M10_CMP[@]}"; do
        m10_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (secret libvirt)"
f="$WB_DIR/M10-E38.secret"
[ -f "$f" ] || exit 0
u="$(cat "$f")"
pose="$(cat "$WB_DIR/M10-E38.secret-pose" 2>/dev/null)"
cour="$(docker exec nova_libvirt virsh -q secret-get-value "$u" </dev/null 2>/dev/null | sha256sum | cut -d' ' -f1)"
if [ -n "$pose" ] && [ "$cour" = "$pose" ]; then
  docker exec nova_libvirt virsh -q secret-set-value --secret "$u" --file "/var/lib/kolla/config_files/secrets/$u.base64" </dev/null >/dev/null \
    && journal "annulation : secret libvirt $u rétabli depuis la configuration Kolla"
else
  journal "annulation : secret libvirt $u déjà corrigé (réparation), laissé tel quel"
fi
rm -f "$f" "$WB_DIR/M10-E38.secret-pose"
EOF
      done
      ;;
    2)
      m10_exec "$_M10_CEPH" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur ceph-par1 (droits de client.cinder)"
f="$WB_DIR/M10-E38.caps"
[ -f "$f" ] || exit 0
cour="$(ceph auth get client.cinder -f json | python3 -c '
import json, sys
e = json.load(sys.stdin); e = e[0] if isinstance(e, list) else e
print(e["caps"].get("osd", ""))')"
if [ "$cour" = "$(cat "$WB_DIR/M10-E38.caps-pose" 2>/dev/null)" ]; then
  args="$(python3 - "$f" <<'PY'
import shlex, sys
out = []
for l in open(sys.argv[1], encoding="utf-8"):
    k, v = l.rstrip("\n").split("\t", 1)
    out += [k, v]
print(" ".join(shlex.quote(x) for x in out))
PY
)"
  eval "set -- $args"
  ceph auth caps client.cinder "$@" >/dev/null 2>&1 && journal "annulation : droits de client.cinder rétablis"
else
  journal "annulation : droits de client.cinder déjà modifiés (réparation), laissés tels quels"
fi
rm -f "$f" "$WB_DIR/M10-E38.caps-pose"
EOF
      ;;
    3)
      m10_exec "$_M10_CTL" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur osctl01 (ceph.conf de cinder-volume)"
if [ -n "$(defaire_subst)" ]; then ctr_redemarrer cinder_volume; fi
EOF
      ;;
  esac
}

_e38_injecter() {
  _e38_precondition || return 1
  m10_essayer E38 3 "$1"
}

panne_E38_v1() { _e38_injecter 1; }
panne_E38_v2() { _e38_injecter 2; }
panne_E38_v3() { _e38_injecter 3; }

verifier_E38() {
  [[ "$(_e38_statut_vol)" != in-use ]]
}

annuler_E38() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e38_defaire "$WB_VAR" ;;
    *) _e38_defaire 3; _e38_defaire 2; _e38_defaire 1 ;;
  esac
  _e38_nettoyer
}

resume_E38() {
  echo "Un volume ne s'attache plus à une instance (m10-e38-vol → m10-e38-sonde, projet plateforme)."
}

symptome_E38() {
  wb_symptome "Ticket INC-3744 — De : Julien Petit" \
    "Impossible d'attacher un volume à une instance : le volume passe « attaching » ou" \
    "« reserved », puis revient « available » ; l'instance n'a pas de nouveau disque. Mes" \
    "volumes déjà attachés semblent fonctionner. Pour reproduire, dans le projet plateforme :" \
    "  openstack server add volume m10-e38-sonde m10-e38-vol" \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 10 38 (avant --annuler, qui supprime la sonde)"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 10 E38 3 "$@"; }
fi
