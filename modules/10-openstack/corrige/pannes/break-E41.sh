# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M10-E41 « Panne : l'envoi d'image échoue »
#
# Variantes :
#   1. osctl01 : glance-api.conf (/etc/kolla/glance-api/glance-api.conf, hors du code) reçoit
#      image_size_cap = 104857600 (100 Mio), glance_api redémarré → 413 au-delà de 100 Mio ;
#   2. ceph-par1 (par ceph01) : quota max_bytes du pool images fixé à son occupation actuelle →
#      pool plein (POOL_FULL), les écritures de Glance sont suspendues ou refusées ;
#   3. osctl01 : clé du trousseau ceph.client.glance.keyring de glance-api remplacée par une clé
#      cephx valide mais inconnue du cluster, glance_api redémarré → Ceph refuse Glance.
# Constat : l'envoi d'un fichier de 200 Mio (image raw de test m10-e41-sonde, projet plateforme)
# n'aboutit pas en 3 minutes. Les images de test sont supprimées à l'annulation.
# Sauvegardes : /var/lib/workbook/M10-E41.* sur osctl01 ou ceph01. Rien n'est rétabli qui a déjà
# été réparé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m10-commun.sh
source "$WB_ROOT/modules/10-openstack/corrige/pannes/_m10-commun.sh"

_e41_fichier() {
  local f
  f="$(m10_etat E41)/sonde-200M.raw"
  if [[ ! -f "$f" ]]; then
    head -c 200M /dev/urandom >"$f" || return 1
  fi
  printf '%s\n' "$f"
}

# _e41_envoi — 0 si l'image de test devient « active » en moins de 3 minutes.
_e41_envoi() {
  local f st
  f="$(_e41_fichier)" || return 1
  timeout 180 openstack --os-cloud "$_M10_CLOUD_PROJET" image create --disk-format raw \
    --container-format bare --private --file "$f" m10-e41-sonde </dev/null >/dev/null 2>&1 || true
  st="$(m10_osp image list --name m10-e41-sonde --long -f json 2>/dev/null | jq -r '[.[].Status] | first // empty')"
  [[ "$st" == active ]]
}

_e41_nettoyer() {
  local id
  for id in $(m10_os image list --all --name m10-e41-sonde -f value -c ID 2>/dev/null); do
    m10_os image delete "$id" >/dev/null 2>&1 || true
  done
}

_e41_precondition() {
  m10_prerequis || return 1
  if ! m10_os image list --limit 1 >/dev/null 2>&1; then
    wb_avert "Glance ne répond pas avant la panne : lab/bin/check 10 41"
    return 1
  fi
  _e41_nettoyer
}

_mE41_une() {
  local n="$1" rc=0
  case "$n" in
    1 | 3)
      m10_exec "$_M10_CTL" VARIANTE="$n" >/dev/null <<'EOF' || rc=$?
case "$VARIANTE" in
  1)
    f=/etc/kolla/glance-api/glance-api.conf
    [ -f "$f" ] || exit 10
    subst "$f" '^\[DEFAULT\][ \t]*\n' '[DEFAULT]\nimage_size_cap = 104857600\n' || exit $?
    ;;
  3)
    f=/etc/kolla/glance-api/ceph/ceph.client.glance.keyring
    [ -f "$f" ] || exit 10
    subst "$f" '^([ \t]*key[ \t]*=[ \t]*)\S+' "\\g<1>$(cle_cephx_bidon)" || exit $?
    ;;
esac
ctr_redemarrer glance_api || exit 1
journal "$f modifié, glance_api redémarré"
EOF
      ((rc != 0)) || sleep 20
      ;;
    2)
      m10_exec "$_M10_CEPH" >/dev/null <<'EOF' || rc=$?
