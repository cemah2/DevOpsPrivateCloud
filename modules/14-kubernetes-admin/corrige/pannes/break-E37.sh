# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M14-E37 « Panne : ImagePullBackOff »
#
# Cible : l'espace témoin wb-pannes. Variantes :
#   1. Secret de tirage « harbor-pull » remplacé par une version au mot de passe périmé (« restauré
#      d'une ancienne sauvegarde ») puis nouvelle version d'agenda : 401 au tirage ;
#   2. nom du Secret de tirage mal orthographié dans le déploiement agenda (harbor-pul) : le kubelet
#      tire en anonyme, le projet est privé ;
#   3. hosts.toml de docker.io modifié sur tous les travailleurs (chemin de cache Harbor inexistant),
#      puis un nouvel outil public (busybox de Docker Hub) est déployé : il ne se tire plus ;
#   4. image d'agenda épinglée sur un digest qui n'existe pas.
# Les témoins tirent leurs images à chaque démarrage (imagePullPolicy: Always) : le cache local des
# nœuds ne masque pas la panne. Annulation seulement si la marque de la panne est encore en place.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m14-commun.sh
source "$WB_ROOT/modules/14-kubernetes-admin/corrige/pannes/_m14-commun.sh"

_E37_FAUX_DIGEST="sha256:5e1f0c3b2a9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f"

_e37_tirage_ko_agenda() { m14_nouveau_pod_etat E37 agenda "$_M14_JQ_PULL"; }
_e37_tirage_ko_outil() { m14_nouveau_pod_etat E37 outil-rapport "$_M14_JQ_PULL"; }

# Déploiement « outil-rapport » (variante 3) : un outil d'équipe qui tire une image publique par son
# nom Docker Hub (résolu par le hosts.toml de docker.io des nœuds, vers le cache Harbor).
_e37_outil() {
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: outil-rapport
  namespace: $_M14_NS
  labels: {app.kubernetes.io/name: outil-rapport, medisphere.internal/ticket: DEV-1537}
spec:
  replicas: 1
  selector: {matchLabels: {app.kubernetes.io/name: outil-rapport}}
  template:
    metadata: {labels: {app.kubernetes.io/name: outil-rapport}}
    spec:
      securityContext: {runAsNonRoot: true, runAsUser: 65534, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: outil
          image: docker.io/library/busybox:1.37
          imagePullPolicy: Always
          command: ["/bin/sh", "-c", "while true; do date; sleep 60; done"]
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 50m, memory: 32Mi}}
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
EOF
}

_m14E37_une() {
  local n="$1" h rc img base
  m14_debut E37
  case "$n" in
    1)
      m14_sauver_objet E37 secret harbor-pull "$_M14_NS"
      wb_kubectl -n "$_M14_NS" get secret harbor-pull -o json | jq '
        (.data[".dockerconfigjson"] | @base64d | fromjson
         | .auths |= with_entries(.value |= (
             (if .username then .username else ((.auth | @base64d) | split(":")[0]) end) as $u
             | (if .password then .password else ((.auth | @base64d) | split(":")[1:] | join(":")) end) as $p
             | .username = $u | .password = ($p + "0") | .auth = (($u + ":" + $p + "0") | @base64)))
         | tojson | @base64) as $d
        | {apiVersion, kind, type, metadata: {name: .metadata.name, namespace: .metadata.namespace,
            annotations: {"medisphere.internal/restaure-depuis": "sauvegarde-2026-06"}}, data: {".dockerconfigjson": $d}}' |
        wb_kubectl replace -f - >/dev/null || return 1
      wb_kubectl -n "$_M14_NS" rollout restart deploy/agenda >/dev/null || return 1
      ;;
    2)
      m14_sauver_objet E37 deployment agenda "$_M14_NS"
      wb_kubectl -n "$_M14_NS" patch deploy agenda --type json \
        -p '[{"op":"replace","path":"/spec/template/spec/imagePullSecrets","value":[{"name":"harbor-pul"}]}]' >/dev/null || return 1
      ;;
    3)
      if ! _e37_outil | wb_kubectl apply --dry-run=server -f - >/dev/null 2>&1; then
        return 10 # une politique d'admission refuse les images hors Harbor dans cet espace
      fi
      for h in "${_M14_W[@]}"; do
        rc=0
        m14_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
