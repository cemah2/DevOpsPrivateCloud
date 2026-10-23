#!/usr/bin/env bash
# plateforme/outils — incident/collecte-pod.sh (F3-S12, INC-5912 ; outillage de RB-262 §4)
# Collecte des preuves d'un pod suspect DÉJÀ ISOLÉ (quarantaine posée, pod sorti de son contrôleur),
# du plus volatil au plus durable, sans rien installer dans le conteneur suspect ni le redémarrer :
#   1. état du pod, du nœud et événements de l'espace ;
#   2. processus, connexions et fichiers de /tmp vus d'un conteneur ÉPHÉMÈRE qui partage l'espace de
#      processus de la cible (--target), sous le MÊME utilisateur que la cible (sinon /proc/1/root et
#      /proc/1/exe sont illisibles), profil restricted ;
#   3. journaux du conteneur (courants et précédents) ;
#   4. événements Falco, Tetragon et audit de l'API exportés de Loki (locataire audit) ;
#   5. flux Hubble (tampon limité : à faire tôt), si la CLI hubble est configurée ;
#   6. empreintes SHA-256 (SHA256SUMS), dépôt dans s3://preuves/<INC>/<horodatage>/ par l'identité
#      « preuves-depot » (écrire et lister, jamais supprimer).
# Le checkpoint du conteneur et l'instantané PBS du nœud restent manuels (RB-262 §4, pièces 7 et 8).
#
# Usage : collecte-pod.sh ESPACE POD CONTENEUR INC-NNNN
# Exige sur adm01 : kubectl (identité personnelle, droits exec/debug sur l'espace), jq, curl, aws,
# sha256sum ; ~/.config/workbook/s3-preuves-depot.env (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY).
# Variables : COLLECTE_IMAGE (défaut netshoot du cache Harbor), LOKI_URL, S3_URL.
# Sortie : le contenu de SHA256SUMS, à recopier dans la main courante. Rien n'est supprimé du cluster.
set -euo pipefail

if (($# != 4)); then
  echo "Usage : $0 ESPACE POD CONTENEUR INC-NNNN" >&2
  exit 2
fi
ns="$1" pod="$2" cible="$3" inc="$4"
[[ "$inc" =~ ^INC-[0-9]{4}$ ]] || { echo "numéro d'incident attendu : INC-NNNN" >&2; exit 2; }

image="${COLLECTE_IMAGE:-registry.par1.medisphere.internal/dockerhub/nicolaka/netshoot:v0.16}"
loki="${LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}"
s3="${S3_URL:-https://s3-01.par1.medisphere.internal:8333}"
depot="${PREUVES_ENV:-$HOME/.config/workbook/s3-preuves-depot.env}"
horodatage="$(date -u +%Y%m%dT%H%M%SZ)"
nom_debug="collecte-${horodatage,,}"
nom_debug="${nom_debug//[^a-z0-9-]/}"

for c in kubectl jq curl aws sha256sum; do
  command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 1; }
done
[[ -r "$depot" ]] || { echo "identité de dépôt illisible : $depot" >&2; exit 1; }

# Dossier de travail en mémoire (tmpfs de la session), retiré à la fin.
d="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/$inc.XXXXXX")"
trap 'rm -rf -- "$d"' EXIT
note() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$d/collecte.log" >&2; }

# Garde-fous : le pod existe, il est isolé, il n'est plus géré par un contrôleur.
kubectl -n "$ns" get pod "$pod" -o json >"$d/pod.json"
jq -e '.metadata.labels["medisphere.internal/quarantaine"] == "oui"' "$d/pod.json" >/dev/null ||
  { echo "le pod n'est pas en quarantaine : isole-le d'abord (RB-262 §3)" >&2; exit 1; }
if jq -e '(.metadata.ownerReferences // []) | length > 0' "$d/pod.json" >/dev/null; then
  note "AVERTISSEMENT : le pod a encore un propriétaire (contrôleur) : un déploiement pourrait le remplacer"
fi
redemarrages_avant="$(jq -r --arg c "$cible" '.status.containerStatuses[] | select(.name == $c) | .restartCount' "$d/pod.json")"
note "collecte $inc de $ns/$pod ($cible), redémarrages du conteneur : $redemarrages_avant"

# 1. État du pod, du nœud, événements.
noeud="$(jq -r '.spec.nodeName' "$d/pod.json")"
kubectl get node "$noeud" -o yaml >"$d/noeud.yaml"
kubectl -n "$ns" get events --sort-by=.lastTimestamp -o wide >"$d/evenements.txt" 2>&1 || true

