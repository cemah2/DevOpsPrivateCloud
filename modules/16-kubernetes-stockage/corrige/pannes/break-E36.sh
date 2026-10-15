# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M16-E36 « Panne : le pod reste en ContainerCreating »
#
# La panne crée dans wb-essais l'application de test temoin-e36 (PVC 1 Gio ceph-rbd, provisionné et
# lié AVANT la panne, et un Deployment épinglé sur un travailleur choisi au hasard par une affinité
# de nœud « équipe de Julien »). Le pod reste en ContainerCreating. Variantes :
#   1. Secret de nœud faux : la clé (userKey) du Secret désigné par
#      csi.storage.k8s.io/node-stage-secret-name de la StorageClass ceph-rbd est remplacée par une
#      clé au bon format qui n'est celle de personne (« rotation ratée ») ;
#   2. moniteurs injoignables depuis le nœud : table nftables « filtrage_stockage » sur le
#      travailleur, qui jette les NOUVELLES connexions vers 10.10.30.51-53 ports 3300 et 6789
#      (les sessions déjà établies des volumes montés ne sont pas coupées) ;
#   3. nœud sans pilote : le travailleur perd l'étiquette medisphere.internal/stockage-ceph qui sert de
#      nodeSelector au DaemonSet ceph-csi-rbd-nodeplugin (M16-E05/E06) → le pod nodeplugin du nœud est
#      retiré, plus de pilote rbd.csi.ceph.com enregistré sur ce nœud. Si le DaemonSet n'a pas ce
#      sélecteur, une affinité qui exclut le nœud est ajoutée au DaemonSet à la place.
# Sauvegardes : Secret et DaemonSet (wb_k8s_sauver, fichiers 600) ; la table nftables porte son nom.
# L'annulation ne remet le Secret que s'il porte encore la clé de la panne (empreinte comparée).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m16-commun.sh
source "$WB_ROOT/modules/16-kubernetes-stockage/corrige/pannes/_m16-commun.sh"

_E36_TABLE=filtrage_stockage
_E36_ETIQ=medisphere.internal/stockage-ceph

_e36_noeud() { m16_lire E36 noeud; }

# _e36_pvc / _e36_deploiement NŒUD — PVC puis Deployment de test épinglé sur NŒUD.
_e36_pvc() {
  wb_kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: temoin-e36
  namespace: $_M16_NS_T
  labels: {app.kubernetes.io/name: temoin-e36}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: $_M16_SC_RBD
  resources: {requests: {storage: 1Gi}}
EOF
}

_e36_deploiement() {
  wb_kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: temoin-e36
  namespace: $_M16_NS_T
  labels: {app.kubernetes.io/name: temoin-e36, app.kubernetes.io/part-of: dev-julien}
spec:
  replicas: 1
  strategy: {type: Recreate}
  selector: {matchLabels: {app.kubernetes.io/name: temoin-e36}}
  template:
    metadata:
      labels: {app.kubernetes.io/name: temoin-e36}
    spec:
      terminationGracePeriodSeconds: 5
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions: [{key: kubernetes.io/hostname, operator: In, values: [$1]}]
      securityContext: {runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, fsGroup: 65534, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: app
          image: $_M16_IMAGE
          command: ["sh", "-c", "date > /donnees/demarrage && exec sleep 2147483647"]
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 32Mi}}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
          volumeMounts: [{name: donnees, mountPath: /donnees}]
      volumes:
        - name: donnees
          persistentVolumeClaim: {claimName: temoin-e36}
EOF
}

_e36_sans_pilote() {
  [[ -z "$(m16_k get pods -n "$_M16_NS_CSI" -l app=ceph-csi-rbd,component=nodeplugin --field-selector "spec.nodeName=$1" -o name)" ]]
}

_e36_lie() { [[ "$(m16_k get pvc temoin-e36 -n "$_M16_NS_T" -o jsonpath='{.status.phase}')" == Bound ]]; }

