# shellcheck shell=bash
# _m15-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du
# module 15 (check-E35 à check-E46). Sourcé par ces scripts, jamais lancé seul.
# Lecture seule : « kube » (compte de service wb-checks, sans accès aux Secrets), requêtes HTTPS et
# DNS depuis adm01, commandes de consultation par SSH (vtysh « show », ip, nft list, crictl exec
# de cilium-health status) sur la bordure et les nœuds.
# Préfixe _m15x_ : évite les collisions quand check-E43 et check-E46 chargent plusieurs checks.

_m15x_ns_app=mediagenda-recette
_m15x_route=mediagenda
_m15x_hote=mediagenda-recette.apps.par1.medisphere.internal
_m15x_zone=apps.par1.medisphere.internal
_m15x_gw=gw-par1
_m15x_gw_ns=passerelles
_m15x_gw_ip=10.10.41.10
_m15x_pool=lb-par1
_m15x_bgp=bgp-par1
_m15x_ca=/usr/local/share/ca-certificates/medisphere-root-ca.crt
_m15x_depot="${WB_DEPOT:-$HOME/medisphere}"
# shellcheck disable=SC2034  # utilisée par les checks qui sourcent ce fichier
read -r -a _m15x_travailleurs <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
# shellcheck disable=SC2034
_m15x_passerelles=(gw01 gw02)

# _m15x_jq 'filtre' ARGS… — 0 si le filtre jq est vrai sur « kube get ARGS -o json ».
_m15x_jq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# _m15x_https CHEMIN [HÔTE] — code HTTP d'une requête HTTPS depuis adm01 (magasin de CA du système).
_m15x_https() {
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "https://${2:-$_m15x_hote}$1" 2>/dev/null || true
}
_m15x_https_200() { [[ "$(_m15x_https "$@")" == 200 ]]; }

# _m15x_https_stable N — N requêtes successives sur /pret, toutes en 200 (pannes intermittentes).
_m15x_https_stable() {
  local i
  for ((i = 0; i < $1; i++)); do
    _m15x_https_200 /pret || return 1
  done
}

# _m15x_service_app — Service visé par la route mediagenda.
_m15x_service_app() {
  kube -n "$_m15x_ns_app" get httproute "$_m15x_route" -o jsonpath='{.spec.rules[0].backendRefs[0].name}' 2>/dev/null
}

# _m15x_selecteur_service NS SVC — sélecteur « k=v,k2=v2 » du Service.
_m15x_selecteur_service() {
  kube -n "$1" get svc "$2" -o json 2>/dev/null | jq -r '.spec.selector // {} | to_entries | map("\(.key)=\(.value)") | join(",")'
}

# _m15x_route_acceptee NS ROUTE — la route est acceptée par gw-par1 et ses références résolues.
_m15x_route_acceptee() {
  kube -n "$1" get httproute "$2" -o json 2>/dev/null | jq -e --arg g "$_m15x_gw" '
    [.status.parents[]? | select(.parentRef.name == $g) | .conditions[]? | select(.status == "True") | .type]
    | (index("Accepted") != null) and (index("ResolvedRefs") != null)' >/dev/null 2>&1
}

# _m15x_dig NOM [TYPE] [SERVEUR] — réponse courte d'un autoritaire (dns01 par défaut), port 5300
# (le port 53 de dns01/dns02 est celui du récurseur, M06-E07), sans récursion ni cache.
_m15x_dig() { dig +short +norec +time="$WB_TIMEOUT" +tries=1 -p 5300 "@${3:-10.10.20.10}" "$1" "${2:-A}" 2>/dev/null; }

# _m15x_refus_par_defaut ESPACE — une NetworkPolicy de l'espace sélectionne tous les pods, couvre
# Ingress et Egress et n'autorise rien (nom libre : « refus-par-defaut » dans le corrigé de M15-E17).
_m15x_refus_par_defaut() {
  _m15x_jq '[.items[] | select((.spec.podSelector // {}) == {} and ((.spec.policyTypes // []) | index("Ingress") != null and index("Egress") != null)
    and ((.spec.ingress // []) | length == 0) and ((.spec.egress // []) | length == 0))] | length > 0' -n "$1" networkpolicies
}

# _m15x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M15-* si aucune) n'est marquée.
_m15x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M15-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M15-$e" ]] || return 1
  done
}

# _m15x_doc_commite FICHIER — le fichier existe dans le dépôt de documentation, suivi et sans
# modification en attente.
_m15x_doc_commite() {
  local f="$1"
  [[ -s "$_m15x_depot/$f" ]] || return 1
  git -C "$_m15x_depot" ls-files --error-unmatch "$f" >/dev/null 2>&1 \
    && [[ -z "$(git -C "$_m15x_depot" status --porcelain -- "$f")" ]]
}

# _m15x_doc_contient FICHIER 'regex' — le document contient le motif (grep -E, insensible à la casse).
_m15x_doc_contient() { grep -Eqi -- "$2" "$_m15x_depot/$1" 2>/dev/null; }

# _m15x_noeud HÔTE 'commande' — commande de lecture en root (sudo -n) sur un nœud ou une passerelle.
_m15x_noeud() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" 2>/dev/null; }

# _m15x_sante_cilium HÔTE — « cilium-health status --probe » dans l'agent du nœud : tous joignables.
_m15x_sante_cilium() {
  local s a b
  # shellcheck disable=SC2016  # évalué sur le nœud
  s="$(_m15x_noeud "$1" 'c="$(crictl ps --name cilium-agent -q 2>/dev/null | head -n 1)"; [ -n "$c" ] && timeout 60 crictl exec "$c" cilium-health status --probe 2>/dev/null')" || return 1
  read -r a b < <(sed -nE 's/^Cluster health:[[:space:]]+([0-9]+)\/([0-9]+) reachable.*/\1 \2/p' <<<"$s" | head -n 1)
  [[ -n "${a:-}" && "$a" == "${b:-x}" ]]
}