f=/etc/containerd/certs.d/docker.io/hosts.toml
grep -qs '/v2/dockerhub"' "$f" || exit 10
sauver "$f"
sed -i 's|/v2/dockerhub"|/v2/docker-hub"|' "$f"
journal "hosts.toml de docker.io : chemin du cache changé (/v2/docker-hub)"
EOF
        if ((rc != 0)); then _e37_defaire 3; return "$rc"; fi
        m14_ecrire E37 noeuds-"$h" 1
      done
      _e37_outil | wb_kubectl apply -f - >/dev/null || { _e37_defaire 3; return 1; }
      m14_journal E37 "variante 3 : outil-rapport déployé"
      m14_attendre 120 _e37_tirage_ko_outil || { _e37_defaire 3; return 10; }
      return 0
      ;;
    4)
      m14_sauver_objet E37 deployment agenda "$_M14_NS"
      img="$(wb_kubectl -n "$_M14_NS" get deploy agenda -o json | jq -r '.spec.template.spec.containers[] | select(.name == "agenda") | .image')"
      base="${img%@*}"
      base="${base%:*}"
      [[ "$base" == */* ]] || return 1
      wb_kubectl -n "$_M14_NS" set image deploy/agenda "agenda=$base@$_E37_FAUX_DIGEST" >/dev/null || return 1
      ;;
  esac
  m14_journal E37 "variante $n posée"
  m14_attendre 120 _e37_tirage_ko_agenda || { _e37_defaire "$n"; return 10; }
}

_e37_defaire() {
  local n="$1" h s d
  case "$n" in
    1)
      s="$(wb_kubectl -n "$_M14_NS" get secret harbor-pull -o json 2>/dev/null)" || s=""
      if jq -e '.metadata.annotations["medisphere.internal/restaure-depuis"] // "" | test("sauvegarde-2026-06")' >/dev/null 2>&1 <<<"$s"; then
        m14_restaurer_objet E37 secret harbor-pull "$_M14_NS"
        wb_kubectl -n "$_M14_NS" rollout restart deploy/agenda >/dev/null 2>&1 || true
      else
        m14_oublier_objet E37 secret harbor-pull "$_M14_NS"
      fi
      ;;
    2 | 4)
      d="$(wb_kubectl -n "$_M14_NS" get deploy agenda -o json 2>/dev/null)" || d=""
      if jq -e --arg dg "$_E37_FAUX_DIGEST" '.spec.template.spec
            | ([.imagePullSecrets[]?.name] | index("harbor-pul")) or ([.containers[].image] | any(endswith($dg)))' >/dev/null 2>&1 <<<"$d"; then
        m14_restaurer_objet E37 deployment agenda "$_M14_NS"
      else
        m14_oublier_objet E37 deployment agenda "$_M14_NS"
      fi
      ;;
    3)
      for h in "${_M14_W[@]}"; do
        [[ -n "$(m14_lire E37 noeuds-"$h")" ]] || continue
        m14_wb_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (hosts.toml)"
if grep -qs '/v2/docker-hub"' /etc/containerd/certs.d/docker.io/hosts.toml; then
  restaurer_fichiers; journal "annulation : hosts.toml de docker.io rétabli"
else
  oublier_fichiers
fi
EOF
        m14_oublier E37 noeuds-"$h"
      done
      wb_kubectl -n "$_M14_NS" delete deploy outil-rapport --ignore-not-found >/dev/null 2>&1 || true
      ;;
  esac
}

panne_E37_v1() { m14_preparer && m14_essayer E37 4 1; }
panne_E37_v2() { m14_preparer && m14_essayer E37 4 2; }
panne_E37_v3() { m14_preparer && m14_essayer E37 4 3; }
panne_E37_v4() { m14_preparer && m14_essayer E37 4 4; }

verifier_E37() {
  case "$WB_VAR" in
    3) _e37_tirage_ko_outil ;;
    *) _e37_tirage_ko_agenda ;;
  esac
}

annuler_E37() {
  case "${WB_VAR:-}" in
    [1-4]) _e37_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3 4; do _e37_defaire "$v"; done ;;
  esac
  m14_oublier E37 debut
  m14_journal E37 "annulation"
}

resume_E37() {
  case "${WB_VAR:-}" in
    3) echo "Un outil d'équipe tout juste déployé dans wb-pannes ne démarre pas : ImagePullBackOff." ;;
    *) echo "La nouvelle version de l'agenda de test (wb-pannes) reste en ImagePullBackOff." ;;
  esac
}

symptome_E37() {
  case "${WB_VAR:-}" in
    3)
      wb_symptome "Ticket INC-4137 — De : Julien Petit" \
        "On vient de déployer un petit outil de rapport (déploiement « outil-rapport », espace" \
        "wb-pannes), une image publique toute simple. Le pod reste en ImagePullBackOff. Nos images" \
        "MédiAgenda, elles, se tirent très bien. Lucas a « harmonisé la configuration des registres »" \
        "sur les nœuds hier. Fais-le démarrer sans contourner le cache Harbor." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 14 37"
      ;;
    *)
      wb_symptome "Ticket INC-4137 — De : Julien Petit" \
        "La nouvelle version de l'agenda de test (déploiement « agenda », espace wb-pannes) ne" \
        "démarre pas : le pod reste en ErrImagePull puis ImagePullBackOff. L'image est bien dans" \
        "Harbor, je la vois dans l'interface. Lucas a « remis en ordre » des choses dans l'espace." \
        "Remets le déploiement en état, sans contourner Harbor ni sa politique de signature." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 14 37"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 14 E37 4 "$@"; }
fi