_e36_supprimer_temoin() {
  wb_kubectl delete deployment temoin-e36 -n "$_M16_NS_T" --ignore-not-found --wait=true --timeout=90s >/dev/null 2>&1 || true
  wb_kubectl delete pvc temoin-e36 -n "$_M16_NS_T" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

# Secret de nœud de la classe ceph-rbd : « espace nom ».
_e36_secret() {
  local n s
  n="$(m16_sc_param csi.storage.k8s.io/node-stage-secret-namespace)"
  s="$(m16_sc_param csi.storage.k8s.io/node-stage-secret-name)"
  [[ -n "$n" && -n "$s" ]] && printf '%s %s\n' "$n" "$s"
}

_e36_cle_actuelle() {
  m16_k get secret "$2" -n "$1" -o jsonpath='{.data.userKey}' | base64 -d 2>/dev/null | sha256sum | cut -d' ' -f1
}

_m16E36_une() {
  local n="$1" x ns s faux v rc=0
  x="$(_e36_noeud)"
  case "$n" in
    1)
      read -r ns s <<<"$(_e36_secret)"
      [[ -n "${s:-}" ]] || return 10
      m16_sauver secret "$s" "$ns"
      faux="$(m16_cle_bidon)"
      wb_kubectl patch secret "$s" -n "$ns" --type merge \
        -p "$(jq -cn --arg k "$faux" '{stringData: {userKey: $k}}')" >/dev/null 2>&1 || return 1
      m16_ecrire E36 secret "$ns $s"
      m16_ecrire E36 cle_posee "$(printf '%s' "$faux" | sha256sum | cut -d' ' -f1)"
      ;;
    2)
      wb_exec "$x" TABLE="$_E36_TABLE" MONS="${_M16_MONS[*]}" >/dev/null 2>&1 <<'EOF' || rc=$?
nft list table inet "$TABLE" >/dev/null 2>&1 && exit 10
liste="$(printf '%s, ' $MONS)"; liste="${liste%, }"
nft -f - <<NFT || exit 1
table inet $TABLE {
  chain sortie {
    type filter hook output priority 0; policy accept;
    ip daddr { $liste } tcp dport { 3300, 6789 } ct state new counter drop comment "InfoGér durcissement INC-2026-0412"
  }
}
NFT
journal "table nftables inet $TABLE posée (nouvelles connexions vers les moniteurs jetées)"
EOF
      ((rc == 0)) || return "$rc"
      m16_ecrire E36 nft oui
      ;;
    3)
      m16_existe daemonset "$_M16_NP_RBD" "$_M16_NS_CSI" || return 10
      v="$(m16_k get daemonset "$_M16_NP_RBD" -n "$_M16_NS_CSI" -o json | jq -r --arg e "$_E36_ETIQ" '.spec.template.spec.nodeSelector[$e] // empty')"
      if [[ -n "$v" ]]; then
        [[ "$(m16_k get node "$x" -o json | jq -r --arg e "$_E36_ETIQ" '.metadata.labels[$e] // empty')" == "$v" ]] || return 10
        m16_ecrire E36 etiquette "$v"
        wb_kubectl label node "$x" "$_E36_ETIQ-" >/dev/null 2>&1 || return 1
        m16_attendre 120 _e36_sans_pilote "$x" || { _e36_defaire 3; return 1; }
        m16_journal E36 "variante 3 posée (étiquette retirée de $x)"
        return 0
      fi
      m16_sauver daemonset "$_M16_NP_RBD" "$_M16_NS_CSI"
      wb_kubectl patch daemonset "$_M16_NP_RBD" -n "$_M16_NS_CSI" --type json -p "$(jq -cn --arg x "$x" '[{op: "add",
          path: "/spec/template/spec/affinity",
          value: {nodeAffinity: {requiredDuringSchedulingIgnoredDuringExecution: {nodeSelectorTerms: [
            {matchExpressions: [{key: "kubernetes.io/hostname", operator: "NotIn", values: [$x]}]}]}}}}]')" >/dev/null 2>&1 || return 1
      m16_ecrire E36 ds oui
      m16_attendre 120 _e36_sans_pilote "$x" || { _e36_defaire 3; return 1; }
      ;;
  esac
  m16_journal E36 "variante $n posée (nœud $x)"
}