# 2. Conteneur éphémère (même utilisateur que la cible), qui dort le temps de la collecte.
uid="$(jq -r --arg c "$cible" '[.spec.containers[] | select(.name == $c) | .securityContext.runAsUser][0] // .spec.securityContext.runAsUser // 65532' "$d/pod.json")"
jq -n --argjson u "$uid" '{securityContext: {runAsUser: $u, runAsNonRoot: true, allowPrivilegeEscalation: false,
  capabilities: {drop: ["ALL"]}, seccompProfile: {type: "RuntimeDefault"}}}' >"$d/.debug.json"
kubectl -n "$ns" debug "$pod" --image="$image" --target="$cible" --container="$nom_debug" \
  --profile=restricted --custom="$d/.debug.json" -- sleep 1200 >/dev/null
rm -f "$d/.debug.json"
for _ in $(seq 1 30); do
  kubectl -n "$ns" get pod "$pod" -o json |
    jq -e --arg n "$nom_debug" 'any(.status.ephemeralContainerStatuses[]?; .name == $n and .state.running != null)' >/dev/null && break
  sleep 2
done
dbg() { kubectl -n "$ns" exec "$pod" -c "$nom_debug" -- "$@"; }
dbg sh -c 'ps -ef; echo; ls -l /proc/1/exe /proc/1/cwd; echo; tr "\0" " " < /proc/1/cmdline; echo' >"$d/processus.txt" 2>&1 || true
dbg sh -c 'ss -tanp 2>/dev/null || netstat -tan' >"$d/connexions.txt" 2>&1 || true
dbg sh -c 'ls -la /proc/1/root/tmp /proc/1/root/var/tmp /proc/1/root/dev/shm 2>&1' >"$d/fichiers-temporaires.txt" || true
# Fichiers déposés : archivés sans être exécutés ni ouverts dans le conteneur suspect.
dbg tar -C /proc/1/root/tmp -cf - . >"$d/tmp-du-conteneur.tar" 2>/dev/null || note "archive de /tmp impossible (voir fichiers-temporaires.txt)"

# 3. Journaux.
kubectl -n "$ns" logs "$pod" -c "$cible" --timestamps >"$d/journaux.txt" 2>&1 || true
kubectl -n "$ns" logs "$pod" -c "$cible" --timestamps --previous >"$d/journaux-precedents.txt" 2>/dev/null || rm -f "$d/journaux-precedents.txt"

# 4. Loki, locataire audit (24 h).
loki_export() {
  curl -sf --max-time 60 -G -H "X-Scope-OrgID: audit" \
    --data-urlencode "query=$1" --data-urlencode "since=24h" --data-urlencode "limit=5000" \
    "$loki/loki/api/v1/query_range" >"$d/$2" || note "export Loki impossible : $2"
}
loki_export "{service=~\"falco|tetragon\"} |= \"$pod\"" loki-falco-tetragon.json
loki_export "{job=\"kubernetes-audit\"} |= \"$pod\"" loki-audit-api.json

# 5. Hubble.
if command -v hubble >/dev/null; then
  hubble observe --pod "$ns/$pod" --since 24h -o json >"$d/hubble.json" 2>/dev/null || note "hubble observe impossible"
fi

# Le conteneur suspect n'a pas redémarré pendant la collecte (preuves volatiles intactes).
redemarrages_apres="$(kubectl -n "$ns" get pod "$pod" -o json | jq -r --arg c "$cible" '.status.containerStatuses[] | select(.name == $c) | .restartCount')"
[[ "$redemarrages_apres" == "$redemarrages_avant" ]] || note "ATTENTION : le conteneur a redémarré pendant la collecte ($redemarrages_avant → $redemarrages_apres)"
kubectl -n "$ns" get pod "$pod" -o yaml >"$d/pod-apres-collecte.yaml"

# 6. Empreintes et dépôt (jamais de suppression : l'identité de dépôt ne le peut pas).
note "fin de la collecte, calcul des empreintes"
(cd "$d" && sha256sum -- * >SHA256SUMS)
(
  set -a
  # shellcheck disable=SC1090
  source "$depot"
  set +a
  aws --endpoint-url "$s3" s3 cp --recursive --only-show-errors "$d/" "s3://preuves/$inc/$horodatage/"
)
echo "Preuves déposées dans s3://preuves/$inc/$horodatage/ — empreintes (à recopier dans la main courante) :"
cat "$d/SHA256SUMS"
