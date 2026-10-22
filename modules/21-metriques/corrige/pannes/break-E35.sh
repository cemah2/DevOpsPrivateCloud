# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres yq et scripts distants entre apostrophes
# break-E35.sh — M21-E35 « Panne : une cible a disparu »
#
# Variantes :
#   1. MR de Lucas dans mediagenda/deploiement : le port du ServiceMonitor « mediagenda » (composant
#      components/supervision) renommé (« harmonisation avec le chart ») : plus aucun port ne
#      correspond, les cibles disparaissent en dev et en recette (prod n'est pas synchronisée) ;
#   2. même fichier : la valeur de l'étiquette de sélection du ServiceMonitor « normalisée »
#      (oui → true) : Prometheus ne le retient plus, les cibles disparaissent ;
#   3. CiliumNetworkPolicy « durcissement-recette » posée à la main dans mediagenda-recette : refus
#      (ingressDeny) de tout ce qui vient de l'espace supervision, sans refus par défaut : l'application
#      répond, la collecte expire (up == 0) ;
#   4. sur une VM du socle (WB_M21_VMS_PANNE, défaut nbx01 dns02 runner01) : certificat TLS de
#      node_exporter remplacé par un certificat autosigné (« renouvelé à la main ») : x509 côté
#      Prometheus ;
#   5. même VM : table nftables « durcissement_exportateurs » qui jette le 9100 venant du VLAN 40 et
#      des pods : délai dépassé à la collecte.
# Annulation seulement si la marque de la panne est encore là (MR inverse, empreinte du certificat,
# annotation de la politique, table nftables).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m21-commun.sh
source "$WB_ROOT/modules/21-metriques/corrige/pannes/_m21-commun.sh"

_E35_REQ_RECETTE='up{namespace="mediagenda-recette",service=~"mediagenda.*"}'
_E35_PORT_ORIG=""
_E35_PORT_NEUF=""
_E35_CLE=""
_E35_VAL_ORIG=""
_E35_VAL_NEUF=""

_e35_cibles_absentes() { [[ "$(m21_prom_nb "$_E35_REQ_RECETTE")" == 0 ]]; }
_e35_cibles_muettes() {
  [[ "$(m21_prom_nb "$_E35_REQ_RECETTE")" -gt 0 ]] && [[ "$(m21_prom_valeur "max($_E35_REQ_RECETTE)")" == 0 ]]
}
_e35_vm_req() {
  local vm="$1" ip
  ip="$(getent hosts "$vm.par1.medisphere.internal" 2>/dev/null | awk '{print $1; exit}')"
  # Job « vms » (ScrapeConfig de M21-E08) : instance = nom court ; repli sur le nom complet ou l'adresse.
  printf 'up{job="vms",instance=~"%s([.:].*)?%s"}' "$vm" "${ip:+|${ip//./[.]}(:.*)?}"
}
_e35_vm_muette() { [[ "$(m21_prom_valeur "max($(_e35_vm_req "$1"))")" == 0 ]]; }
_e35_vm_vue() { [[ "$(m21_prom_valeur "min($(_e35_vm_req "$1"))")" == 1 ]]; }

# Transformations du ServiceMonitor (entrée → sortie), et leurs inverses.
_e35_t_port() { P="$_E35_PORT_NEUF" yq '(select(.kind == "ServiceMonitor") | .spec.endpoints[] | select(has("port")) | .port) = strenv(P)'; }
_e35_i_port() { A="$_E35_PORT_NEUF" P="$_E35_PORT_ORIG" yq '(select(.kind == "ServiceMonitor") | .spec.endpoints[] | select(.port == strenv(A)) | .port) = strenv(P)'; }
_e35_t_etiq() { K="$_E35_CLE" V="$_E35_VAL_NEUF" yq '(select(.kind == "ServiceMonitor") | .metadata.labels[strenv(K)]) = strenv(V)'; }
_e35_i_etiq() {
  K="$_E35_CLE" A="$_E35_VAL_NEUF" V="$_E35_VAL_ORIG" \
    yq '(select(.kind == "ServiceMonitor" and .metadata.labels[strenv(K)] == strenv(A)) | .metadata.labels[strenv(K)]) = strenv(V)'
}

