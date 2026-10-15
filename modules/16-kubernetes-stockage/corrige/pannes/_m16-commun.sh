# shellcheck shell=bash
# _m16-commun.sh — fonctions partagées par les scripts de panne du module 16 (M16-E35 à M16-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_kubectl, wb_k8s_sauver, wb_exec, wb_avert,
# WB_EX, WB_VAR…). Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions
# d'annulation sont appelées hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.10 « Pannes du bloc C ») :
#   - les pannes agissent sur les objets de k8s-par1 dans les espaces du workbook (wb-essais,
#     mediagenda-recette) et des composants de plateforme (ceph-csi, kube-system/snapshot-controller,
#     velero), sur les travailleurs k8s-w01-03 (SSH admin + sudo ; arrêt d'une VM du pool lab par
#     pve01 pour M16-E37 v2), et côté ceph-par1 UNIQUEMENT sur les objets du consommateur Kubernetes
#     (identité client.k8s, quota du pool k8s-rbd) : jamais un MON, un OSD ni le pool d'un autre
#     consommateur ;
#   - AUCUNE donnée n'est détruite : pas de suppression de PVC existant, d'image RBD, de base ; les
#     seuls objets supprimés à l'annulation sont ceux que la panne a créés (témoins jetables) ;
#   - tout objet Kubernetes modifié est sauvegardé avant (wb_k8s_sauver, dossier
#     ~/.local/state/workbook/k8s/M16-EXX/, mis en 700/600 car il peut contenir un Secret) ;
#   - l'annulation ne rétablit que ce qui porte encore la marque de la panne (une réparation de
#     l'apprenant n'est jamais défaite).
#
# Témoins du palier 4 (m16_temoins), créés à la première injection et conservés, espace wb-essais :
#   - PVC temoin-rbd (ceph-rbd, RWO, 1 Gio) et Deployment temoin-rbd ;
#   - PVC temoin-cephfs (cephfs, RWX, 1 Gio) et Deployment temoin-cephfs ;
#   chaque pod écrit l'heure (epoch) dans /donnees/battement toutes les 10 s ; sa sonde de
#   disponibilité échoue si le battement a plus de 60 s.
# État local (adm01) : ~/.local/state/workbook/M16-EXX/ (valeurs d'origine non secrètes) et
#   ~/.local/state/workbook/m16-injections/EXX (heure de la dernière injection, lue par les checks,
#   conservée après l'annulation).

_M16_NS_T=wb-essais
_M16_NS_DB=mediagenda-recette
_M16_CLUSTER=mediagenda-db
_M16_NS_CSI=ceph-csi
_M16_SC_RBD=ceph-rbd
_M16_SC_FS=cephfs
_M16_VSC_RBD=ceph-rbd-snap
_M16_POOL=k8s-rbd
_M16_CEPH_ID=client.k8s
_M16_CEPH_ADMIN="${WB_CEPH_ADMIN:-ceph01}"
_M16_PROV_RBD=ceph-csi-rbd-provisioner
_M16_NP_RBD=ceph-csi-rbd-nodeplugin
_M16_DRV_RBD=rbd.csi.ceph.com
_M16_IMAGE="${WB_M16_IMAGE_TEMOIN:-registry.par1.medisphere.internal/dockerhub/library/busybox:1.37}"
read -r -a _M16_TRAVAILLEURS <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
# shellcheck disable=SC2034  # utilisé par break-E37
declare -A _M16_VMID=([k8s-w01]=2144 [k8s-w02]=2145 [k8s-w03]=2146 [k8s-w04]=2147)
_M16_MONS=(10.10.30.51 10.10.30.52 10.10.30.53)

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

# m16_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m16_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M16-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

m16_journal() {
  local ex="$1" d
  shift
  d="$(m16_etat "$ex")"
  printf '%s %s [M16-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}

m16_lire() {
  local f
  f="$(m16_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}

# m16_ecrire EXX CLÉ VALEUR — une seule écriture par clé et par panne (jamais un état déjà cassé).
m16_ecrire() {
  local d
  d="$(m16_etat "$1")"
  [[ -f "$d/$2" ]] || printf '%s\n' "$3" >"$d/$2"
}

m16_effacer_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M16-$1"
  rm -rf -- "$d"
}

# m16_horodater EXX — note l'heure (epoch) de l'injection ; lue par checks/_m16-expert.sh.
m16_horodater() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/m16-injections"
  mkdir -p "$d" && date +%s >"$d/$1"
}

