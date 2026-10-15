# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E21.sh — M18-E21 « Panne : la machine reste en Provisioning »
#
# Cluster de gestion k3s01, espace capi-essai. La panne pose une cause, puis passe le MachineDeployment
# des travailleurs de N à N+1 (comme Karim). La nouvelle machine reste bloquée. Variantes :
#   1. JETON : le jeton Proxmox wb-capi@pve!capi reçoit une date d'expiration passée (pveum user token
#      modify --expire) : CAPMOX est refusé par l'API Proxmox, aucune VM n'est clonée ;
#   2. TEMPLATE : le template référencé par le gabarit des travailleurs (templateID, 9061 après M18-E13)
#      est retiré du pool « lab » : le jeton, limité au pool, n'a plus le droit de le cloner ;
#   3. ADRESSES : des IPAddressClaim « essai-lb-NN » (les « essais de répartiteur » de Lucas) réservent
#      toutes les adresses libres du pool capi-essai-v4-icip : la VM est clonée mais attend une adresse.
# Annulation : expiration d'origine du jeton remise (si elle vaut encore la valeur injectée), template
# remis dans le pool (s'il n'y est pas), réservations « essai-lb-* » supprimées ; puis retour au nombre
# de travailleurs d'origine, la machine ajoutée par la panne étant marquée pour suppression
# (cluster.x-k8s.io/delete-machine).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m18-commun.sh
source "$WB_ROOT/modules/18-distributions/corrige/pannes/_m18-commun.sh"

_E21_NS="$_M18_ESPACE_CAPI"
_E21_USER=wb-capi@pve
_E21_JETON=capi

_e21_md() {
  m18_gestion get machinedeployments.v1beta2.cluster.x-k8s.io -n "$_E21_NS" -o json 2>/dev/null \
    | jq -r '[.items[] | select(.spec.clusterName == "capi-essai")][0].metadata.name // empty'
}
_e21_machines() {
  m18_gestion get machines.v1beta2.cluster.x-k8s.io -n "$_E21_NS" -l "cluster.x-k8s.io/deployment-name=$1" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null
}
_e21_template() {
  local pmt
  pmt="$(m18_gestion get machinedeployments.v1beta2.cluster.x-k8s.io "$1" -n "$_E21_NS" \
    -o jsonpath='{.spec.template.spec.infrastructureRef.name}' 2>/dev/null)" || return 1
  m18_gestion get proxmoxmachinetemplates.v1alpha2.infrastructure.cluster.x-k8s.io "$pmt" -n "$_E21_NS" \
    -o jsonpath='{.spec.template.spec.templateID}' 2>/dev/null
}
_e21_pool_ip() {
  local p
  p="$(m18_gestion get proxmoxclusters.v1alpha2.infrastructure.cluster.x-k8s.io capi-essai -n "$_E21_NS" \
    -o jsonpath='{.status.inClusterIPPoolRef[0].name}' 2>/dev/null)" || p=""
  printf '%s\n' "${p:-capi-essai-v4-icip}"
}

# Machine ajoutée par la panne (absente de la liste d'origine).
_e21_nouvelle() {
  local md av m
  md="$(m18_lire E21 md)"
  av="$(m18_lire E21 avant)"
  while read -r m; do
    [[ -n "$m" ]] || continue
    grep -qxF "$m" <<<"$av" || { printf '%s\n' "$m"; return 0; }
  done < <(_e21_machines "$md")
  return 1
}
_e21_pm_de() {
  m18_gestion get machines.v1beta2.cluster.x-k8s.io "$1" -n "$_E21_NS" -o jsonpath='{.spec.infrastructureRef.name}' 2>/dev/null
}
# Bloquée sans VM : la ProxmoxMachine de la nouvelle machine n'a pas de VMID.
_e21_sans_vm() {
  local m pm vmid
  m="$(_e21_nouvelle)" || return 1
  pm="$(_e21_pm_de "$m")" || return 1
  [[ -n "$pm" ]] || return 1
  vmid="$(m18_gestion get proxmoxmachines.v1alpha2.infrastructure.cluster.x-k8s.io "$pm" -n "$_E21_NS" \
    -o jsonpath='{.spec.virtualMachineID}' 2>/dev/null)" || return 1
  [[ -z "$vmid" ]]
}
# Bloquée en attente d'adresse : condition VirtualMachineProvisioned de raison WaitingForStaticIPAllocation.
_e21_attend_ip() {
  local m pm r
  m="$(_e21_nouvelle)" || return 1
  pm="$(_e21_pm_de "$m")" || return 1
  [[ -n "$pm" ]] || return 1
  r="$(m18_gestion get proxmoxmachines.v1alpha2.infrastructure.cluster.x-k8s.io "$pm" -n "$_E21_NS" \
    -o jsonpath='{.status.conditions[?(@.type=="VirtualMachineProvisioned")].reason}' 2>/dev/null)" || return 1
  [[ "$r" == WaitingForStaticIPAllocation ]]
}

