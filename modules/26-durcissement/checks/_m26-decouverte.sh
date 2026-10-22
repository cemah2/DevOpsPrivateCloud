# shellcheck shell=bash
# _m26-decouverte.sh — fonctions partagées par les checks M26-E03 à M26-E08 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m26d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) :
#   - VMs : SSH en admin, commandes de consultation seulement (sudo -n en lecture) ;
#   - Proxmox : « qm config » sur WB_PVE_HOST (lecture) ;
#   - cluster : « kube » (compte wb-checks ; ClusterRole agrégée wb-checks-securite étendue en E07
#     aux politiques et rapports de Kyverno et aux configurations de webhooks ; jamais de Secret) ;
#   - Loki (locataire audit) : loki_requete ; Prometheus : prom_requete ; GitLab : gitlab_api.
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_M26_HOTES_MESURE  VMs mesurées par Lynis en E03 (« gw01 git01 mon01 ipa01 »)
#   WB_M26_DURCI_DEB     alias SSH de la VM d'essai Debian (durci-deb)
#   WB_M26_DURCI_ROCKY   alias SSH de la VM d'essai Rocky (durci-rocky)
#   WB_M26_NOEUDS        nombre de nœuds de k8s-par1 (6)

read -r -a _M26D_HOTES <<<"${WB_M26_HOTES_MESURE:-gw01 git01 mon01 ipa01}"
_M26D_DEB="${WB_M26_DURCI_DEB:-durci-deb}"
_M26D_ROCKY="${WB_M26_DURCI_ROCKY:-durci-rocky}"
_M26D_NOEUDS="${WB_M26_NOEUDS:-6}"
_M26D_DEPOT_DOC=plateforme/medisphere
_M26D_DOC=docs/securite/durcissement
_M26D_REGISTRE='registry.par1.medisphere.internal/'

# _m26d_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m26d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m26d_uri TEXTE — encodage pour une URL (chemins GitLab).
_m26d_uri() {
  jq -rn --arg v "$1" '$v | @uri'
}

# _m26d_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m26d_contenu_main() {
  gitlab_api "projects/$(_m26d_uri "$1")/repository/files/$(_m26d_uri "$2")/raw?ref=main" 2>/dev/null || true
}

# _m26d_arbre_main PROJET CHEMIN — noms des fichiers du dossier sur main (un par ligne, vide si absent).
_m26d_arbre_main() {
  gitlab_api "projects/$(_m26d_uri "$1")/repository/tree?path=$(_m26d_uri "$2")&ref=main&per_page=100" 2>/dev/null \
    | jq -r '.[] | select(.type == "blob") | .name' 2>/dev/null || true
}

# _m26d_pipeline_main PROJET — statut du dernier pipeline de main (vide si aucun).
_m26d_pipeline_main() {
  gitlab_api "projects/$(_m26d_uri "$1")/pipelines?ref=main&per_page=1" 2>/dev/null \
    | jq -r '.[0].status // empty' 2>/dev/null || true
}

# _m26d_doc NOM — contenu d'un document de docs/securite/durcissement/ sur main (vide si absent).
_m26d_doc() {
  _m26d_contenu_main "$_M26D_DEPOT_DOC" "$_M26D_DOC/$1"
}

# _m26d_contient TEXTE REGEX — le texte correspond à la regex étendue (sans afficher le texte).
_m26d_contient() {
  [[ -n "$1" ]] && grep -Eq -- "$2" <<<"$1"
}

# _m26d_ligne_avec TEXTE MOT REGEX — une même ligne du texte contient MOT et correspond à REGEX.
_m26d_ligne_avec() {
  [[ -n "$1" ]] && grep -F -- "$2" <<<"$1" | grep -Eq -- "$3"
}

# _m26d_ssh HÔTE COMMANDE — sortie d'une commande de consultation sur une VM (vide si échec).
_m26d_ssh() {
  remote "$1" "$2" 2>/dev/null || true
}

# _m26d_k ARGS… — kubectl en lecture par le compte des checks (sortie vide en cas d'erreur).
_m26d_k() {
  kube "$@" 2>/dev/null || true
}

# _m26d_lisible RESSOURCE — le compte des checks peut lister ce type (RBAC, CRD installée).
_m26d_lisible() {
  kube get "$1" -A -o name >/dev/null 2>&1
}

# _m26d_app_saine NOM — Application Argo CD Synced et Healthy.
_m26d_app_saine() {
  _m26d_json "$(_m26d_k -n argocd get applications.argoproj.io "$1" -o json)" \
    '.status.sync.status == "Synced" and .status.health.status == "Healthy"'
}

# _m26d_images_harbor ESPACE — toutes les images des pods de l'espace (conteneurs, init) viennent de Harbor.
_m26d_images_harbor() {
  # shellcheck disable=SC2016  # $r est une variable jq
  _m26d_json "$(_m26d_k -n "$1" get pods -o json)" \
    '(.items | length) > 0 and ([.items[].spec | (.containers + (.initContainers // []))[].image
       | startswith($r)] | all)' --arg r "$_M26D_REGISTRE"
}

# _m26d_valeur 'PromQL' — première valeur du résultat (vide si pas de résultat ou erreur).
_m26d_valeur() {
  prom_requete "$1" 2>/dev/null \
    | jq -r 'if .status == "success" then (.data.result[0].value[1] // empty) else empty end' 2>/dev/null || true
}

# _m26d_au_moins 'PromQL' N — la première valeur du résultat est >= N.
_m26d_au_moins() {
  local v
  v="$(_m26d_valeur "$1")"
  [[ -n "$v" ]] && awk -v v="$v" -v n="$2" 'BEGIN { exit !(v + 0 >= n + 0) }'
}

# _m26d_loki_flux 'LogQL' [depuis=168h] — nombre de flux renvoyés par Loki (locataire audit).
_m26d_loki_flux() {
  loki_requete "$1" audit "${2:-168h}" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo 0
}