_e35_politique() {
  cat <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: durcissement-recette
  namespace: mediagenda-recette
  labels: {app.kubernetes.io/part-of: securite}
  annotations: {medisphere.internal/ticket: SEC-2235, medisphere.internal/auteur: lucas.martin}
spec:
  description: "SEC-2235 : en recette, MédiAgenda ne reçoit que le trafic applicatif (Lucas)"
  endpointSelector: {matchLabels: {app.kubernetes.io/name: mediagenda}}
  enableDefaultDeny: {ingress: false, egress: false}
  ingressDeny:
    - fromEndpoints: [{matchLabels: {"k8s:io.kubernetes.pod.namespace": supervision}}]
EOF
}

_m21E35_une() {
  local n="$1" f vm rc
  m21_ecrire E35 variante "$n"
  case "$n" in
    1 | 2)
      [[ "$(m21_prom_nb "$_E35_REQ_RECETTE")" -gt 0 ]] || return 10
      f="$(m21_git_trouver "$_M21_PROJ_DEP" '.kind == "ServiceMonitor"' components/supervision)" ||
        f="$(m21_git_trouver "$_M21_PROJ_DEP" '.kind == "ServiceMonitor"')" || return 10
      if ((n == 1)); then
        _E35_PORT_ORIG="$(m21_git_lire "$_M21_PROJ_DEP" "$f" | yq 'select(.kind == "ServiceMonitor") | .spec.endpoints[0].port // ""' | head -n 1)"
        [[ -n "$_E35_PORT_ORIG" && "$_E35_PORT_ORIG" != null ]] || return 10
        _E35_PORT_NEUF=metriques
        [[ "$_E35_PORT_ORIG" == metriques ]] && _E35_PORT_NEUF=metrics
        m21_ecrire E35 port "$_E35_PORT_ORIG $_E35_PORT_NEUF"
        m21_git_transformer E35 sm "$_M21_PROJ_DEP" "$f" \
          "refactor(supervision): port du ServiceMonitor aligné sur le chart (M21-E35)" _e35_t_port || return
      else
        _E35_CLE="$(m21_etiquettes_objet serviceMonitorSelector | jq -r 'keys[0]')"
        _E35_VAL_ORIG="$(m21_git_lire "$_M21_PROJ_DEP" "$f" | K="$_E35_CLE" yq 'select(.kind == "ServiceMonitor") | .metadata.labels[strenv(K)] // ""' | head -n 1)"
        [[ -n "$_E35_VAL_ORIG" && "$_E35_VAL_ORIG" != null ]] || return 10
        _E35_VAL_NEUF=true
        [[ "$_E35_VAL_ORIG" == true ]] && _E35_VAL_NEUF=oui
        m21_ecrire E35 etiquette "$_E35_CLE $_E35_VAL_ORIG $_E35_VAL_NEUF"
        m21_git_transformer E35 sm "$_M21_PROJ_DEP" "$f" \
          "style(supervision): étiquettes booléennes normalisées (M21-E35)" _e35_t_etiq || return
      fi
      m21_journal E35 "variante $n posée ($f)"
      m21_attendre 300 _e35_cibles_absentes || { _e35_defaire "$n"; return 10; }
      ;;
    3)
      [[ "$(m21_prom_valeur "min($_E35_REQ_RECETTE)")" == 1 ]] || return 10
      wb_kubectl -n mediagenda-recette get pods -l app.kubernetes.io/name=mediagenda -o name 2>/dev/null | grep -q . || return 10
      _e35_politique | wb_kubectl apply -f - >/dev/null || return 10
      m21_journal E35 "variante 3 : CiliumNetworkPolicy durcissement-recette posée"
      m21_attendre 240 _e35_cibles_muettes || { _e35_defaire 3; return 10; }
      ;;
    4 | 5)
      vm="$(m21_lire E35 vm)"
      if [[ -z "$vm" ]]; then
        for vm in $(printf '%s\n' "${_M21_VMS[@]}" | shuf); do
          _e35_vm_vue "$vm" && break
          vm=""
        done
        [[ -n "$vm" ]] || return 10
        m21_ecrire E35 vm "$vm"
      fi
      rc=0
      if ((n == 4)); then
        m21_wb_exec "$vm" >/dev/null <<'EOF' || rc=$?
