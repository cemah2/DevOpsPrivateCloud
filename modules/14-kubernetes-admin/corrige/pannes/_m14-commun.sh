# shellcheck shell=bash
# _m14-commun.sh — fonctions partagées par les scripts de panne du module 14 (M14-E35 à M14-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_exec_invite, wb_kubectl, WB_EX…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.10 « Pannes du bloc C ») :
#   - les pannes n'agissent que sur les nœuds de k8s-par1 (SSH, utilisateur admin + sudo ; agent QEMU
#     depuis pve01 quand SSH peut être perdu) et sur les objets des espaces du workbook (wb-*,
#     mediagenda-*) et des composants de plateforme (kube-system) ;
#   - jamais deux nœuds de contrôle à la fois, sauf l'astreinte M14-E43, qui prend d'abord un
#     instantané etcd vérifié ;
#   - toute valeur modifiée est sauvegardée avant (fichiers : /var/lib/workbook/ de l'hôte ; objets :
#     ~/.local/state/workbook/M14-EXX/ sur adm01, en JSON nettoyé) ; l'annulation ne rétablit que ce
#     qui porte encore la marque de la panne (une réparation de l'apprenant n'est jamais défaite).
#
# Pourquoi un mécanisme propre plutôt que wb_k8s_restaurer de pannes-lib.sh : celui-ci remet un objet
# entier tel qu'il était (replace simple), alors que ces pannes ne doivent défaire QUE ce qu'elles ont
# changé et jamais une réparation de l'apprenant faite entre-temps. Ici, les taints se retirent une à
# une, CoreDNS est corrigé par « patch », et les objets sauvegardés (nettoyés : resourceVersion, uid,
# status…) ne sont remis par « replace » simple, ou recréés s'ils ont disparu, que s'ils portent encore
# la marque de la panne (chaque script le vérifie avant m14_restaurer_objet, sinon m14_oublier_objet).
# Jamais « replace --force » (suppression puis création).
#
# Témoins (m14_temoins) : espace wb-pannes, créé à la première injection et jamais supprimé par les
# pannes (voir _m14-temoins.yaml et l'en-tête de enonce/04-expert.md).

_M14_DIR="$(dirname "${BASH_SOURCE[0]}")"
_M14_NS=wb-pannes
_M14_REGISTRE=registry.par1.medisphere.internal
_M14_VIP=10.10.40.200
_M14_API_NOM=k8s-api.par1.medisphere.internal
read -r -a _M14_CP <<<"${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
read -r -a _M14_W <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
declare -A _M14_IP=([k8s-cp01]=10.10.40.51 [k8s-cp02]=10.10.40.52 [k8s-cp03]=10.10.40.53
  [k8s-w01]=10.10.40.61 [k8s-w02]=10.10.40.62 [k8s-w03]=10.10.40.63)
# shellcheck disable=SC2034
declare -A _M14_VMID=([k8s-cp01]=2141 [k8s-cp02]=2142 [k8s-cp03]=2143
  [k8s-w01]=2144 [k8s-w02]=2145 [k8s-w03]=2146)

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

# m14_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m14_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M14-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

m14_journal() {
  local ex="$1" d
  shift
  d="$(m14_etat "$ex")"
  printf '%s %s [M14-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}

# m14_lire EXX CLÉ / m14_ecrire EXX CLÉ VALEUR / m14_oublier EXX CLÉ — petites valeurs d'état.
m14_lire() {
  local f
  f="$(m14_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m14_ecrire() {
  local d
  d="$(m14_etat "$1")"
  [[ -f "$d/$2" ]] || printf '%s\n' "$3" >"$d/$2"
}
m14_oublier() {
  local d
  d="$(m14_etat "$1")"
  rm -f -- "${d:?}/$2"
}

# m14_attendre SECONDES commande… — relance la commande toutes les 5 s jusqu'à succès ou délai.
m14_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 5
    t=$((t + 5))
  done
  "$@"
}

