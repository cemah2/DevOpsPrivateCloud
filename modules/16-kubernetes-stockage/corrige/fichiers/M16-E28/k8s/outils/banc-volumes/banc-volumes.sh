#!/usr/bin/env bash
# plateforme/k8s — outils/banc-volumes/banc-volumes.sh (M16-E28, PLAT-1728)
# Mesure un profil fio sur une cible (classe de stockage ou emptyDir) dans wb-essais, sur un nœud
# imposé, et écrit le résultat JSON de fio dans RÉPERTOIRE/<cible>-<profil>-<n>.json.
# Le PVC de mesure et le Job sont supprimés à la fin, même en cas d'échec.
# Usage : banc-volumes.sh --cible ceph-rbd|ceph-rbd-chiffre|cephfs|emptydir|<classe> --profil wal|oltp|iops|debit
#                         [--repetition N] [--noeud k8s-w01] [--sortie ~/m16/e28]
set -euo pipefail

ici="$(dirname "$(readlink -f "$0")")"
ns=wb-essais
noeud=k8s-w01
cible=""
profil=""
rep=1
sortie="$HOME/m16/e28"
# Image signée de M16-E28 (remplace par l'empreinte : @sha256:…).
image="${BANC_IMAGE:-registry.par1.medisphere.internal/plateforme/outils-stockage:1.0.0}"

while (($#)); do
  case "$1" in
    --cible) cible="$2"; shift 2 ;;
    --profil) profil="$2"; shift 2 ;;
    --repetition) rep="$2"; shift 2 ;;
    --noeud) noeud="$2"; shift 2 ;;
    --sortie) sortie="$2"; shift 2 ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done
[[ -n "$cible" && "$profil" =~ ^(wal|oltp|iops|debit)$ && "$rep" =~ ^[0-9]+$ ]] \
  || { echo "usage : $0 --cible CIBLE --profil wal|oltp|iops|debit [--repetition N]" >&2; exit 2; }

nom="banc-${cible//[^a-z0-9]/-}-${profil}-${rep}"
mkdir -p "$sortie"

nettoyer() {
  kubectl delete job "$nom" -n "$ns" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  kubectl delete configmap "$nom" -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete pvc "$nom" -n "$ns" --ignore-not-found --wait=true >/dev/null 2>&1 || true
}
trap nettoyer EXIT

kubectl create configmap "$nom" -n "$ns" --from-file=profils.fio="$ici/profils.fio" >/dev/null

if [[ "$cible" == emptydir ]]; then
  volume='{"name": "donnees", "emptyDir": {"sizeLimit": "3Gi"}}'
else
  acces=ReadWriteOnce
  [[ "$cible" == cephfs ]] && acces=ReadWriteMany
  kubectl apply -f - >/dev/null <<FIN
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: $nom, namespace: $ns, labels: {medisphere.internal/banc: "oui"}}
spec:
  accessModes: [$acces]
  storageClassName: $cible
  resources: {requests: {storage: 4Gi}}
FIN
  volume="{\"name\": \"donnees\", \"persistentVolumeClaim\": {\"claimName\": \"$nom\"}}"
fi

kubectl apply -f - >/dev/null <<FIN
apiVersion: batch/v1
kind: Job
metadata: {name: $nom, namespace: $ns, labels: {medisphere.internal/banc: "oui"}}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    metadata: {labels: {medisphere.internal/banc: "oui"}}
    spec:
      restartPolicy: Never
      nodeSelector: {kubernetes.io/hostname: $noeud}
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile: {type: RuntimeDefault}
      containers:
      - name: fio
        image: $image
        # Résultat écrit dans un fichier puis affiché à la fin : les messages de fio passent avant
        # et ne coupent pas le JSON lu par « kubectl logs ».
        command: ["sh", "-c", "fio --section=$profil --output-format=json --output=/donnees/resultat.json /profils/profils.fio >&2 && cat /donnees/resultat.json"]
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities: {drop: [ALL]}
        resources:
          requests: {cpu: "1", memory: 256Mi}
          limits: {memory: 512Mi}
        volumeMounts:
        - {name: donnees, mountPath: /donnees}
        - {name: profils, mountPath: /profils, readOnly: true}
      volumes:
      - $volume
      - {name: profils, configMap: {name: $nom}}
FIN

echo "Mesure $cible / $profil (répétition $rep) sur $noeud…"
kubectl wait --for=condition=complete "job/$nom" -n "$ns" --timeout=15m >/dev/null \
  || { echo "le Job $nom a échoué ou dépassé 15 min" >&2; kubectl logs -n "$ns" "job/$nom" --tail=20 >&2 || true; exit 1; }
f="$sortie/${cible}-${profil}-${rep}.json"
# Les journaux mêlent sortie standard et erreurs de fio : le JSON commence à la première ligne « { ».
kubectl logs -n "$ns" "job/$nom" | sed -n '/^{/,$p' >"$f"
# Résumé : IOPS, débit (Mio/s), latence moyenne et p99 (ms) des lectures et des écritures, et,
# pour « wal », celle des fdatasync : fio la compte À PART (.sync), hors de la latence des écritures ;
# la latence d'une validation PostgreSQL, c'est l'écriture PLUS le fdatasync.
jq -r --arg c "$cible" --arg p "$profil" '.jobs[0] as $j
  | ((["read", "write"][] as $s | $j[$s] | select(.io_bytes > 0)
      | "\($c)\t\($p)\t\($s)\t\(.iops | floor) IOPS\t\(.bw / 1024 | . * 10 | floor / 10) Mio/s\tmoy \(.clat_ns.mean / 1e6 | . * 100 | floor / 100) ms\tp99 \((.clat_ns.percentile["99.000000"] // 0) / 1e6 | . * 100 | floor / 100) ms"),
     ($j.sync // {} | select((.lat_ns.N // 0) > 0)
      | "\($c)\t\($p)\tfdatasync\t\(.lat_ns.N) appels\t-\tmoy \(.lat_ns.mean / 1e6 | . * 100 | floor / 100) ms\tp99 \((.lat_ns.percentile["99.000000"] // 0) / 1e6 | . * 100 | floor / 100) ms"))' "$f"
