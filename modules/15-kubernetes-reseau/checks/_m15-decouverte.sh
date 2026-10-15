# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes distantes entre apostrophes (évaluées sur le nœud)
# _m15-decouverte.sh — fonctions partagées par les checks M15-E02 à M15-E08 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m15d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès : « kube » (kubectl avec le compte de service wb-checks, lecture seule, sans les Secrets),
# SSH « admin » vers les nœuds avec « sudo -n » pour LIRE les règles du noyau, API GitLab en GET,
# requêtes HTTP de test vers les NodePort depuis adm01.
# Variables de lab/lab.env : WB_K8S_KUBECONFIG, WB_K8S_CP, WB_K8S_WORKERS (module 14).

_M15D_NS="wb-essais"
_M15D_PROJET_K8S="projects/plateforme%2Fk8s"
_M15D_PROJET_DOC="projects/plateforme%2Fmedisphere"
_M15D_PROJET_ANSIBLE="projects/plateforme%2Fansible"
read -r -a _M15D_CP <<<"${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
read -r -a _M15D_WORKERS <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
_M15D_NOEUDS=("${_M15D_CP[@]}" "${_M15D_WORKERS[@]}")
_M15D_GW_API_VERSION="v1.6.1"

# _m15d_get ARGS… — « kube get ARGS -o json » ; sortie vide si l'objet n'existe pas ou si l'API ne répond pas.
_m15d_get() {
  kube get "$@" -o json 2>/dev/null || true
}

# _m15d_json JSON FILTRE [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné (non vide).
_m15d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m15d_absent ARGS… — OK si « kube get ARGS » répond NotFound (et pas une autre erreur : un cluster
# injoignable ne doit pas faire passer un contrôle d'absence).
_m15d_absent() {
  local sortie
  sortie="$(kube get "$@" 2>&1)" && return 1
  grep -q 'NotFound' <<<"$sortie"
}

# _m15d_cilium_cfg CLÉ — valeur d'une clé de la ConfigMap kube-system/cilium-config (vide si absente).
_m15d_cilium_cfg() {
  kube -n kube-system get configmap cilium-config -o json 2>/dev/null \
    | jq -r --arg k "$1" '.data[$k] // ""' 2>/dev/null || true
}

# _m15d_ip_noeud NOM — adresse InternalIP d'un nœud.
_m15d_ip_noeud() {
  kube get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true
}

# _m15d_noeuds_echo — noms des nœuds qui portent un pod echo prêt (un par ligne).
_m15d_noeuds_echo() {
  kube -n "$_M15D_NS" get pods -l app=echo -o json 2>/dev/null | jq -r '
    .items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True")) | .spec.nodeName' \
    2>/dev/null | sort -u || true
}

# _m15d_fichier_main PROJET CHEMIN — le fichier existe sur la branche main du projet GitLab.
_m15d_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m15d_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m15d_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m15d_arbre_main PROJET DOSSIER — noms des fichiers d'un dossier sur main (un par ligne).
_m15d_arbre_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/tree?path=$chemin&ref=main&per_page=100" 2>/dev/null \
    | jq -r '.[] | select(.type == "blob") | .name' 2>/dev/null || true
}

# _m15d_doc_main MOTIF_REGEX — un fichier de docs/kubernetes/reseau/ sur main a un nom qui correspond.
_m15d_doc_main() {
  _m15d_arbre_main "$_M15D_PROJET_DOC" "docs/kubernetes/reseau" | grep -Eq -- "$1"
}

# _m15d_regles_noeud NŒUD — règles netfilter du nœud (nft et iptables, nft et legacy), lues avec sudo.
_m15d_regles_noeud() {
  remote "$1" 'sudo -n sh -c "nft list ruleset 2>/dev/null; for b in iptables ip6tables iptables-legacy ip6tables-legacy; do command -v \$b-save >/dev/null 2>&1 && \$b-save 2>/dev/null; done; true"' 2>/dev/null || true
}

# _m15d_http_code URL [OPTIONS curl…] — code HTTP (ou 000), sans jamais échouer.
_m15d_http_code() {
  local url="$1"
  shift
  curl -s -o /dev/null -w '%{http_code}' --max-time "${WB_TIMEOUT:-5}" "$@" "$url" 2>/dev/null || true
}

# _m15d_agents_a_jour — OK si chaque agent Cilium a démarré APRÈS la dernière modification de la
# ConfigMap cilium-config (date la plus récente de ses managedFields). Sinon, un agent tourne encore
# avec l'ancienne configuration (rollOutCiliumPods vaut false : il faut redémarrer les agents).
_m15d_agents_a_jour() {
  local cm pods
  cm="$(kube -n kube-system get configmap cilium-config -o json 2>/dev/null || true)"
  pods="$(kube -n kube-system get pods -l k8s-app=cilium -o json 2>/dev/null || true)"
  [[ -n "$cm" && -n "$pods" ]] || return 1
  jq -e -n --argjson cm "$cm" --argjson p "$pods" '
    ([$cm.metadata.managedFields[]?.time // empty] | max) as $modif
    | ($p.items | length) > 0 and $modif != null
      and all($p.items[]; ([.status.containerStatuses[]? | select(.name == "cilium-agent")
                            | .state.running.startedAt // empty][0] // "") > $modif)' >/dev/null 2>&1
}

# _m15d_depot_a FICHIER_REGEX PROJET DOSSIER — un fichier du dossier (sur main) a un nom qui correspond.
_m15d_depot_a() {
  _m15d_arbre_main "$2" "$3" | grep -Eqi -- "$1"
}

# _m15d_yq_vrai EXPRESSION TEXTE_YAML — OK si l'expression yq (mikefarah, -e) est vraie sur le YAML
# donné (non vide). Plusieurs documents : l'expression est évaluée sur chacun.
_m15d_yq_vrai() {
  [[ -n "$2" ]] && yq -e "$1" <<<"$2" >/dev/null 2>&1
}
