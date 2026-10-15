# shellcheck shell=bash
# _m15-commun.sh — fonctions partagées par les scripts de panne du module 15 (M15-E35 à M15-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_kubectl, wb_k8s_sauver, wb_exec, WB_EX…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.10 « Pannes du bloc C ») :
#   - les pannes n'agissent que sur des objets du cluster k8s-par1 dans les espaces du workbook
#     (wb-*, mediagenda-*) et des composants de plateforme (kube-system : Corefile, configuration
#     Cilium ; cert-manager ; external-dns ; passerelles), avec le kubeconfig d'administration
#     (WB_K8S_ADMIN_KUBECONFIG) ; sur les travailleurs k8s-w01-03 par SSH (admin + sudo) ;
#   - côté bordure : UNE seule passerelle, jamais celle qui porte la VIP (10.10.40.1), jamais
#     keepalived ni la VIP, et seulement la configuration courante de FRR (rien d'écrit sur disque) ;
#   - jamais pbs01, jamais pve01 ni son réseau ;
#   - chaque objet est sauvegardé avant modification (wb_k8s_sauver : YAML, convention du bloc C ;
#     plus une copie JSON utilisée pour la remise en état, voir m15_remettre) ;
#   - l'annulation ne rétablit que ce qui porte encore la marque de la panne : une réparation de
#     l'apprenant n'est jamais défaite.
#
# Témoins du palier 4 (m15_temoins), créés à la première injection et conservés :
#   - espace wb-pannes (PSA baseline) ;
#   - DaemonSet « sonde » (un pod par travailleur, image netshoot par le cache Harbor) : socat sur
#     le port 8080 répond « sonde-<nœud> » ; outils dig, curl, nc dans le même conteneur ;
#   - NetworkPolicy « sonde-interne » : trafic interne à l'espace et DNS vers kube-dns seulement.
# État local (adm01) : ~/.local/state/workbook/M15-EXX/ (valeurs d'origine non secrètes) et
# ~/.local/state/workbook/k8s/M15-EXX/ (objets sauvegardés).