_e21_pve_json() { remote "$WB_PVE_HOST" "$1" 2>/dev/null; }

_e21_dans_pool() {
  _e21_pve_json "pvesh get /pools --poolid lab --output-format json" \
    | jq -e --argjson id "$1" '[.[]? | .members[]? | .vmid] | index($id) != null' >/dev/null 2>&1
}

_e21_monter() {
  local md="$1" n
  n="$(m18_gestion get machinedeployments.v1beta2.cluster.x-k8s.io "$md" -n "$_E21_NS" -o jsonpath='{.spec.replicas}')" || return 1
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  m18_ecrire E21 replicas "$n"
  m18_gestion scale machinedeployments.v1beta2.cluster.x-k8s.io "$md" -n "$_E21_NS" --replicas "$((n + 1))" >/dev/null || return 1
  m18_journal E21 "MachineDeployment $md : $n → $((n + 1)) réplicas"
}

_mE21_une() {
  local v="$1" md tpl exp pool libre i av
  md="$(_e21_md)" || md=""
  [[ -n "$md" ]] || { wb_avert "aucun MachineDeployment de capi-essai dans l'espace $_E21_NS"; return 1; }
  m18_ecrire E21 md "$md"
  av="$(_e21_machines "$md")"
  m18_ecrire E21 avant "$av"
  case "$v" in
    1)
      exp="$(_e21_pve_json "pveum user token list $_E21_USER --output-format json" \
        | jq -r --arg t "$_E21_JETON" '.[]? | select(.tokenid == $t) | (.expire // 0)')" || exp=""
      [[ "$exp" =~ ^[0-9]+$ ]] || return 10
      m18_ecrire E21 expire_orig "$exp"
      m18_ecrire E21 expire_faux "$(( $(date +%s) - 86400 ))"
      remote "$WB_PVE_HOST" "pveum user token modify $_E21_USER $_E21_JETON --expire $(m18_lire E21 expire_faux)" >/dev/null || return 1
      m18_journal E21 "jeton $_E21_USER!$_E21_JETON : expiration passée (ancienne valeur : $exp)"
      ;;
    2)
      tpl="$(_e21_template "$md")" || tpl=""
      [[ "$tpl" =~ ^[0-9]+$ ]] || return 10
      _e21_dans_pool "$tpl" || return 10
      m18_ecrire E21 template "$tpl"
      remote "$WB_PVE_HOST" "pveum pool modify lab --vms $tpl --delete 1" >/dev/null || return 1
      _e21_dans_pool "$tpl" && return 1
      m18_journal E21 "template $tpl retiré du pool lab"
      ;;
    3)
      pool="$(_e21_pool_ip)"
      libre="$(m18_gestion get inclusterippools.ipam.cluster.x-k8s.io "$pool" -n "$_E21_NS" \
        -o jsonpath='{.status.ipAddresses.free}' 2>/dev/null)" || libre=""
      [[ "$libre" =~ ^[0-9]+$ ]] && ((libre >= 1 && libre <= 20)) || return 10
      m18_ecrire E21 pool "$pool"
      for ((i = 1; i <= libre; i++)); do
        m18_gestion apply -f - >/dev/null <<EOF || return 1
apiVersion: ipam.cluster.x-k8s.io/v1beta2
kind: IPAddressClaim
metadata:
  name: $(printf 'essai-lb-%02d' "$i")
  namespace: $_E21_NS
spec:
  poolRef:
    apiGroup: ipam.cluster.x-k8s.io
    kind: InClusterIPPool
    name: $pool
EOF
        printf 'essai-lb-%02d\n' "$i" >>"$(m18_etat E21)/reservations"
      done
      if ! m18_attendre 90 _e21_pool_plein "$pool"; then return 1; fi
      m18_journal E21 "$libre réservations essai-lb-* sur le pool $pool"
      ;;
  esac
  m18_ecrire E21 variante "$v"
  _e21_monter "$md"
}

_e21_pool_plein() {
  [[ "$(m18_gestion get inclusterippools.ipam.cluster.x-k8s.io "$1" -n "$_E21_NS" -o jsonpath='{.status.ipAddresses.free}' 2>/dev/null)" == 0 ]]
}

_e21_sain() {
  local c
  c="$(m18_gestion get clusters.v1beta2.cluster.x-k8s.io capi-essai -n "$_E21_NS" -o json 2>/dev/null)" || return 1
  jq -e '(.spec.paused // false) == false and any(.status.conditions[]?; .type == "Available" and .status == "True")' >/dev/null <<<"$c" || return 1
  m18_gestion get machines.v1beta2.cluster.x-k8s.io -n "$_E21_NS" -l cluster.x-k8s.io/cluster-name=capi-essai -o json 2>/dev/null \
    | jq -e '(.items | length) >= 2 and all(.items[]; .status.phase == "Running")' >/dev/null
}

