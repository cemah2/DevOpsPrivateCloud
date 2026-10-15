# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M16-E35 « Panne : le PVC reste Pending »
#
# La panne « déploie » dans wb-essais une petite application de test, le StatefulSet temoin-e35
# (1 réplique, volumeClaimTemplates « donnees » 2 Gio), qui ne démarre pas. Variantes :
#   1. classe inexistante : volumeClaimTemplates en storageClassName « ceph-rbd-ssd » (copiée d'un
#      ancien manifeste d'InfoGér) ;
#   2. plus de classe par défaut : l'annotation is-default-class de ceph-rbd passe à « false » et le
#      gabarit ne nomme aucune classe ;
#   3. quota : ResourceQuota « stockage-equipe » qui plafonne le nombre de PVC de la classe ceph-rbd
#      au nombre actuel → la création du PVC est refusée par l'admission ;
#   4. provisioner arrêté : Deployment ceph-csi-rbd-provisioner à 0 réplique.
# Objets d'origine sauvegardés (wb_k8s_sauver) ; l'annulation supprime temoin-e35 (objet de test),
# et ne rétablit que ce qui porte encore la panne.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m16-commun.sh
source "$WB_ROOT/modules/16-kubernetes-stockage/corrige/pannes/_m16-commun.sh"

_E35_QUOTA=stockage-equipe

# _e35_sts CLASSE — manifeste du StatefulSet de test (CLASSE vide : pas de storageClassName).
_e35_sts() {
  local classe_ligne=""
  [[ -n "$1" ]] && classe_ligne="        storageClassName: $1"
  cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: temoin-e35
  namespace: $_M16_NS_T
  labels: {app.kubernetes.io/name: temoin-e35}
spec:
  clusterIP: None
  selector: {app.kubernetes.io/name: temoin-e35}
  ports: [{name: factice, port: 9, targetPort: 9}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: temoin-e35
  namespace: $_M16_NS_T
  labels: {app.kubernetes.io/name: temoin-e35, app.kubernetes.io/part-of: dev-julien}
spec:
  serviceName: temoin-e35
  replicas: 1
  selector: {matchLabels: {app.kubernetes.io/name: temoin-e35}}
  template:
    metadata:
      labels: {app.kubernetes.io/name: temoin-e35}
    spec:
      terminationGracePeriodSeconds: 5
      securityContext: {runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, fsGroup: 65534, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: app
          image: $_M16_IMAGE
          command: ["sh", "-c", "date > /donnees/demarrage && exec sleep 2147483647"]
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 32Mi}}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
          volumeMounts: [{name: donnees, mountPath: /donnees}]
  volumeClaimTemplates:
    - metadata:
        name: donnees
      spec:
        accessModes: [ReadWriteOnce]
$classe_ligne
        resources: {requests: {storage: 2Gi}}
EOF
}

_e35_sans_provisioner() {
  [[ -z "$(m16_k get pods -n "$_M16_NS_CSI" -l app=ceph-csi-rbd,component=provisioner -o name)" ]]
}

_e35_supprimer_temoin() {
  wb_kubectl delete statefulset temoin-e35 -n "$_M16_NS_T" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
  wb_kubectl delete service temoin-e35 -n "$_M16_NS_T" --ignore-not-found >/dev/null 2>&1 || true
  wb_kubectl delete pvc -n "$_M16_NS_T" -l app.kubernetes.io/name=temoin-e35 --ignore-not-found --wait=false >/dev/null 2>&1 || true
  # Les PVC d'un StatefulSet ne portent pas toujours les étiquettes du modèle : par le nom aussi.
  wb_kubectl delete pvc donnees-temoin-e35-0 -n "$_M16_NS_T" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

_m16E35_une() {
  local n="$1" classe="$_M16_SC_RBD" nb d
  # Un défaut déjà présent (aucune classe par défaut, provisioner à 0) fausserait le diagnostic.
  case "$n" in
    1) classe="ceph-rbd-ssd"
       m16_existe storageclass "$classe" && return 10 ;;
    2) classe=""
       [[ "$(m16_k get storageclass "$_M16_SC_RBD" -o json | jq -r '.metadata.annotations["storageclass.kubernetes.io/is-default-class"] // ""')" == true ]] || return 10
       m16_sauver storageclass "$_M16_SC_RBD"
       wb_kubectl annotate storageclass "$_M16_SC_RBD" --overwrite \
         storageclass.kubernetes.io/is-default-class=false >/dev/null 2>&1 || return 1
       m16_ecrire E35 defaut_retire oui
       # Une autre classe par défaut rendrait la variante sans effet.
       d="$(m16_k get storageclass -o json | jq -r '[.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true")] | length')"
       [[ "$d" == 0 ]] || { _e35_defaire 2; return 10; } ;;
    3) m16_existe resourcequota "$_E35_QUOTA" "$_M16_NS_T" && return 10
       nb="$(m16_k get pvc -n "$_M16_NS_T" -o json | jq --arg c "$_M16_SC_RBD" '[.items[] | select(.spec.storageClassName == $c)] | length')"
       m16_sauver resourcequota "$_E35_QUOTA" "$_M16_NS_T"
       wb_kubectl apply -f - >/dev/null 2>&1 <<EOF || return 1