u="$(unite_de node_exporter)" || exit 10
wc="$(option_de "$u" web.config.file)"
[ -n "$wc" ] && [ -f "$wc" ] || exit 10
champ() { sed -n "s/^[[:space:]]*$1:[[:space:]]*[\"']\{0,1\}\([^\"' ]*\).*/\1/p" "$wc" | head -n 1; }
cert="$(champ cert_file)"; cle="$(champ key_file)"
[ -n "$cert" ] && [ -n "$cle" ] || exit 10
cert="$(readlink -f "$cert")"; cle="$(readlink -f "$cle")"
[ -f "$cert" ] && [ -f "$cle" ] || exit 10
command -v openssl >/dev/null || exit 10
t="$(mktemp -d)"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 \
  -subj "/CN=$(hostname -f)" -addext "subjectAltName=DNS:$(hostname -f),DNS:$(hostname -s)" \
  -keyout "$t/cle" -out "$t/cert" >/dev/null 2>&1 || { rm -rf "$t"; exit 1; }
sauver "$cert"; sauver "$cle"
cat "$t/cle" > "$cle"; cat "$t/cert" > "$cert"
rm -rf "$t"
openssl x509 -noout -fingerprint -sha256 -in "$cert" | cut -d= -f2 > "$WB_DIR/$WB_EX.empreinte"
journal "certificat de node_exporter remplacé par un certificat autosigné : $cert"
EOF
      else
        m21_wb_exec "$vm" >/dev/null <<'EOF' || rc=$?
command -v nft >/dev/null || exit 10
nft list table inet durcissement_exportateurs >/dev/null 2>&1 && exit 10
nft -f - <<'NFT' || exit 1
table inet durcissement_exportateurs {
  chain entree {
    type filter hook input priority -10; policy accept;
    ip saddr { 10.10.40.0/24, 10.240.0.0/16 } tcp dport 9100 counter drop comment "PLAT-2235 exportateurs : MGMT seulement (Lucas)"
  }
}
NFT
journal "table nftables durcissement_exportateurs ajoutée (9100 refusé depuis le VLAN 40 et les pods)"
EOF
      fi
      ((rc == 0)) || { _e35_defaire "$n"; return "$rc"; }
      m21_journal E35 "variante $n posée sur $vm"
      m21_attendre 240 _e35_vm_muette "$vm" || { _e35_defaire "$n"; return 10; }
      ;;
  esac
}

_e35_charger() {
  read -r _E35_PORT_ORIG _E35_PORT_NEUF <<<"$(m21_lire E35 port)"
  read -r _E35_CLE _E35_VAL_ORIG _E35_VAL_NEUF <<<"$(m21_lire E35 etiquette)"
}

_e35_defaire() {
  local n="$1" vm p
  _e35_charger
  case "$n" in
    1)
      [[ -n "$_E35_PORT_NEUF" ]] && m21_git_defaire E35 sm _e35_i_port "revert(supervision): port du ServiceMonitor rétabli (M21-E35, annulation)"
      m21_oublier E35 port
      ;;
    2)
      [[ -n "$_E35_CLE" ]] && m21_git_defaire E35 sm _e35_i_etiq "revert(supervision): étiquette de sélection rétablie (M21-E35, annulation)"
      m21_oublier E35 etiquette
      ;;
    3)
      p="$(wb_kubectl -n mediagenda-recette get ciliumnetworkpolicies.cilium.io durcissement-recette -o json 2>/dev/null)" || p=""
      if jq -e '.metadata.annotations["medisphere.internal/auteur"] == "lucas.martin"' >/dev/null 2>&1 <<<"$p"; then
        wb_kubectl -n mediagenda-recette delete ciliumnetworkpolicies.cilium.io durcissement-recette >/dev/null 2>&1 || true
      fi
      ;;
    4)
      vm="$(m21_lire E35 vm)"
      [[ -n "$vm" ]] || return 0
      m21_wb_exec "$vm" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $vm (certificat de node_exporter)"