# m14_essayer EXX NB DÉPART — essaie les variantes à partir de DÉPART ; une variante qui renvoie 10
# est « sans effet sur ce lab » (configuration différente de celle attendue) : on passe à la suivante.
m14_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m14${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M14-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

# ---------------------------------------------------------------------------
# Objets Kubernetes : sauvegarde nettoyée et restauration (adm01, kubeconfig d'administration)
# ---------------------------------------------------------------------------

_m14_fichier_objet() { printf '%s/%s_%s_%s.json\n' "$(m14_etat "$1")" "${4:-_cluster}" "${2//\//-}" "$3"; }

# m14_sauver_objet EXX TYPE NOM [ESPACE] — une seule fois par panne ; « ABSENT » si l'objet n'existe pas.
m14_sauver_objet() {
  local ex="$1" type="$2" nom="$3" ns="${4:-}" f
  f="$(_m14_fichier_objet "$ex" "$type" "$nom" "$ns")"
  [[ -e "$f" ]] && return 0
  if wb_kubectl get "$type" "$nom" ${ns:+-n "$ns"} -o json 2>/dev/null | jq '
      del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.generation,
          .metadata.managedFields, .metadata.selfLink, .status)
      | if .metadata.annotations then .metadata.annotations |= del(."kubectl.kubernetes.io/last-applied-configuration") else . end' >"$f.tmp" 2>/dev/null &&
    [[ -s "$f.tmp" ]]; then
    mv "$f.tmp" "$f"
  else
    rm -f "$f.tmp"
    printf 'ABSENT\n' >"$f"
  fi
  chmod 600 "$f"
}

# m14_objet_sauve EXX TYPE NOM [ESPACE] — affiche la copie sauvegardée (JSON) ; code 1 si aucune.
m14_objet_sauve() {
  local f
  f="$(_m14_fichier_objet "$@")"
  [[ -s "$f" ]] && [[ "$(head -c 6 "$f")" != ABSENT ]] && cat "$f"
}

# m14_restaurer_objet EXX TYPE NOM [ESPACE] — remet la copie sauvegardée (ou supprime l'objet s'il
# n'existait pas), puis oublie la copie.
m14_restaurer_objet() {
  local ex="$1" type="$2" nom="$3" ns="${4:-}" f
  f="$(_m14_fichier_objet "$ex" "$type" "$nom" "$ns")"
  [[ -e "$f" ]] || return 0
  if [[ "$(head -c 6 "$f")" == ABSENT ]]; then
    wb_kubectl delete "$type" "$nom" ${ns:+-n "$ns"} --ignore-not-found >/dev/null 2>&1 || wb_avert "suppression de $type/$nom impossible"
  elif wb_kubectl get "$type" "$nom" ${ns:+-n "$ns"} >/dev/null 2>&1; then
    wb_kubectl replace -f "$f" >/dev/null 2>&1 || wb_avert "restauration de $type/$nom impossible (copie : $f)"
  else
    wb_kubectl create -f "$f" >/dev/null 2>&1 || wb_avert "recréation de $type/$nom impossible (copie : $f)"
  fi
  rm -f -- "$f"
}

# m14_oublier_objet EXX TYPE NOM [ESPACE] — efface la copie sans rien restaurer.
m14_oublier_objet() { rm -f -- "$(_m14_fichier_objet "$@")"; }

# m14_depuis EXX — date de début de l'injection (epoch), mémorisée une fois.
m14_debut() { m14_ecrire "$1" debut "$(date +%s)"; }

# m14_pods_json [ESPACE] — pods de l'espace (défaut wb-pannes) en JSON.
m14_pods_json() { wb_kubectl -n "${1:-$_M14_NS}" get pods -o json 2>/dev/null; }