_M15_NS_APP=mediagenda-recette
_M15_ROUTE=mediagenda
_M15_HOTE=mediagenda-recette.apps.par1.medisphere.internal
_M15_ZONE=apps.par1.medisphere.internal
_M15_GW=gw-par1
_M15_GW_NS=passerelles
_M15_GW_IP=10.10.41.10
_M15_POOL=lb-par1
_M15_BGP=bgp-par1
_M15_NS_TEMOINS=wb-pannes
_M15_ISSUER=step-ca-acme
_M15_IMG_SONDE="${WB_M15_IMAGE_SONDE:-registry.par1.medisphere.internal/dockerhub/nicolaka/netshoot:v0.13}"
# shellcheck disable=SC2034  # utilisée par les scripts qui sourcent ce fichier
_M15_PASSERELLES=(gw01 gw02)
read -r -a _M15_TRAVAILLEURS <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------
m15_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M15-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
m15_journal() {
  local ex="$1" d
  shift
  d="$(m15_etat "$ex")"
  printf '%s %s [M15-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}
m15_lire() {
  local f
  f="$(m15_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
# Une seule écriture par clé et par panne : on ne capture jamais un état déjà cassé.
m15_ecrire() {
  local d
  d="$(m15_etat "$1")"
  [[ -f "$d/$2" ]] || printf '%s\n' "$3" >"$d/$2"
}
m15_oublier() {
  rm -rf -- "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M15-$1" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/M15-$1"
}

# ---------------------------------------------------------------------------
# Kubernetes
# ---------------------------------------------------------------------------
m15_k() { wb_kubectl "$@"; }

# m15_attendre SECONDES commande [args…] — relance la commande toutes les 5 s jusqu'à succès.
m15_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 5
    t=$((t + 5))
  done
  "$@" >/dev/null 2>&1
}

# _m15_fichier TYPE NOM [NS] — chemin de la copie JSON (même dossier que wb_k8s_sauver).
_m15_fichier() {
  local type="$1" nom="$2" ns="${3:-}"
  printf '%s/%s_%s_%s.json\n' "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/$WB_EX" \
    "${ns:-_cluster}" "${type//\//-}" "$nom"
}

# m15_sauver TYPE NOM [NS] — sauvegarde avant modification (YAML de la convention + copie JSON).
#   Une seule fois par panne et par objet. « ABSENT » si l'objet n'existe pas.
m15_sauver() {
  local type="$1" nom="$2" ns="${3:-}" f
  wb_k8s_sauver "$type" "$nom" "$ns"
  f="$(_m15_fichier "$type" "$nom" "$ns")"
  [[ -e "$f" ]] && return 0
  if ! m15_k get "$type" "$nom" ${ns:+-n "$ns"} -o json >"$f.tmp" 2>/dev/null; then
    printf 'ABSENT\n' >"$f.tmp"
  fi
  mv "$f.tmp" "$f"
  chmod 600 "$f"
}

# m15_remettre TYPE NOM [NS] — remet l'objet sauvegardé. « kubectl replace » avec la version
#   courante de l'objet (resourceVersion) : un remplacement sans version est refusé pour les
#   ressources personnalisées (CRD Cilium, Gateway API, cert-manager) ; l'objet recréé s'il a été
#   supprimé ; supprimé s'il n'existait pas avant la panne.
m15_remettre() {
  local type="$1" nom="$2" ns="${3:-}" f rv
  f="$(_m15_fichier "$type" "$nom" "$ns")"
  [[ -f "$f" ]] || return 0
  if [[ "$(head -c 6 "$f")" == ABSENT ]]; then
    m15_k delete "$type" "$nom" ${ns:+-n "$ns"} --ignore-not-found --wait=false >/dev/null 2>&1 || true
    return 0
  fi
  rv="$(m15_k get "$type" "$nom" ${ns:+-n "$ns"} -o jsonpath='{.metadata.resourceVersion}' 2>/dev/null || true)"
  if [[ -n "$rv" ]]; then
    jq --arg rv "$rv" 'del(.status, .metadata.managedFields, .metadata.uid, .metadata.creationTimestamp, .metadata.generation)
      | .metadata.resourceVersion = $rv' "$f" | m15_k replace -f - >/dev/null 2>&1 \
      || wb_avert "remise en état de $type/$nom${ns:+ ($ns)} impossible : compare avec $f"
  else
    jq 'del(.status, .metadata.managedFields, .metadata.uid, .metadata.creationTimestamp, .metadata.generation, .metadata.resourceVersion)' "$f" \
      | m15_k create -f - >/dev/null 2>&1 || wb_avert "recréation de $type/$nom${ns:+ ($ns)} impossible : voir $f"
  fi
}

# m15_patch_json TYPE NOM NS 'filtre jq' — applique le filtre à l'objet (après sauvegarde) et
#   le remplace. Échoue (1) si le filtre ne change rien.
m15_patch_json() {
  local type="$1" nom="$2" ns="$3" filtre="$4" avant apres
  avant="$(m15_k get "$type" "$nom" ${ns:+-n "$ns"} -o json 2>/dev/null)" || return 1
  apres="$(jq "$filtre" <<<"$avant" 2>/dev/null)" || return 1
  [[ -n "$apres" ]] || return 1
  if [[ "$(jq -S '.spec, .metadata.labels, .data' <<<"$avant")" == "$(jq -S '.spec, .metadata.labels, .data' <<<"$apres")" ]]; then
    return 1
  fi
  m15_sauver "$type" "$nom" "$ns"
  jq 'del(.status, .metadata.managedFields)' <<<"$apres" | m15_k replace -f - >/dev/null 2>&1
}

# m15_service_app — Service de MédiAgenda en recette (premier backendRef de la route « mediagenda »).
m15_service_app() {
  m15_k -n "$_M15_NS_APP" get httproute "$_M15_ROUTE" -o jsonpath='{.spec.rules[0].backendRefs[0].name}' 2>/dev/null
}

# m15_deploiement_app — Deployment dont les pods portent les étiquettes du sélecteur du Service.
m15_deploiement_app() {
  local svc sel
  svc="$(m15_service_app)"
  [[ -n "$svc" ]] || return 1
  sel="$(m15_k -n "$_M15_NS_APP" get svc "$svc" -o json 2>/dev/null \
    | jq -r '.spec.selector // {} | to_entries | map("\(.key)=\(.value)") | join(",")')"
  [[ -n "$sel" ]] || return 1
  m15_k -n "$_M15_NS_APP" get deploy -o json 2>/dev/null | jq -r --arg s "$sel" '
    ($s | split(",") | map(split("=") | {key: .[0], value: .[1]}) | from_entries) as $sel
    | .items[] | select(.spec.template.metadata.labels as $l | $sel | to_entries | all(. as $e | $l[$e.key] == $e.value))
    | .metadata.name' | head -n 1
}

# m15_https CHEMIN [HÔTE] — code HTTP d'une requête HTTPS depuis adm01 (CA du système).
m15_https() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 8 "https://${2:-$_M15_HOTE}$1" 2>/dev/null || true
}
m15_entree_ok() { [[ "$(m15_https /pret)" == 200 ]]; }
m15_entree_ko() { [[ "$(m15_https /pret)" != 200 ]]; }

