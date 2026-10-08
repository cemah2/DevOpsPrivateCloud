# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M10-E36 « Panne : l'IP flottante ne répond pas »
#
# Préparation : une pile sonde m10-e36-* (projet plateforme : réseau 172.30.36.0/24, routeur vers
# ext-net, groupe de sécurité ICMP + SSH depuis MGMT, port, IP flottante, instance m10-e36-sonde) ;
# elle doit répondre au ping et en SSH depuis adm01 AVANT l'injection.
# Variantes :
#   1. le port de l'instance passe dans un groupe de sécurité « m10-e36-durci » sans règle d'entrée
#      (« durcissement » d'un collègue) ;
#   2. osctl01 : external_ids:ovn-bridge-mappings de l'Open vSwitch local réécrit « physnet-ext:br-ex »
#      (« renommage du réseau physique ») → le port localnet de physnet1 n'est plus relié à br-ex ;
#   3. osctl01 : l'interface physique du réseau externe (neutron_external_interface) retirée de br-ex ;
#   4. osctl01 : cette même interface mise administrativement DOWN.
# Les variantes 2 à 4 cassent le chemin nord-sud pour tout le cloud (la passerelle OVN est osctl01).
# Sauvegardes : /var/lib/workbook/M10-E36.* sur osctl01 (valeur d'origine des correspondances,
# nom de l'interface). --annuler rétablit ce qui est encore cassé ET supprime la pile sonde.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m10-commun.sh
source "$WB_ROOT/modules/10-openstack/corrige/pannes/_m10-commun.sh"

_e36_joignable() {
  local ip
  ip="$(m10_lire E36 fip)"
  [[ -n "$ip" ]] && m10_ping "$ip"
}

_e36_precondition() {
  local ip
  m10_prerequis || return 1
  if ! m10_os network show ext-net -f value -c id >/dev/null 2>&1; then
    wb_avert "réseau externe ext-net introuvable (M10-E08/E12)"
    return 1
  fi
  m10_pile_detruire E36
  echo "Création de l'instance de test (2 à 4 minutes)…"
  if ! m10_pile_creer E36 || ! m10_pile_serveur E36 m10-e36-sonde; then
    wb_avert "impossible de créer la pile de test (quotas du projet plateforme ? lab/bin/check 10 12)"
    return 1
  fi
  ip="$(m10_lire E36 fip)"
  if ! m10_attendre 240 m10_ssh_sonde "$ip"; then
    wb_avert "l'instance de test ($ip) ne répond pas en SSH avant la panne : le réseau externe n'est pas sain"
    return 1
  fi
}

_mE36_une() {
  local n="$1" rc=0
  case "$n" in
    1)
      m10_osp security group create --description "Durcissement MédiAgenda" m10-e36-durci >/dev/null || return 1
      m10_osp port set --no-security-group --security-group m10-e36-durci m10-e36-port >/dev/null || return 1
      m10_journal E36 "port m10-e36-port : groupe m10-e36-durci (aucune règle d'entrée)"
      ;;
    2 | 3 | 4)
      m10_exec "$_M10_CTL" VARIANTE="$n" >/dev/null <<'EOF' || rc=$?
ctr_actif openvswitch_vswitchd || exit 10
corr="$(ovs get open . external_ids:ovn-bridge-mappings 2>/dev/null | tr -d '"')"
# physnet1:br-ex (ou plusieurs couples séparés par des virgules)
pont="$(printf '%s' "$corr" | tr ',' '\n' | sed -n 's/^physnet1:\(.*\)$/\1/p' | head -n 1)"
[ -n "$pont" ] || exit 10
itf="$(ovs list-ports "$pont" 2>/dev/null | grep -v '^patch-' | head -n 1)"
case "$VARIANTE" in
  2)
    [ -f "$WB_DIR/M10-E36.correspondances" ] || printf '%s\n' "$corr" >"$WB_DIR/M10-E36.correspondances"
    ovs set open . "external_ids:ovn-bridge-mappings=\"physnet-ext:$pont\"" || exit 1
    journal "ovn-bridge-mappings : « $corr » → « physnet-ext:$pont »"
    ;;
  3)
    [ -n "$itf" ] || exit 10
    printf '%s\t%s\n' "$pont" "$itf" >"$WB_DIR/M10-E36.port"
    ovs del-port "$pont" "$itf" || exit 1
    journal "port $itf retiré du pont $pont"
    ;;
  4)
    [ -n "$itf" ] || exit 10
    ip link show "$itf" >/dev/null 2>&1 || exit 10
    printf '%s\n' "$itf" >"$WB_DIR/M10-E36.lien"
    ip link set "$itf" down || exit 1
    journal "interface $itf mise DOWN"
    ;;
