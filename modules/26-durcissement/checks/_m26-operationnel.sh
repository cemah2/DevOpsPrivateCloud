# shellcheck shell=bash
# _m26-operationnel.sh — fonctions partagées par les checks M26-E10 à M26-E16 (lecture seule).
# Sourcé par les check-EXX.sh du palier 2 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m26o_ : pas de collision avec les fonctions des autres paliers (_m26c_ pour E17-E23).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) :
#   - hôtes : SSH du compte qui lance le check (admin sur adm01), commandes de consultation ;
#     « sudo -n » seulement pour LIRE (sshd -T, auditctl -l, aa-status, test -r d'un fichier root) ;
#   - cluster : « kube » (compte wb-checks : objets de Kyverno et rapports par wb-checks-securite,
#     E07 ; ExternalSecret par M25-E12 ; jamais les Secrets) ;
#   - GitLab : gitlab_api (jeton read_api) ; Loki : loki_requete (locataire audit) ; Harbor : harbor_api ;
#   - pve01 : « qm list » en consultation (root, comme les checks des modules précédents).
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_M26_DURCI_DEB    nom SSH de la VM d'essai Debian   (durci-deb)
#   WB_M26_DURCI_ROCKY  nom SSH de la VM d'essai Rocky    (durci-rocky)
#   WB_M26_TEMOIN_DEB   hôte Debian durci qui la remplace après E14 (mon01)
#   WB_M26_TEMOIN_ROCKY hôte Rocky durci qui la remplace après E14 (ceph01)
#   WB_M26_SOCLE        hôtes des vagues 1 à 6 (liste séparée par des espaces)

_M26O_DEB="${WB_M26_DURCI_DEB:-durci-deb}"
_M26O_ROCKY="${WB_M26_DURCI_ROCKY:-durci-rocky}"
_M26O_TEMOIN_DEB="${WB_M26_TEMOIN_DEB:-mon01}"
_M26O_TEMOIN_ROCKY="${WB_M26_TEMOIN_ROCKY:-ceph01}"
_M26O_SOCLE="${WB_M26_SOCLE:-mon01 nbx01 s3-01 dns02 runner01 runner02 reg01 dns01 ca01 git01 idp01 vault01 vault02 vault03 kms01 ipa01 lb02 lb01 gw02 gw01 k8s-w01 k8s-w02 k8s-w03 k8s-cp01 k8s-cp02 k8s-cp03 ceph01 ceph02 ceph03 adm01}"
_M26O_P_ANSIBLE="plateforme/ansible"
_M26O_P_DOC="plateforme/medisphere"
_M26O_P_POLITIQUES="plateforme/politiques"
_M26O_DOC_DURCI="docs/securite/durcissement"
_M26O_TRAVAIL="$HOME/m26"
_M26O_PVE="${WB_PVE_HOST:-pve01}"

# _m26o_k ARGS… — kubectl en lecture par le compte des checks (sortie vide en cas d'erreur).
_m26o_k() { kube "$@" 2>/dev/null || true; }