apiVersion: v1
kind: ResourceQuota
metadata:
  name: $_E35_QUOTA
  namespace: $_M16_NS_T
  annotations: {medisphere.internal/ticket: "CHG-1735 plafond provisoire, à revoir"}
spec:
  hard:
    $_M16_SC_RBD.storageclass.storage.k8s.io/persistentvolumeclaims: "${nb:-0}"
EOF
       sleep 5 ;;
    4) nb="$(m16_k get deployment "$_M16_PROV_RBD" -n "$_M16_NS_CSI" -o jsonpath='{.spec.replicas}')"
       [[ "${nb:-0}" =~ ^[1-9][0-9]*$ ]] || return 10
       m16_ecrire E35 repliques "$nb"
       wb_kubectl scale deployment "$_M16_PROV_RBD" -n "$_M16_NS_CSI" --replicas=0 >/dev/null 2>&1 || return 1
       m16_attendre 90 _e35_sans_provisioner || true ;;
  esac
  _e35_sts "$classe" | wb_kubectl apply -f - >/dev/null 2>&1 || { _e35_defaire "$n"; return 1; }
  m16_journal E35 "variante $n posée"
}

# _e35_defaire N — retire la variante N si elle est encore en place.
_e35_defaire() {
  local nb d
  case "$1" in
    2)
      [[ "$(m16_lire E35 defaut_retire)" == oui ]] || return 0
      d="$(m16_k get storageclass -o json | jq -r '[.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true")] | length')" || d=1
      # Rétablie seulement si aucune classe n'est par défaut (une autre réparation reste en place),
      # et seulement si ceph-rbd l'était avant la panne.
      if [[ "$d" == 0 ]] && grep -q 'is-default-class: "true"' "$(_m16_fichier storageclass "$_M16_SC_RBD")" 2>/dev/null; then
        wb_kubectl annotate storageclass "$_M16_SC_RBD" --overwrite \
          storageclass.kubernetes.io/is-default-class=true >/dev/null 2>&1 || wb_avert "annulation : classe par défaut non rétablie"
      fi
      rm -f -- "$(_m16_fichier storageclass "$_M16_SC_RBD")" ;;
    3)
      m16_restaurer resourcequota "$_E35_QUOTA" "$_M16_NS_T" ;;
    4)
      nb="$(m16_lire E35 repliques)"
      [[ -n "$nb" ]] || return 0
      if [[ "$(m16_k get deployment "$_M16_PROV_RBD" -n "$_M16_NS_CSI" -o jsonpath='{.spec.replicas}')" == 0 ]]; then
        wb_kubectl scale deployment "$_M16_PROV_RBD" -n "$_M16_NS_CSI" --replicas="$nb" >/dev/null 2>&1 \
          || wb_avert "annulation : $_M16_PROV_RBD non relancé"
      fi ;;
  esac
}

_e35_injecter() {
  m16_preparer || return 1
  m16_existe statefulset temoin-e35 "$_M16_NS_T" && _e35_supprimer_temoin
  m16_horodater E35
  m16_essayer E35 4 "$1"
}

panne_E35_v1() { _e35_injecter 1; }
panne_E35_v2() { _e35_injecter 2; }
panne_E35_v3() { _e35_injecter 3; }
panne_E35_v4() { _e35_injecter 4; }

# La panne est constatée si, au bout de 45 s, temoin-e35 n'a toujours aucune réplique prête et que
# le symptôme attendu est visible (PVC Pending, ou création refusée par le quota).
verifier_E35() {
  sleep 45
  local pret
  pret="$(m16_k get statefulset temoin-e35 -n "$_M16_NS_T" -o jsonpath='{.status.readyReplicas}')"
  [[ "${pret:-0}" == 0 ]] || return 1
  case "$WB_VAR" in
    3) m16_evenement "$_M16_NS_T" temoin-e35 'exceeded quota|forbidden' ;;
    *) [[ "$(m16_k get pvc donnees-temoin-e35-0 -n "$_M16_NS_T" -o jsonpath='{.status.phase}')" == Pending ]] ;;
  esac
}

annuler_E35() {
  case "${WB_VAR:-}" in
    1 | 2 | 3 | 4) _e35_defaire "$WB_VAR" ;;
    *) _e35_defaire 4; _e35_defaire 3; _e35_defaire 2 ;;
  esac
  _e35_supprimer_temoin
  m16_journal E35 "annulation"
  m16_effacer_etat E35
}

resume_E35() {
  echo "La nouvelle application de test de Julien (StatefulSet temoin-e35, espace wb-essais) ne démarre pas : son volume n'est jamais prêt."
}

symptome_E35() {
  wb_symptome "Ticket INC-4341 — De : Julien Petit" \
    "J'ai déployé ce matin notre petite application de test dans wb-essais : le StatefulSet" \
    "temoin-e35 (une réplique, un volume de 2 Gio par instance). Il reste à 0/1 depuis : le pod" \
    "ne démarre jamais, on dirait qu'il attend son volume. Le manifeste vient de notre dépôt et" \
    "marchait la semaine dernière sur un autre espace. Tu peux regarder ?" \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 16 35"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 16 E35 4 "$@"; }
fi