_e36_defaire() {
  local x ns s v
  x="$(_e36_noeud)"
  case "$1" in
    1)
      read -r ns s <<<"$(m16_lire E36 secret)"
      [[ -n "${s:-}" ]] || return 0
      if [[ "$(_e36_cle_actuelle "$ns" "$s")" == "$(m16_lire E36 cle_posee)" ]]; then
        m16_restaurer secret "$s" "$ns"
      else
        rm -f -- "$(_m16_fichier secret "$s" "$ns")"
      fi ;;
    2)
      [[ "$(m16_lire E36 nft)" == oui && -n "$x" ]] || return 0
      wb_exec "$x" TABLE="$_E36_TABLE" >/dev/null 2>&1 <<'EOF' || wb_avert "annulation : table nftables de $x non retirée"
nft list table inet "$TABLE" >/dev/null 2>&1 || exit 0
nft delete table inet "$TABLE"
journal "table nftables inet $TABLE retirée"
EOF
      ;;
    3)
      v="$(m16_lire E36 etiquette)"
      if [[ -n "$v" && -n "$x" ]]; then
        if [[ -z "$(m16_k get node "$x" -o json | jq -r --arg e "$_E36_ETIQ" '.metadata.labels[$e] // empty')" ]]; then
          wb_kubectl label node "$x" "$_E36_ETIQ=$v" >/dev/null 2>&1 || wb_avert "annulation : étiquette de $x non remise"
        fi
        return 0
      fi
      [[ "$(m16_lire E36 ds)" == oui && -n "$x" ]] || return 0
      if m16_k get daemonset "$_M16_NP_RBD" -n "$_M16_NS_CSI" -o json \
        | jq -e --arg x "$x" '[.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[]?.matchExpressions[]? | select(.operator == "NotIn" and (.values | index($x)))] | length > 0' >/dev/null 2>&1; then
        m16_restaurer daemonset "$_M16_NP_RBD" "$_M16_NS_CSI"
      else
        rm -f -- "$(_m16_fichier daemonset "$_M16_NP_RBD" "$_M16_NS_CSI")"
      fi ;;
  esac
}

_e36_injecter() {
  local x
  m16_preparer || return 1
  m16_existe deployment temoin-e36 "$_M16_NS_T" && _e36_supprimer_temoin
  x="${_M16_TRAVAILLEURS[RANDOM % ${#_M16_TRAVAILLEURS[@]}]}"
  m16_ecrire E36 noeud "$x"
  m16_horodater E36
  # Volume provisionné et lié avant la panne : seul le montage sur le nœud est en cause.
  _e36_pvc || return 1
  m16_attendre 90 _e36_lie || { wb_avert "le PVC de test ne se lie pas"; return 1; }
  m16_essayer E36 3 "$1" || return 1
  _e36_deploiement "$x"
}

panne_E36_v1() { _e36_injecter 1; }
panne_E36_v2() { _e36_injecter 2; }
panne_E36_v3() { _e36_injecter 3; }

verifier_E36() {
  local p
  sleep 60
  p="$(m16_premier_pod "$_M16_NS_T" app.kubernetes.io/name=temoin-e36)"
  [[ -n "$p" ]] || return 1
  # Pod ni démarré ni prêt, et événement de montage ou d'attachement en échec.
  m16_k get pod "$p" -n "$_M16_NS_T" -o json \
    | jq -e '[.status.containerStatuses[]? | select(.state.running != null)] | length == 0' >/dev/null 2>&1 || return 1
  m16_evenement "$_M16_NS_T" "$p" 'FailedMount|FailedAttachVolume|MountVolume|not found in the list of registered CSI drivers'
}

annuler_E36() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e36_defaire "$WB_VAR" ;;
    *) _e36_defaire 3; _e36_defaire 2; _e36_defaire 1 ;;
  esac
  _e36_supprimer_temoin
  m16_journal E36 "annulation"
  m16_effacer_etat E36
}

resume_E36() {
  echo "Le pod de test temoin-e36 (wb-essais), épinglé sur $(_e36_noeud), reste en ContainerCreating."
}

symptome_E36() {
  wb_symptome "Ticket INC-4342 — De : Julien Petit" \
    "Notre application de test temoin-e36 (wb-essais) doit tourner sur $(_e36_noeud) : on y épingle" \
    "nos essais de performance. Son volume a été créé sans problème (PVC Bound), mais le pod reste" \
    "en ContainerCreating depuis plus de dix minutes. Ailleurs, tout a l'air de marcher." \
    "Ne déplace pas l'application sur un autre nœud : c'est ce nœud-là qu'il nous faut." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 16 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 16 E36 3 "$@"; }
fi