_e21_injecter() {
  m18_outils kubectl jq || return 1
  if ! _e21_sain; then
    wb_avert "capi-essai n'est pas sain avant la panne (Cluster Available, sans pause, toutes les machines Running : M18-E13)"
    return 1
  fi
  m18_essayer E21 3 "$1"
}

panne_E21_v1() { _e21_injecter 1; }
panne_E21_v2() { _e21_injecter 2; }
panne_E21_v3() { _e21_injecter 3; }

# La panne a pris quand la nouvelle machine est encore bloquée après 2 min 30 (un clone sain reçoit son
# VMID en quelques secondes ; une adresse libre est attribuée aussitôt).
verifier_E21() {
  sleep 150
  case "$(m18_lire E21 variante)" in
    1 | 2) _e21_sans_vm ;;
    3) _e21_attend_ip ;;
    *) return 1 ;;
  esac
}

annuler_E21() {
  local exp faux tpl r md n m cur
  exp="$(m18_lire E21 expire_orig)"
  faux="$(m18_lire E21 expire_faux)"
  if [[ -n "$faux" ]]; then
    cur="$(_e21_pve_json "pveum user token list $_E21_USER --output-format json" \
      | jq -r --arg t "$_E21_JETON" '.[]? | select(.tokenid == $t) | (.expire // 0)')" || cur=""
    if [[ "$cur" == "$faux" ]]; then
      remote "$WB_PVE_HOST" "pveum user token modify $_E21_USER $_E21_JETON --expire ${exp:-0}" >/dev/null \
        || wb_avert "expiration du jeton non rétablie : pveum user token modify $_E21_USER $_E21_JETON --expire 0"
      m18_journal E21 "annulation : expiration du jeton remise à ${exp:-0}"
    fi
    m18_oublier E21 expire_orig
    m18_oublier E21 expire_faux
  fi
  tpl="$(m18_lire E21 template)"
  if [[ -n "$tpl" ]]; then
    if ! _e21_dans_pool "$tpl"; then
      remote "$WB_PVE_HOST" "pveum pool modify lab --vms $tpl" >/dev/null || wb_avert "template $tpl non remis dans le pool lab"
      m18_journal E21 "annulation : template $tpl remis dans le pool lab"
    fi
    m18_oublier E21 template
  fi
  if [[ -f "$(m18_etat E21)/reservations" ]]; then
    while read -r r; do
      [[ -n "$r" ]] && m18_gestion delete ipaddressclaims.ipam.cluster.x-k8s.io "$r" -n "$_E21_NS" --ignore-not-found >/dev/null 2>&1
    done <"$(m18_etat E21)/reservations"
    m18_oublier E21 reservations
    m18_journal E21 "annulation : réservations essai-lb-* supprimées"
  fi
  md="$(m18_lire E21 md)"
  n="$(m18_lire E21 replicas)"
  if [[ -n "$md" && "$n" =~ ^[0-9]+$ ]]; then
    if m="$(_e21_nouvelle)"; then
      m18_gestion annotate machines.v1beta2.cluster.x-k8s.io "$m" -n "$_E21_NS" cluster.x-k8s.io/delete-machine=panne-e21 --overwrite >/dev/null 2>&1 || true
    fi
    m18_gestion scale machinedeployments.v1beta2.cluster.x-k8s.io "$md" -n "$_E21_NS" --replicas "$n" >/dev/null \
      || wb_avert "MachineDeployment $md non remis à $n réplicas"
    m18_journal E21 "annulation : $md remis à $n réplicas"
  fi
  for f in md replicas avant variante pool; do m18_oublier E21 "$f"; done
}

resume_E21() { echo "Un travailleur demandé sur capi-essai reste bloqué avant d'être Running."; }

symptome_E21() {
  local l
  case "$(m18_lire E21 variante)" in
    1 | 2) l="Dans Proxmox, je ne vois aucune nouvelle VM dans 5180-5189." ;;
    3) l="Dans Proxmox, une nouvelle VM est apparue dans 5180-5189, mais elle ne démarre pas." ;;
  esac
  wb_symptome "Ticket INC-4521 — De : Julien Petit — Copie : Karim Benali" \
    "J'ai demandé un troisième travailleur sur capi-essai pour un test de charge. Karim vient de passer" \
    "le MachineDeployment des travailleurs à un réplica de plus. La nouvelle machine n'avance pas." \
    "$l" \
    "Personne ne supprime rien : trouve ce qui la bloque, répare, et écris RB-180." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 18 21"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 18 E21 3 "$@"; }
fi