q="$(ceph osd pool get-quota images -f json 2>/dev/null)" || exit 10
[ -n "$q" ] || exit 10
orig="$(printf '%s' "$q" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("quota_max_bytes", 0))')"
occ="$(ceph df -f json | python3 -c '
import json, sys
for p in json.load(sys.stdin)["pools"]:
    if p["name"] == "images":
        print(max(int(p["stats"].get("stored", 0)), 1048576))')"
[ -n "$occ" ] || exit 10
[ -f "$WB_DIR/M10-E41.quota" ] || printf '%s\n' "$orig" >"$WB_DIR/M10-E41.quota"
printf '%s\n' "$occ" >"$WB_DIR/M10-E41.quota-pose"
ceph osd pool set-quota images max_bytes "$occ" >/dev/null 2>&1 || exit 1
journal "quota max_bytes du pool images : $orig → $occ"
# Le drapeau « full » est posé par les moniteurs à la prochaine mise à jour des statistiques.
i=0
while [ $i -lt 24 ]; do
  ceph health detail 2>/dev/null | grep -q "pool 'images'.*quota" && exit 0
  i=$((i + 1)); sleep 5
done
exit 0
EOF
      ;;
  esac
  ((rc == 0)) || return "$rc"
  echo "Envoi d'une image de test de 200 Mio (jusqu'à 3 minutes)…"
  if _e41_envoi; then
    _e41_defaire "$n"
    _e41_nettoyer
    return 10
  fi
}

_e41_defaire() {
  case "$1" in
    1 | 3)
      m10_exec "$_M10_CTL" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur osctl01 (glance-api)"
if [ -n "$(defaire_subst)" ]; then ctr_redemarrer glance_api; fi
EOF
      ;;
    2)
      m10_exec "$_M10_CEPH" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur ceph-par1 (quota du pool images)"
f="$WB_DIR/M10-E41.quota"
[ -f "$f" ] || exit 0
cour="$(ceph osd pool get-quota images -f json 2>/dev/null | python3 -c 'import json, sys; print(json.load(sys.stdin).get("quota_max_bytes", 0))')"
if [ "$cour" = "$(cat "$WB_DIR/M10-E41.quota-pose" 2>/dev/null)" ]; then
  ceph osd pool set-quota images max_bytes "$(cat "$f")" >/dev/null 2>&1 && journal "annulation : quota du pool images rétabli ($(cat "$f"))"
else
  journal "annulation : quota du pool images déjà modifié ($cour), laissé tel quel"
fi
rm -f "$f" "$WB_DIR/M10-E41.quota-pose"
EOF
      ;;
  esac
}

_e41_injecter() {
  _e41_precondition || return 1
  m10_essayer E41 3 "$1"
}

panne_E41_v1() { _e41_injecter 1; }
panne_E41_v2() { _e41_injecter 2; }
panne_E41_v3() { _e41_injecter 3; }

# Le constat (envoi de 200 Mio en échec) est fait dans _mE41_une ; l'image de test reste visible.
verifier_E41() {
  [[ "$(m10_osp image list --name m10-e41-sonde --long -f json 2>/dev/null | jq -r '[.[].Status] | first // "absente"')" != active ]]
}

annuler_E41() {
  case "${WB_VAR:-}" in
    1 | 3) _e41_defaire 1 ;;
    2) _e41_defaire 2 ;;
    *) _e41_defaire 2; _e41_defaire 1 ;;
  esac
  _e41_nettoyer
  rm -f -- "$(m10_etat E41)/sonde-200M.raw"
}

resume_E41() {
  echo "Les envois d'image vers Glance échouent (image de test m10-e41-sonde jamais « active »)."
}

symptome_E41() {
  wb_symptome "Ticket INC-3747 — De : Julien Petit" \
    "Je n'arrive plus à envoyer d'image dans Glance : l'image reste « queued » ou « saving »," \
    "puis la commande échoue ou n'en finit pas. Les images existantes démarrent normalement." \
    "Mon essai de cette nuit : m10-e41-sonde (200 Mio, raw, projet plateforme), toujours là." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 10 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 10 E41 3 "$@"; }
fi