# m14_nouveau_pod_etat EXX APP 'filtre jq' — 0 si un pod de l'application APP créé depuis le début de
# l'injection satisfait le filtre (appliqué à chaque pod).
m14_nouveau_pod_etat() {
  local debut
  debut="$(m14_lire "$1" debut)"
  m14_pods_json "$_M14_NS" | jq -e --arg app "$2" --argjson t "${debut:-0}" "
    [.items[] | select(.metadata.labels[\"app.kubernetes.io/name\"] == \$app)
              | select((.metadata.creationTimestamp | fromdateiso8601) >= (\$t - 5))
              | select($3)] | length > 0" >/dev/null 2>&1
}

# Filtres jq usuels sur un pod
# shellcheck disable=SC2034
{
  _M14_JQ_PENDING='.status.phase == "Pending" and ([.status.conditions[]? | select(.type == "PodScheduled" and .status == "False")] | length > 0)'
  _M14_JQ_PULL='[.status.containerStatuses[]?.state.waiting.reason // empty] | any(. == "ErrImagePull" or . == "ImagePullBackOff")'
  _M14_JQ_CRASH='[.status.containerStatuses[]? | (.restartCount >= 1) or ((.state.waiting.reason // "") | test("CrashLoopBackOff|RunContainerError|CreateContainerError|StartError"))] | any'
}

# m14_evenement_depuis EXX ESPACE RAISON 'regex message' — un événement récent correspond.
m14_evenement_depuis() {
  local debut
  debut="$(m14_lire "$1" debut)"
  wb_kubectl -n "$2" get events -o json 2>/dev/null | jq -e --arg r "$3" --arg m "$4" --argjson t "${debut:-0}" '
    [.items[] | select(.reason == $r) | select((.message // "") | test($m))
              | select(((.lastTimestamp // .metadata.creationTimestamp) | fromdateiso8601) >= ($t - 5))] | length > 0' >/dev/null 2>&1
}

# m14_deploiement_pret ESPACE NOM — déploiement entièrement à jour et disponible.
m14_deploiement_pret() {
  wb_kubectl -n "$1" get deploy "$2" -o json 2>/dev/null | jq -e '
    (.spec.replicas // 1) as $n
    | (.status.updatedReplicas // 0) == $n and (.status.availableReplicas // 0) == $n
      and (.status.replicas // 0) == $n and (.status.observedGeneration // 0) >= .metadata.generation' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Exécution distante sur les nœuds
# ---------------------------------------------------------------------------
# Aide ajoutée devant chaque script distant (en plus du prélude de pannes-lib) :
#   crictl_          crictl sur le socket de containerd ;
#   etcdctl_ ARGS    etcdctl avec les certificats du nœud (healthcheck-client), entrée standard fermée ;
#   etcdctl_entree   idem, avec l'entrée standard (pour « put » d'une valeur lue sur stdin) ;
#   oublier_fichiers efface les sauvegardes faites par sauver() sans rien restaurer.
# etcdctl est celui du nœud s'il existe (M14-E24), sinon celui du conteneur etcd (crictl exec).
read -r -d '' _M14_AIDE <<'AIDE' || true
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
crictl_() { crictl --runtime-endpoint unix:///run/containerd/containerd.sock "$@"; }
_etcd_opts() {
  local p=/etc/kubernetes/pki/etcd
  printf '%s\n' --cacert "$p/ca.crt" --cert "$p/healthcheck-client.crt" --key "$p/healthcheck-client.key" \
    --dial-timeout=5s --command-timeout=30s
}
_etcd_cmd() {
  local entree="$1" id; shift
  local -a o; mapfile -t o < <(_etcd_opts)
  if command -v etcdctl >/dev/null 2>&1; then
    if [ "$entree" = 1 ]; then ETCDCTL_API=3 etcdctl "${o[@]}" "$@"; else ETCDCTL_API=3 etcdctl "${o[@]}" "$@" </dev/null; fi
  else
    id="$(crictl_ ps -q --name '^etcd$' --state Running 2>/dev/null </dev/null | head -n 1)"
    [ -n "$id" ] || { echo "etcdctl introuvable et conteneur etcd local arrêté" >&2; return 1; }
    if [ "$entree" = 1 ]; then crictl_ exec -i "$id" etcdctl "${o[@]}" "$@"; else crictl_ exec "$id" etcdctl "${o[@]}" "$@" </dev/null; fi
  fi
}
etcdctl_() { _etcd_cmd 0 "$@"; }
etcdctl_entree() { _etcd_cmd 1 "$@"; }
oublier_fichiers() {
  local m="$WB_DIR/$WB_EX.manifeste" src dst
  [ -f "$m" ] || return 0
  while IFS="$(printf '\t')" read -r src dst; do
    [ "$dst" = ABSENT ] || rm -f -- "$dst"
  done < "$m"
  rm -f "$m"
}
# attendre_etcd_local SECONDES — le membre etcd local répond (endpoint health).
attendre_etcd_local() {
  local t=0
  while [ "$t" -lt "$1" ]; do
    etcdctl_ endpoint health >/dev/null 2>&1 && return 0
    sleep 5; t=$((t + 5))
  done
  return 1
}
AIDE

# m14_wb_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec avec l'aide ci-dessus.
m14_wb_exec() {
  local h="$1"
  shift
  { printf '%s\n' "$_M14_AIDE"; cat; } | wb_exec "$h" "$@"
}

# m14_wb_exec_invite HÔTE [VAR=valeur…] <<'EOF' … EOF — par l'agent QEMU (sans SSH).
m14_wb_exec_invite() {
  local h="$1"
  shift
  { printf '%s\n' "$_M14_AIDE"; cat; } | wb_exec_invite "${_M14_VMID[$h]}" "$@"
}

# m14_ssh HÔTE 'commande' — commande courte en root sur un nœud (sortie standard).
m14_ssh() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null; }

# m14_etcd_relais [EXCLU] — premier nœud de contrôle joignable (hors EXCLU) dont etcd répond.
m14_etcd_relais() {
  local h
  for h in "${_M14_CP[@]}"; do
    [[ "$h" == "${1:-}" ]] && continue
    if m14_wb_exec "$h" >/dev/null 2>&1 <<'EOF'; then
etcdctl_ endpoint health >/dev/null 2>&1
EOF
      printf '%s\n' "$h"
      return 0
    fi
  done
  return 1
}

# m14_etcd_points — liste des points d'accès clients des trois membres.
m14_etcd_points() {
  local h l=""
  for h in "${_M14_CP[@]}"; do l+="${l:+,}https://${_M14_IP[$h]}:2379"; done
  printf '%s\n' "$l"
}

# m14_etcd_membre_sain HÔTE [RELAIS] — le membre de HÔTE répond, vu depuis un autre nœud.
m14_etcd_membre_sain() {
  local h="$1" r="${2:-}"
  [[ -n "$r" ]] || r="$(m14_etcd_relais "$h")" || return 1
  m14_wb_exec "$r" EP="https://${_M14_IP[$h]}:2379" >/dev/null 2>&1 <<'EOF'
etcdctl_ --endpoints="$EP" endpoint health >/dev/null 2>&1
EOF
}

# m14_vip_porteur — nœud de contrôle qui porte la VIP de l'API.
m14_vip_porteur() {
  local h
  for h in "${_M14_CP[@]}"; do
    if remote "$h" "ip -4 -o addr show | grep -qw $_M14_VIP" </dev/null >/dev/null 2>&1; then
      printf '%s\n' "$h"
      return 0
    fi
  done
  return 1
}

# m14_api_repond — une réponse HTTP (quel que soit son code) arrive de l'API par la VIP.
m14_api_repond() {
  local c
  c="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 6 "https://$_M14_VIP:8443/livez" 2>/dev/null)" || true
  [[ -n "$c" && "$c" != 000 ]]
}
m14_api_muette() { ! m14_api_repond; }

# m14_apiserver_sain HÔTE — /livez du kube-apiserver du nœud (port 6443) répond 200.
m14_apiserver_sain() {
  [[ "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 6 "https://${_M14_IP[$1]}:6443/livez" 2>/dev/null)" == 200 ]]
}

# m14_noeud_pret NŒUD — condition Ready vraie.
m14_noeud_pret() {
  wb_kubectl get node "$1" -o json 2>/dev/null | jq -e '[.status.conditions[] | select(.type == "Ready" and .status == "True")] | length == 1' >/dev/null 2>&1
}
m14_noeud_pas_pret() { ! m14_noeud_pret "$1"; }

# m14_hasard LISTE… — un élément au hasard.
m14_hasard() { local -a l=("$@"); printf '%s\n' "${l[RANDOM % ${#l[@]}]}"; }

# ---------------------------------------------------------------------------
# Santé avant injection
# ---------------------------------------------------------------------------

# m14_sain — refuse de casser un cluster qui ne va pas bien.
m14_sain() {
  local h nb
  if ! m14_api_repond; then
    echo "L'API du cluster ne répond pas par la VIP $_M14_VIP:8443 : répare d'abord (lab/bin/check 14 39)." >&2
    return 1
  fi
  nb="$(wb_kubectl get nodes -o json 2>/dev/null | jq '[.items[] | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length' 2>/dev/null)" || nb=0
  if ((${nb:-0} < ${#_M14_CP[@]} + ${#_M14_W[@]})); then
    echo "Tous les nœuds ne sont pas Ready (kubectl get nodes) : rien n'est cassé." >&2
    return 1
  fi
  for h in "${_M14_CP[@]}"; do
    if ! m14_etcd_membre_sain "$h"; then
      echo "Le membre etcd de $h ne répond pas : rien n'est cassé (lab/bin/check 14 40)." >&2
      return 1
    fi
  done
  return 0
}

# ---------------------------------------------------------------------------
# Témoins (espace wb-pannes)
# ---------------------------------------------------------------------------

# m14_image_agenda — image MédiAgenda à utiliser : WB_M14_IMAGE_AGENDA, sinon celle qui tourne le plus
# dans le cluster (hors wb-pannes), sinon la dernière étiquette v* du dépôt Harbor.
m14_image_agenda() {
  local img tag
  if [[ -n "${WB_M14_IMAGE_AGENDA:-}" ]]; then
    printf '%s\n' "$WB_M14_IMAGE_AGENDA"
    return 0
  fi
  img="$(wb_kubectl get pods -A -o json 2>/dev/null | jq -r --arg ns "$_M14_NS" '
    [.items[] | select(.metadata.namespace != $ns) | .spec.containers[].image
     | select(test("/medisphere/mediagenda-api[:@]"))] | group_by(.) | max_by(length) | .[0] // empty' 2>/dev/null)"
  if [[ -n "$img" ]]; then
    printf '%s\n' "$img"
    return 0
  fi
  tag="$(harbor_api 'projects/medisphere/repositories/mediagenda-api/artifacts?with_tag=true&page_size=30&sort=-push_time' 2>/dev/null |
    jq -r '[.[].tags[]?.name | select(test("^v[0-9]"))][0] // empty' 2>/dev/null)"
  [[ -n "$tag" ]] || return 1
  printf '%s/medisphere/mediagenda-api:%s\n' "$_M14_REGISTRE" "$tag"
}

# m14_temoins_prets — les cinq déploiements témoins sont disponibles.
m14_temoins_prets() {
  local d
  for d in postgres valkey agenda sonde-api sonde-dns; do
    m14_deploiement_pret "$_M14_NS" "$d" || return 1
  done
}

# m14_temoins — crée les témoins s'ils n'existent pas, puis attend qu'ils soient prêts.
m14_temoins() {
  local img src mdp
  if ! wb_kubectl get deploy agenda -n "$_M14_NS" >/dev/null 2>&1; then
    echo "Première injection du palier 4 : création des témoins dans l'espace $_M14_NS (2 à 5 min)…"
    img="$(m14_image_agenda)" || {
      echo "Image MédiAgenda introuvable (aucun pod ni étiquette v* dans Harbor) : renseigne WB_M14_IMAGE_AGENDA dans lab/lab.env." >&2
      return 1
    }
    src="$(wb_kubectl get secrets -A --field-selector metadata.name=harbor-pull -o json 2>/dev/null |
      jq -r --arg ns "$_M14_NS" '[.items[] | select(.metadata.namespace != $ns and .type == "kubernetes.io/dockerconfigjson") | .metadata.namespace][0] // empty')"
    [[ -n "$src" ]] || {
      echo "Aucun Secret « harbor-pull » de type dockerconfigjson dans le cluster (M14-E19) : témoins impossibles." >&2
      return 1
    }
    # L'espace d'abord (premier document du fichier), puis un essai à blanc de tout le reste.
    awk '/^---$/ {exit} {print}' "$_M14_DIR/_m14-temoins.yaml" | wb_kubectl apply -f - >/dev/null || return 1
    if ! sed -e "s|__IMAGE_AGENDA__|$img|g" -e "s|__REGISTRE__|$_M14_REGISTRE|g" "$_M14_DIR/_m14-temoins.yaml" |
      wb_kubectl apply -f - --dry-run=server >/dev/null; then
      echo "Les témoins sont refusés par l'API (admission ?) : rien n'a été créé." >&2
      wb_kubectl delete namespace "$_M14_NS" --wait=false >/dev/null 2>&1 || true
      return 1
    fi
    wb_kubectl get secret harbor-pull -n "$src" -o json |
      jq --arg ns "$_M14_NS" '{apiVersion, kind, type, data, metadata: {name: "harbor-pull", namespace: $ns}}' |
      wb_kubectl apply -f - >/dev/null || return 1
    mdp="$(openssl rand -hex 24)"
    jq -n --arg ns "$_M14_NS" --arg p "$mdp" '{apiVersion: "v1", kind: "Secret", type: "Opaque",
        metadata: {name: "agenda-db", namespace: $ns},
        stringData: {motdepasse: $p, url: ("postgresql://mediagenda:" + $p + "@postgres:5432/mediagenda")}}' |
      wb_kubectl apply -f - >/dev/null || return 1
    sed -e "s|__IMAGE_AGENDA__|$img|g" -e "s|__REGISTRE__|$_M14_REGISTRE|g" "$_M14_DIR/_m14-temoins.yaml" |
      wb_kubectl apply -f - >/dev/null || return 1
  fi
  if ! m14_attendre 300 m14_temoins_prets; then
    echo "Les témoins de $_M14_NS ne sont pas prêts (kubectl -n $_M14_NS get pods) : rien n'est cassé." >&2
    return 1
  fi
}

# m14_preparer — précondition commune : cluster sain, puis témoins prêts (créés au besoin). Pendant
# l'astreinte (M14-E43, _M14_ASTREINTE=1), break-E43 a fait ces contrôles une fois avant la première
# panne : les refaire ici échouerait à cause de la panne précédente.
m14_preparer() {
  if [[ -n "${_M14_ASTREINTE:-}" ]]; then return 0; fi
  m14_sain || return 1
  m14_temoins
}
