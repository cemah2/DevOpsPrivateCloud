# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M08-E40 « Panne : le S3 de Ceph répond en erreur »
#
# Témoin : utilisateur RGW sonde-s3, compartiment « sonde », lu par la sonde de cephcli01 à travers
# https://rgw.par1.medisphere.internal (VIP 10.10.30.200, service ingress de cephadm).
# Variantes :
#   1. démons haproxy du service ingress arrêtés (tous) → plus rien n'écoute derrière la VIP
#      (keepalived la retire ou la garde selon son contrôle : refus ou délai dépassé côté client) ;
#   2. démons RGW arrêtés (tous) et leurs unités masquées → haproxy répond 503 ;
#   3. horloge de cephcli01 avancée de 20 min (chronyd arrêté) → 403 RequestTimeTooSkewed ;
#   4. utilisateur sonde-s3 suspendu (« audit des comptes inactifs ») → 403 UserSuspended.
# Rien n'est effacé (aucune clé, aucun compartiment, aucun objet). L'annulation relance, démasque,
# resynchronise, réactive — seulement ce qui porte encore la panne.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m08-commun.sh
source "$WB_ROOT/modules/08-ceph/corrige/pannes/_m08-commun.sh"

# _e40_code — code HTTP d'un GET signé de l'objet témoin depuis cephcli01 (000 : pas de réponse).
_e40_code() {
  m08_wb_exec "$_M08_CLIENT" RGW="$_M08_RGW_FQDN" 2>/dev/null <<'EOF' || true
curl -s -o /dev/null -w '%{http_code}' --max-time 15 -K /etc/workbook/sonde-s3.curl "https://$RGW/sonde/temoin"
EOF
}
_e40_en_erreur() { [[ "$(_e40_code)" != 200 ]]; }

_e40_rgwadm() {
  local a
  a="$(printf '%q ' "$@")"
  m08_admin A="$a" <<'EOF'
ceph_sh "radosgw-admin $A"
EOF
}
_e40_suspendu() {
  [[ "$(_e40_rgwadm user info --uid=sonde-s3 2>/dev/null | jq -r '.suspended')" == 1 ]]
}

# _e40_arreter_type TYPE [masquer] — arrête tous les démons cephadm de ce type ; mémorise la liste.
_e40_arreter_type() {
  local h d liste
  liste="$(m08_demons "$1" 2>/dev/null)"
  [[ -n "$liste" ]] || return 10
  m08_ecrire E40 demons "$liste"
  while read -r h d; do
    [[ -n "$d" ]] || continue
    m08_arreter "$h" "$d" "${2:-}" >/dev/null || return 1
  done <<<"$liste"
}

_mE40_une() {
  local n="$1" rc=0
  m08_temoins_s3 || { wb_avert "RGW absent ou témoin S3 non créé (M08-E11)"; return 1; }
  case "$n" in
    1) _e40_arreter_type haproxy || rc=$? ;;
    2) _e40_arreter_type rgw masquer || rc=$? ;;
    3)
      m08_wb_exec "$_M08_CLIENT" >/dev/null <<'EOF' || rc=$?
c=""
for s in chrony chronyd systemd-timesyncd; do
  if systemctl is-active -q "$s"; then c="$s"; break; fi
done
[ -n "$c" ] || exit 10
systemctl stop "$c"
echo "$c" >"$WB_DIR/M08-E40.temps"
date -s "@$(( $(date +%s) + 1200 ))" >/dev/null
journal "$c arrêté, horloge avancée de 20 min"
EOF
      ;;
    4)
      _e40_suspendu && return 10
      _e40_rgwadm user suspend --uid=sonde-s3 >/dev/null 2>&1 || return 1
      m08_ecrire E40 suspendu 1
      ;;
  esac
  if ((rc != 0)); then
    _e40_defaire "$n"
    return "$rc"
  fi
  if ! m08_attendre 60 _e40_en_erreur; then
    _e40_defaire "$n"
    return 10
  fi
  m08_journal E40 "variante $n posée"
}

# _e40_defaire N — retire la variante N si elle est encore en place.
_e40_defaire() {
  local h d
  case "$1" in
    1 | 2)
      while read -r h d; do
        [[ -n "${d:-}" ]] || continue
        m08_relancer "$h" "$d" >/dev/null
      done <<<"$(m08_lire E40 demons)"
      ;;
    3)
      m08_wb_exec "$_M08_CLIENT" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur cephcli01 (horloge)"
f="$WB_DIR/M08-E40.temps"
[ -f "$f" ] || exit 0
c="$(cat "$f")"
if ! systemctl is-active -q "$c"; then
  systemctl start "$c"
  sleep 5
  if [ "$c" != systemd-timesyncd ]; then chronyc -a makestep >/dev/null 2>&1 || true; fi
  journal "annulation : $c relancé, horloge resynchronisée"
fi
rm -f "$f"
EOF
      ;;
    4)
      if [[ "$(m08_lire E40 suspendu)" == 1 ]] && _e40_suspendu; then
        _e40_rgwadm user enable --uid=sonde-s3 >/dev/null 2>&1 || wb_avert "annulation : sonde-s3 toujours suspendu"
      fi
      ;;
  esac
}

_e40_injecter() {
  m08_preparer || return 1
  m08_essayer E40 4 "$1"
}

panne_E40_v1() { _e40_injecter 1; }
panne_E40_v2() { _e40_injecter 2; }
panne_E40_v3() { _e40_injecter 3; }
panne_E40_v4() { _e40_injecter 4; }

verifier_E40() { _e40_en_erreur; }

annuler_E40() {
  case "${WB_VAR:-}" in
    1 | 2 | 3 | 4) _e40_defaire "$WB_VAR" ;;
    *) _e40_defaire 4; _e40_defaire 3; _e40_defaire 1 ;;
  esac
  m08_journal E40 "annulation"
  rm -rf -- "$(m08_etat E40)"
}

resume_E40() {
  echo "La sonde S3 de MédiDoc (rgw.par1.medisphere.internal) est rouge depuis cephcli01."
}

symptome_E40() {
  wb_symptome "Ticket INC-3546 — De : Julien Petit (pour l'équipe MédiDoc)" \
    "Les essais d'intégration de MédiDoc contre le S3 de Ceph échouent depuis ce matin. La sonde" \
    "de cephcli01 le confirme (« sudo wb-sonde-stockage », lignes S3) : le message d'erreur est" \
    "dans sa sortie. Le S3 du socle (s3-01) fonctionne, lui. Rien n'a été déployé côté MédiDoc." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 08 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 08 E40 4 "$@"; }
fi