esac
EOF
      ;;
  esac
  ((rc == 0)) || return "$rc"
  sleep 10
  # Constat : trois essais espacés ; un seul ping qui passe = variante sans effet.
  local i
  for i in 1 2 3; do
    if _e36_joignable; then
      _e36_defaire "$n"
      return 10
    fi
    sleep 5
  done
}

# _e36_defaire N — retire la variante N (sans toucher à la pile sonde).
_e36_defaire() {
  case "$1" in
    1)
      if [[ "$(m10_osp port show m10-e36-port -f json 2>/dev/null | jq -r '.security_group_ids | length')" == 1 ]] \
        && m10_osp port show m10-e36-port -f json 2>/dev/null | jq -e --arg d "$(m10_osp security group show m10-e36-durci -f value -c id 2>/dev/null)" '.security_group_ids[0] == $d' >/dev/null 2>&1; then
        m10_osp port set --no-security-group --security-group m10-e36-sg m10-e36-port >/dev/null 2>&1 || true
        m10_journal E36 "annulation : port m10-e36-port remis dans m10-e36-sg"
      fi
      m10_osp security group delete m10-e36-durci >/dev/null 2>&1 || true
      ;;
    2 | 3 | 4)
      m10_exec "$_M10_CTL" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur osctl01 (Open vSwitch / interface externe)"
f="$WB_DIR/M10-E36.correspondances"
if [ -f "$f" ]; then
  orig="$(cat "$f")"
  cour="$(ovs get open . external_ids:ovn-bridge-mappings 2>/dev/null | tr -d '"')"
  case "$cour" in
    physnet-ext:*) ovs set open . "external_ids:ovn-bridge-mappings=\"$orig\"" && journal "annulation : ovn-bridge-mappings rétabli ($orig)" ;;
    *) journal "annulation : ovn-bridge-mappings déjà corrigé ($cour), laissé tel quel" ;;
  esac
  rm -f "$f"
fi
f="$WB_DIR/M10-E36.port"
if [ -f "$f" ]; then
  IFS="$(printf '\t')" read -r pont itf <"$f"
  if ovs port-to-br "$itf" >/dev/null 2>&1; then
    journal "annulation : $itf déjà rattaché à un pont (réparation), laissé tel quel"
  else
    ovs --may-exist add-port "$pont" "$itf" && journal "annulation : $itf remis dans $pont"
  fi
  rm -f "$f"
fi
f="$WB_DIR/M10-E36.lien"
if [ -f "$f" ]; then
  itf="$(cat "$f")"
  if ip -br link show "$itf" 2>/dev/null | grep -qw DOWN; then
    ip link set "$itf" up && journal "annulation : interface $itf remise UP"
  else
    journal "annulation : interface $itf déjà UP (réparation)"
  fi
  rm -f "$f"
fi
EOF
      ;;
  esac
}

_e36_injecter() {
  _e36_precondition || return 1
  m10_essayer E36 4 "$1"
}

panne_E36_v1() { _e36_injecter 1; }
panne_E36_v2() { _e36_injecter 2; }
panne_E36_v3() { _e36_injecter 3; }
panne_E36_v4() { _e36_injecter 4; }

verifier_E36() {
  sleep 5
  ! _e36_joignable
}

annuler_E36() {
  case "${WB_VAR:-}" in
    1) _e36_defaire 1 ;;
    *) _e36_defaire 2; _e36_defaire 1 ;;
  esac
  m10_pile_detruire E36
}

resume_E36() {
  echo "L'instance de test m10-e36-sonde ne répond plus sur son IP flottante $(m10_lire E36 fip) (ni ping ni SSH depuis adm01)."
}

symptome_E36() {
  wb_symptome "Ticket INC-3742 — De : Julien Petit" \
    "Mes instances de recette ne répondent plus sur leur IP flottante depuis le réseau de" \
    "l'entreprise : ni ping, ni SSH, ni HTTP. Elles tournent (ACTIVE) et la console montre un" \
    "système démarré. Pour reproduire, une instance de test vient d'être créée dans le projet" \
    "plateforme : m10-e36-sonde, IP flottante $(m10_lire E36 fip), utilisateur debian, clé SSH" \
    "dans le dossier M10-sonde de ~/.local/state/workbook/. Elle répondait il y a cinq minutes." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 10 36 (avant --annuler, qui supprime la sonde)"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 10 E36 4 "$@"; }
fi