# _m26o_json JSON [--arg NOM VALEUR]… FILTRE_JQ — OK si le filtre jq (-e), DERNIER argument, est
#   vrai sur le JSON donné ; les arguments intermédiaires sont passés à jq.
_m26o_json() {
  local donnees="$1"
  shift
  local filtre="${*: -1}"
  local -a options=("${@:1:$#-1}")
  [[ -n "$donnees" ]] && jq -e "${options[@]}" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m26o_uri TEXTE — encodage pour une URL.
_m26o_uri() { jq -rn --arg v "$1" '$v | @uri'; }

# _m26o_fichier PROJET CHEMIN [BRANCHE=main] — le fichier existe sur la branche.
_m26o_fichier() {
  gitlab_api "projects/$(_m26o_uri "$1")/repository/files/$(_m26o_uri "$2")?ref=$(_m26o_uri "${3:-main}")" >/dev/null 2>&1
}

# _m26o_contenu PROJET CHEMIN [BRANCHE=main] — contenu brut (vide si absent).
_m26o_contenu() {
  gitlab_api "projects/$(_m26o_uri "$1")/repository/files/$(_m26o_uri "$2")/raw?ref=$(_m26o_uri "${3:-main}")" 2>/dev/null || true
}

# _m26o_contient PROJET CHEMIN REGEX — le fichier de main contient une ligne qui correspond.
_m26o_contient() {
  grep -Eq -- "$3" <<<"$(_m26o_contenu "$1" "$2")"
}

# _m26o_arbre PROJET CHEMIN — fichiers sous CHEMIN sur main (récursif, un par ligne).
_m26o_arbre() {
  gitlab_api "projects/$(_m26o_uri "$1")/repository/tree?ref=main&recursive=true&per_page=100&path=$(_m26o_uri "$2")" 2>/dev/null \
    | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
}

# _m26o_job_ok PROJET JOB — le dernier pipeline de main a réussi et contient le job JOB, réussi.
_m26o_job_ok() {
  local p id
  p="$(gitlab_api "projects/$(_m26o_uri "$1")/pipelines?ref=main&per_page=1" 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null || true)"
  _m26o_json "$p" '.status == "success"' || return 1
  id="$(jq -r '.id' <<<"$p")"
  gitlab_api "projects/$(_m26o_uri "$1")/pipelines/$id/jobs?per_page=100" 2>/dev/null \
    | jq -e --arg j "$2" 'any(.[]; .name == $j and .status == "success")' >/dev/null 2>&1
}

# _m26o_joignable HÔTE — l'hôte répond en SSH (commande vide).
_m26o_joignable() { remote "$1" true >/dev/null 2>&1; }

# _m26o_essai deb|rocky — hôte sur lequel vérifier le rôle : la VM d'essai si elle existe encore,
#   sinon un hôte du socle durci (après E14, les VMs d'essai sont détruites).
_m26o_essai() {
  if [[ "$1" == deb ]]; then
    if _m26o_joignable "$_M26O_DEB"; then echo "$_M26O_DEB"; else echo "$_M26O_TEMOIN_DEB"; fi
  else
    if _m26o_joignable "$_M26O_ROCKY"; then echo "$_M26O_ROCKY"; else echo "$_M26O_TEMOIN_ROCKY"; fi
  fi
}

# _m26o_travail FICHIER REGEX — le fichier de travail (~/m26/…) existe et contient la regex.
_m26o_travail() {
  [[ -s "$_M26O_TRAVAIL/$1" ]] && grep -Eqi -- "$2" "$_M26O_TRAVAIL/$1"
}

# _m26o_loki_nb 'LogQL' [locataire=audit] [depuis=24h] — nombre de lignes renvoyées (0 si rien/erreur).
_m26o_loki_nb() {
  local n
  n="$(loki_requete "$1" "${2:-audit}" "${3:-24h}" 2>/dev/null \
    | jq -r '[.data.result[]?.values[]?] | length' 2>/dev/null || true)"
  echo "${n:-0}"
}

# _m26o_politique TYPE NOM — JSON d'une politique Kyverno CEL (vide si absente ou illisible).
#   TYPE : validatingpolicies, mutatingpolicies, generatingpolicies, imagevalidatingpolicies.
_m26o_politique() {
  _m26o_k get "$1.policies.kyverno.io" "$2" -o json
}

# _m26o_echecs_rapport POLITIQUE ESPACE — nombre de résultats « fail » de la politique dans les
#   PolicyReport de l'espace (wgpolicyk8s.io/v1alpha2) ; vide si les rapports sont illisibles.
_m26o_echecs_rapport() {
  _m26o_k get policyreports.wgpolicyk8s.io -n "$2" -o json \
    | jq -r --arg p "$1" '[.items[]?.results[]? | select(.policy == $p and .result == "fail")] | length' 2>/dev/null || true
}

# _m26o_vm_absente VMID — pve01 répond à « qm list » et le VMID n'y figure pas.
_m26o_vm_absente() {
  local liste
  liste="$(remote "$_M26O_PVE" 'qm list' 2>/dev/null || true)"
  grep -q 'VMID' <<<"$liste" && ! awk '{print $1}' <<<"$liste" | grep -qx "$1"
}