# m16_attendre SECONDES commande [args…] — relance toutes les 5 s jusqu'à succès.
m16_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 5
    t=$((t + 5))
  done
  "$@" >/dev/null 2>&1
}

# m16_essayer EXX NB DÉPART — appelle _mEXX_une N (codes : 0 panne posée ; 10 variante sans effet
# ou impossible sur ce lab, déjà défaite ; autre = erreur) pour N = DÉPART, DÉPART+1… jusqu'à un succès.
m16_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M16-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

# ---------------------------------------------------------------------------
# Objets Kubernetes : sauvegarde et restauration ciblées
# ---------------------------------------------------------------------------

_m16_fichier() {
  local type="$1" nom="$2" ns="${3:-}"
  printf '%s/workbook/k8s/%s/%s_%s_%s.yaml\n' "${XDG_STATE_HOME:-$HOME/.local/state}" "$WB_EX" \
    "${ns:-_cluster}" "${type//\//-}" "$nom"
}

# m16_sauver TYPE NOM [ESPACE] — wb_k8s_sauver, puis droits 700/600 (un Secret peut s'y trouver).
m16_sauver() {
  local f
  wb_k8s_sauver "$@"
  f="$(_m16_fichier "$@")"
  chmod 700 "$(dirname "$f")" 2>/dev/null || true
  chmod 600 "$f" 2>/dev/null || true
}

# m16_restaurer TYPE NOM [ESPACE] — remet l'objet sauvegardé par m16_sauver (le supprime s'il
# n'existait pas). Les champs d'état et d'identité sont retirés ; la resourceVersion courante est
# reprise pour que « replace » fonctionne aussi sur les ressources personnalisées.
m16_restaurer() {
  local type="$1" nom="$2" ns="${3:-}" f j rv
  f="$(_m16_fichier "$@")"
  [[ -f "$f" ]] || return 0
  if [[ "$(head -n1 "$f")" == ABSENT* ]]; then
    wb_kubectl delete "$type" "$nom" ${ns:+-n "$ns"} --ignore-not-found --wait=false >/dev/null 2>&1 || true
    rm -f -- "$f"
    return 0
  fi
  j="$(wb_kubectl create --dry-run=client --validate=false -o json -f "$f" 2>/dev/null \
    | jq -c 'del(.status, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp,
                 .metadata.managedFields, .metadata.generation, .metadata.selfLink,
                 .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"])')" || j=""
  if [[ -z "$j" ]]; then
    wb_avert "restauration impossible de $type/$nom (fichier $f illisible) : à remettre à la main"
    return 0
  fi
  rv="$(wb_kubectl get "$type" "$nom" ${ns:+-n "$ns"} -o jsonpath='{.metadata.resourceVersion}' 2>/dev/null)" || rv=""
  if [[ -n "$rv" ]]; then
    jq -c --arg rv "$rv" '.metadata.resourceVersion = $rv' <<<"$j" | wb_kubectl replace -f - >/dev/null 2>&1 \
      || { wb_avert "$type/$nom non restauré (modifié entre-temps ?)"; return 0; }
  else
    wb_kubectl create -f - <<<"$j" >/dev/null 2>&1 || { wb_avert "$type/$nom non recréé"; return 0; }
  fi
  rm -f -- "$f"
}

# m16_k ARGS — wb_kubectl silencieux sur stderr.
m16_k() { wb_kubectl "$@" 2>/dev/null; }

# m16_json TYPE NOM [ESPACE] — l'objet en JSON (vide s'il n'existe pas).
m16_json() {
  local type="$1" nom="$2" ns="${3:-}"
  m16_k get "$type" "$nom" ${ns:+-n "$ns"} -o json || true
}

# m16_existe TYPE NOM [ESPACE]
m16_existe() {
  local type="$1" nom="$2" ns="${3:-}"
  wb_kubectl get "$type" "$nom" ${ns:+-n "$ns"} >/dev/null 2>&1
}