# m15_tcp IP PORT — connexion TCP depuis adm01.
m15_tcp() { timeout 5 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

# m15_dig NOM [TYPE] — réponse de l'autoritaire primaire (dns01, port 5300 : le 53 est celui du
# récurseur, M06-E07) pour un nom de la zone apps, sans cache.
m15_dig() { dig +short +norec +time=3 +tries=1 -p 5300 @10.10.20.10 "$1" "${2:-A}" 2>/dev/null; }

# ---------------------------------------------------------------------------
# Témoins du palier 4
# ---------------------------------------------------------------------------
m15_temoins() {
  if ! m15_k apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $_M15_NS_TEMOINS
  labels:
    pod-security.kubernetes.io/enforce: baseline
    medisphere.fr/usage: pannes-m15
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: sonde-interne
  namespace: $_M15_NS_TEMOINS
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - podSelector: {}
  egress:
    - to:
        - podSelector: {}
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - {protocol: UDP, port: 53}
        - {protocol: TCP, port: 53}
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: sonde
  namespace: $_M15_NS_TEMOINS
  labels: {app.kubernetes.io/name: sonde}
spec:
  selector:
    matchLabels: {app.kubernetes.io/name: sonde}
  template:
    metadata:
      labels: {app.kubernetes.io/name: sonde}
    spec:
      terminationGracePeriodSeconds: 2
      containers:
        - name: sonde
          image: $_M15_IMG_SONDE
          command: ["sh", "-c", "exec socat TCP-LISTEN:8080,fork,reuseaddr SYSTEM:'echo sonde-\$NOEUD'"]
          env:
            - name: NOEUD
              valueFrom: {fieldRef: {fieldPath: spec.nodeName}}
          ports:
            - {name: sonde, containerPort: 8080}
          resources:
            requests: {cpu: 10m, memory: 16Mi}
            limits: {cpu: 200m, memory: 64Mi}
EOF
  then
    wb_avert "témoins du palier 4 impossibles à créer dans $_M15_NS_TEMOINS (droits, admission ?)"
    return 1
  fi
  if ! m15_k -n "$_M15_NS_TEMOINS" rollout status ds/sonde --timeout=180s >/dev/null 2>&1; then
    wb_avert "les pods témoins de $_M15_NS_TEMOINS ne démarrent pas (image $_M15_IMG_SONDE tirée par le cache Harbor ?)"
    return 1
  fi
}

# m15_pod_temoin NŒUD — nom du pod témoin sur ce nœud ; m15_ip_temoin NŒUD — son adresse.
m15_pod_temoin() {
  m15_k -n "$_M15_NS_TEMOINS" get pods -l app.kubernetes.io/name=sonde --field-selector "spec.nodeName=$1" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}
m15_ip_temoin() {
  m15_k -n "$_M15_NS_TEMOINS" get pods -l app.kubernetes.io/name=sonde --field-selector "spec.nodeName=$1" \
    -o jsonpath='{.items[0].status.podIP}' 2>/dev/null
}

# m15_temoin_exec NŒUD commande… — commande dans le pod témoin du nœud.
m15_temoin_exec() {
  local n="$1" p
  shift
  p="$(m15_pod_temoin "$n")"
  [[ -n "$p" ]] || return 1
  m15_k -n "$_M15_NS_TEMOINS" exec "$p" -c sonde -- "$@"
}

# m15_joindre SOURCE CIBLE — le témoin de SOURCE obtient la réponse du témoin de CIBLE (TCP 8080).
m15_joindre() {
  local ip
  ip="$(m15_ip_temoin "$2")"
  [[ -n "$ip" ]] || return 1
  m15_temoin_exec "$1" sh -c "nc -w 3 $ip 8080 </dev/null | grep -q sonde-" >/dev/null 2>&1
}

# m15_inter_noeuds_ok — chaque témoin joint les témoins des autres travailleurs.
m15_inter_noeuds_ok() {
  local a b
  for a in "${_M15_TRAVAILLEURS[@]}"; do
    for b in "${_M15_TRAVAILLEURS[@]}"; do
      [[ "$a" == "$b" ]] && continue
      m15_joindre "$a" "$b" || return 1
    done
  done
}

# m15_sain — précondition : l'entrée (HTTPS de MédiAgenda recette) et le réseau entre nœuds marchent.
m15_sain() {
  local pb=()
  m15_entree_ok || pb+=("https://$_M15_HOTE/pret ne répond pas 200 depuis adm01")
  m15_inter_noeuds_ok || pb+=("les témoins de $_M15_NS_TEMOINS ne se joignent pas entre travailleurs")
  if ((${#pb[@]} == 0)); then return 0; fi
  wb_avert "le cluster n'est pas sain avant la panne : $(
    IFS=';'
    printf '%s' "${pb[*]}"
  ). Lance lab/bin/check 15 ${WB_EX#M15-E} et répare d'abord."
  return 1
}

# m15_preparer — précondition commune. Pendant l'astreinte (M15-E43, _M15_ASTREINTE=1), break-E43
# fait ces contrôles une seule fois : les refaire ici échouerait à cause de la panne précédente.
m15_preparer() {
  if [[ -n "${_M15_ASTREINTE:-}" ]]; then return 0; fi
  m15_temoins || return 1
  m15_sain
}

# m15_essayer EXX NB DÉPART — appelle _m15EXX_une N (0 : posée ; 10 : sans effet ou impossible sur
# ce lab ; autre : erreur) pour N = DÉPART, DÉPART+1… jusqu'à un succès.
m15_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m15${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M15-$ex n'est applicable sur ce lab (configuration inattendue)"
  return 1
}

# ---------------------------------------------------------------------------
# Bordure
# ---------------------------------------------------------------------------
# m15_passerelle_secours — la passerelle qui NE porte PAS la VIP 10.10.40.1 (seule cible permise).
m15_passerelle_secours() {
  local g n=0 choix=""
  for g in "${_M15_PASSERELLES[@]}"; do
    if remote "$g" "ip -4 -o addr show | grep -q ' 10\.10\.40\.1/'" >/dev/null 2>&1; then
      n=$((n + 1))
    elif remote "$g" true >/dev/null 2>&1; then
      choix="$g"
    fi
  done
  # Exactement une passerelle maître et l'autre joignable, sinon on ne touche à rien.
  ((n == 1)) && [[ -n "$choix" ]] && printf '%s\n' "$choix"
}