[ -f "$WB_DIR/$WB_EX.empreinte" ] || exit 0
e="$(cat "$WB_DIR/$WB_EX.empreinte")"
u="$(unite_de node_exporter)" || u=""
wc="$( [ -n "$u" ] && option_de "$u" web.config.file)"
cert="$(sed -n "s/^[[:space:]]*cert_file:[[:space:]]*[\"']\{0,1\}\([^\"' ]*\).*/\1/p" "${wc:-/dev/null}" 2>/dev/null | head -n 1)"
if [ -n "$cert" ] && [ "$(openssl x509 -noout -fingerprint -sha256 -in "$(readlink -f "$cert")" 2>/dev/null | cut -d= -f2)" = "$e" ]; then
  restaurer_fichiers; journal "annulation : certificat et clé de node_exporter rétablis"
else
  oublier_fichiers
fi
rm -f "$WB_DIR/$WB_EX.empreinte"
EOF
      ;;
    5)
      vm="$(m21_lire E35 vm)"
      [[ -n "$vm" ]] || return 0
      m21_wb_exec "$vm" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $vm (nftables)"
if nft list table inet durcissement_exportateurs >/dev/null 2>&1; then
  nft delete table inet durcissement_exportateurs && journal "annulation : table durcissement_exportateurs retirée"
fi
EOF
      ;;
  esac
}

panne_E35_v1() { m21_preparer && m21_essayer E35 5 1; }
panne_E35_v2() { m21_preparer && m21_essayer E35 5 2; }
panne_E35_v3() { m21_preparer && m21_essayer E35 5 3; }
panne_E35_v4() { m21_preparer && m21_essayer E35 5 4; }
panne_E35_v5() { m21_preparer && m21_essayer E35 5 5; }

verifier_E35() {
  case "$WB_VAR" in
    1 | 2) _e35_cibles_absentes ;;
    3) _e35_cibles_muettes ;;
    *) _e35_vm_muette "$(m21_lire E35 vm)" ;;
  esac
}

annuler_E35() {
  local v="${WB_VAR:-}"
  [[ "$v" =~ ^[1-5]$ ]] || v="$(m21_lire E35 variante)"
  [[ -n "$v" ]] && _e35_defaire "$v"
  m21_oublier E35 variante
  m21_oublier E35 vm
  m21_journal E35 "annulation"
}

resume_E35() {
  case "${WB_VAR:-}" in
    4 | 5) echo "Le tableau des nœuds n'a plus aucune courbe pour $(m21_lire E35 vm), qui répond pourtant en SSH." ;;
    *) echo "Le tableau RED de MédiAgenda est vide pour la recette depuis la dernière heure." ;;
  esac
}

symptome_E35() {
  case "${WB_VAR:-}" in
    4 | 5)
      wb_symptome "Ticket INC-4835 — De : Nadia Roussel" \
        "Le tableau USE des machines n'a plus aucune courbe pour $(m21_lire E35 vm) depuis une dizaine" \
        "de minutes. La machine va bien : je m'y connecte en SSH, ses services répondent. Lucas a" \
        "« durci des choses » sur quelques VMs du socle cette semaine. Je veux revoir ses courbes," \
        "et savoir pourquoi aucune alerte ne m'a prévenue que je ne la voyais plus." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 21 35"
      ;;
    *)
      wb_symptome "Ticket INC-4835 — De : Julien Petit" \
        "Le tableau RED de MédiAgenda est vide pour la recette depuis tout à l'heure (et peut-être" \
        "pour le dev). L'application marche, nos tests de recette passent. Prometheus ne doit plus" \
        "nous voir : on a besoin de ces courbes pour l'analyse canary de cet après-midi." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 21 35"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 21 E35 5 "$@"; }
fi