# m16_sc_param CLÉ — paramètre de la StorageClass ceph-rbd (ex. clusterID).
m16_sc_param() {
  m16_k get storageclass "$_M16_SC_RBD" -o json | jq -r --arg c "$1" '.parameters[$c] // empty'
}

# m16_noeud_du_pod ESPACE SÉLECTEUR — nœud du premier pod Running correspondant.
m16_noeud_du_pod() {
  m16_k get pods -n "$1" -l "$2" -o json \
    | jq -r '[.items[] | select(.status.phase == "Running" and (.metadata.deletionTimestamp == null))][0].spec.nodeName // empty'
}

# m16_pret ESPACE DEPLOYMENT — 0 si toutes les répliques voulues sont disponibles.
m16_pret() {
  m16_k get deployment "$2" -n "$1" -o json \
    | jq -e '(.spec.replicas // 1) >= 1 and (.status.availableReplicas // 0) >= (.spec.replicas // 1)
             and (.status.updatedReplicas // 0) >= (.spec.replicas // 1)' >/dev/null 2>&1
}

# m16_noeud_pret NŒUD
m16_noeud_pret() {
  m16_k get node "$1" -o json \
    | jq -e '[.status.conditions[] | select(.type == "Ready")][0].status == "True"' >/dev/null 2>&1
}

# m16_evenement ESPACE OBJET MOTIF — un événement récent (10 min) sur l'objet correspond au motif.
m16_evenement() {
  m16_k get events -n "$1" --field-selector "involvedObject.name=$2" -o json \
    | jq -e --arg m "$3" --argjson t "$(($(date +%s) - 600))" '
        any(.items[]; (((.lastTimestamp // .eventTime // .metadata.creationTimestamp) | sub("\\.[0-9]+";"") | fromdateiso8601) >= $t)
                      and ((.reason + " " + .message) | test($m)))' >/dev/null 2>&1
}

# m16_premier_pod ESPACE SÉLECTEUR — nom du pod le plus récent (non supprimé) du sélecteur.
m16_premier_pod() {
  m16_k get pods -n "$1" -l "$2" -o json \
    | jq -r '[.items[] | select(.metadata.deletionTimestamp == null)] | sort_by(.metadata.creationTimestamp) | last | .metadata.name // empty'
}

# ---------------------------------------------------------------------------
# Accès aux hôtes et à Ceph
# ---------------------------------------------------------------------------

# Aide envoyée au nœud admin de ceph-par1 (après le prélude de wb_exec, exécutée en root).
read -r -d '' _M16_AIDE_CEPH <<'AIDE' || true
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ceph_sh() {
  if command -v ceph >/dev/null 2>&1 && [ -r /etc/ceph/ceph.client.admin.keyring ]; then
    timeout 120 bash -c "$1" </dev/null
  else
    timeout 180 cephadm shell -- bash -c "$1" </dev/null 2>/dev/null
  fi
}
ceph_() { ceph_sh "ceph --connect-timeout 20 $(printf '%q ' "$@")"; }
AIDE

# m16_ceph_exec [VAR=valeur…] <<'EOF' … EOF — script en root sur le nœud admin de ceph-par1.
m16_ceph_exec() {
  { printf '%s\n' "$_M16_AIDE_CEPH"; cat; } | wb_exec "$_M16_CEPH_ADMIN" "$@"
}

# m16_ceph ARGS… — une commande ceph sur le nœud admin, sortie standard renvoyée.
m16_ceph() {
  local a
  a="$(printf '%q ' "$@")"
  m16_ceph_exec A="$a" <<'EOF'
ceph_sh "ceph --connect-timeout 20 $A"
EOF
}

# m16_caps — droits de client.k8s en JSON compact ({"mon": "...", "osd": "...", ...}), jamais la clé.
m16_caps() {
  m16_ceph auth get "$_M16_CEPH_ID" -f json 2>/dev/null | jq -c '.[0].caps // empty' 2>/dev/null
}

# m16_hachage_cle — empreinte SHA-256 de la clé de client.k8s (jamais la clé elle-même).
m16_hachage_cle() {
  m16_ceph_exec I="$_M16_CEPH_ID" <<'EOF' 2>/dev/null
ceph_sh "ceph --connect-timeout 20 auth get-key $I" | sha256sum | cut -d' ' -f1
EOF
}

# m16_ca_bidon — certificat d'une autorité auto-signée inconnue (PEM), pour les variantes « CA ».
m16_ca_bidon() {
  local t
  t="$(mktemp -d)"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 365 \
    -subj "/O=MediSphere/CN=MediSphere Root CA" -keyout "$t/k.pem" -out "$t/c.pem" >/dev/null 2>&1 \
    && cat "$t/c.pem"
  rm -rf -- "$t"
}

# m16_cle_bidon — une clé au format cephx (« AQ… », 40 caractères) qui n'est celle de personne.
m16_cle_bidon() {
  { printf '\001\000'; head -c 8 /dev/urandom; printf '\020\000'; head -c 16 /dev/urandom; } | base64 -w0
}

# ---------------------------------------------------------------------------
# Témoins du palier 4 et état sain
# ---------------------------------------------------------------------------

# _m16_manifeste_temoin NOM CLASSE MODE — PVC + Deployment d'un témoin (sortie standard).
_m16_manifeste_temoin() {
  sed -e "s|@NOM@|$1|g" -e "s|@CLASSE@|$2|g" -e "s|@MODE@|$3|g" -e "s|@IMAGE@|$_M16_IMAGE|g" \
    -e "s|@NS@|$_M16_NS_T|g" <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: @NOM@
  namespace: @NS@
  labels: {app.kubernetes.io/name: @NOM@, app.kubernetes.io/part-of: wb-temoins, medisphere.internal/temoin: m16}
spec:
  accessModes: [@MODE@]
  storageClassName: @CLASSE@
  resources: {requests: {storage: 1Gi}}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: @NOM@
  namespace: @NS@
  labels: {app.kubernetes.io/name: @NOM@, app.kubernetes.io/part-of: wb-temoins, medisphere.internal/temoin: m16}
spec:
  replicas: 1
  strategy: {type: Recreate}
  selector: {matchLabels: {app.kubernetes.io/name: @NOM@}}
  template:
    metadata:
      labels: {app.kubernetes.io/name: @NOM@, app.kubernetes.io/part-of: wb-temoins, medisphere.internal/temoin: m16}
    spec:
      terminationGracePeriodSeconds: 5
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        runAsGroup: 65534
        fsGroup: 65534
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: temoin
          image: @IMAGE@
          command: ["sh", "-c", "while true; do date +%s > /donnees/.b && mv /donnees/.b /donnees/battement && sync; sleep 10; done"]
          readinessProbe:
            exec: {command: ["sh", "-c", "t=$(cat /donnees/battement) && [ $(( $(date +%s) - t )) -lt 60 ]"]}
            periodSeconds: 10
            failureThreshold: 2
          resources:
            requests: {cpu: 10m, memory: 16Mi}
            limits: {cpu: 100m, memory: 32Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: [ALL]}
          volumeMounts: [{name: donnees, mountPath: /donnees}]
      volumes:
        - name: donnees
          persistentVolumeClaim: {claimName: @NOM@}
YAML
}

# m16_temoins — crée les témoins absents et attend qu'ils soient disponibles (3 min au plus).
m16_temoins() {
  local nom classe mode
  m16_existe namespace "$_M16_NS_T" || { wb_avert "espace $_M16_NS_T absent (M14-E07)"; return 1; }
  for nom in temoin-rbd temoin-cephfs; do
    if [[ "$nom" == temoin-rbd ]]; then classe="$_M16_SC_RBD"; mode=ReadWriteOnce; else classe="$_M16_SC_FS"; mode=ReadWriteMany; fi
    m16_existe storageclass "$classe" || { wb_avert "StorageClass $classe absente (M16-E06/E07)"; return 1; }
    if ! m16_existe deployment "$nom" "$_M16_NS_T"; then
      _m16_manifeste_temoin "$nom" "$classe" "$mode" | wb_kubectl apply -f - >/dev/null || return 1
    fi
  done
  m16_attendre 180 m16_pret "$_M16_NS_T" temoin-rbd || { wb_avert "témoin temoin-rbd pas disponible"; return 1; }
  m16_attendre 120 m16_pret "$_M16_NS_T" temoin-cephfs || { wb_avert "témoin temoin-cephfs pas disponible"; return 1; }
}

# m16_sain_csi — nœuds Ready, ceph-csi RBD disponible, témoins disponibles ; sinon dit pourquoi.
m16_sain_csi() {
  local n pb=()
  for n in "${_M16_TRAVAILLEURS[@]}"; do
    m16_noeud_pret "$n" || pb+=("nœud $n pas Ready")
    [[ "$(m16_k get node "$n" -o jsonpath='{.spec.unschedulable}')" == true ]] && pb+=("nœud $n cordonné")
  done
  m16_pret "$_M16_NS_CSI" "$_M16_PROV_RBD" || pb+=("$_M16_PROV_RBD pas disponible")
  m16_k get daemonset "$_M16_NP_RBD" -n "$_M16_NS_CSI" -o json \
    | jq -e '.status.numberReady >= 1 and .status.numberReady == .status.desiredNumberScheduled' >/dev/null 2>&1 \
    || pb+=("$_M16_NP_RBD incomplet")
  m16_pret "$_M16_NS_T" temoin-rbd || pb+=("témoin temoin-rbd indisponible")
  m16_pret "$_M16_NS_T" temoin-cephfs || pb+=("témoin temoin-cephfs indisponible")
  if ((${#pb[@]} == 0)); then return 0; fi
  wb_avert "k8s-par1 n'est pas sain avant la panne : ${pb[*]}. Lance lab/bin/check 16 ${WB_EX#M16-E} et répare d'abord."
  return 1
}

# m16_preparer — précondition commune : témoins prêts puis cluster sain. Pendant l'astreinte
# (M16-E43, _M16_ASTREINTE=1), break-E43 a fait ces contrôles une fois avant la première panne.
m16_preparer() {
  if [[ -n "${_M16_ASTREINTE:-}" ]]; then return 0; fi
  m16_temoins || return 1
  m16_sain_csi
}

# ---------------------------------------------------------------------------
# CloudNativePG (mediagenda-db) et Velero
# ---------------------------------------------------------------------------

m16_cnpg() { m16_json cluster.postgresql.cnpg.io "$_M16_CLUSTER" "$_M16_NS_DB"; }

# m16_cnpg_sain — 3 instances prêtes, phase « Cluster in healthy state ».
m16_cnpg_sain() {
  m16_cnpg | jq -e '.spec.instances >= 3 and .status.readyInstances == .spec.instances
                    and .status.phase == "Cluster in healthy state"' >/dev/null 2>&1
}

m16_primaire() { m16_cnpg | jq -r '.status.currentPrimary // empty'; }

# m16_psql "SQL" — requête sur le primaire (sortie brute, -tA).
m16_psql() {
  local p
  p="$(m16_primaire)"
  [[ -n "$p" ]] || return 1
  wb_kubectl exec -n "$_M16_NS_DB" "$p" -c postgres -- psql -X -v ON_ERROR_STOP=1 -tAc "$1" 2>/dev/null
}

# m16_bsl — nom de l'emplacement de sauvegarde de Velero (par défaut, sinon celui de velero-k8s-par1).
m16_bsl() {
  m16_k get backupstoragelocations.velero.io -n velero -o json | jq -r '
    ([.items[] | select(.spec.default == true)] + [.items[] | select(.spec.objectStorage.bucket == "velero-k8s-par1")])[0].metadata.name // empty'
}

m16_bsl_phase() {
  m16_k get backupstoragelocations.velero.io "$1" -n velero -o jsonpath='{.status.phase}'
}

# m16_creer_sauvegarde NOM — sauvegarde Velero de wb-essais (volumes par Kopia), TTL 24 h.
m16_creer_sauvegarde() {
  local bsl
  bsl="$(m16_bsl)"
  wb_kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: $1
  namespace: velero
spec:
  includedNamespaces: [$_M16_NS_T]
  defaultVolumesToFsBackup: true
  storageLocation: ${bsl:-default}
  ttl: 24h0m0s
EOF
}
