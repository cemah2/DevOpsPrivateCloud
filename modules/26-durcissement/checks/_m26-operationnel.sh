# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et LogQL entre apostrophes
# _m26-operationnel.sh — fonctions partagées par les checks M26-E10 à M26-E22 (lecture seule).
# Sourcé par les check-EXX.sh du palier 2 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixes : _m26o_ (E10 à E16, hôtes et Kyverno) et _m26c_ (E17 à E22, admission, exécution, charges).
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
#   WB_M26_NOEUDS       nombre de nœuds de k8s-par1 (6)
#   WB_M26_TRAVAIL      dossier de travail du module sur adm01 (~/m26)

_M26O_DEB="${WB_M26_DURCI_DEB:-durci-deb}"
_M26O_ROCKY="${WB_M26_DURCI_ROCKY:-durci-rocky}"
_M26O_TEMOIN_DEB="${WB_M26_TEMOIN_DEB:-mon01}"
_M26O_TEMOIN_ROCKY="${WB_M26_TEMOIN_ROCKY:-ceph01}"
_M26O_SOCLE="${WB_M26_SOCLE:-mon01 nbx01 s3-01 dns02 runner01 runner02 reg01 dns01 ca01 git01 idp01 vault01 vault02 vault03 kms01 ipa01 lb02 lb01 gw02 gw01 k8s-w01 k8s-w02 k8s-w03 k8s-cp01 k8s-cp02 k8s-cp03 ceph01 ceph02 ceph03 adm01}"
_M26O_P_ANSIBLE="plateforme/ansible"
_M26O_P_DOC="plateforme/medisphere"
_M26O_P_POLITIQUES="plateforme/politiques"
_M26O_DOC_DURCI="docs/securite/durcissement"
_M26O_TRAVAIL="${WB_M26_TRAVAIL:-$HOME/m26}"
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

# ---------------------------------------------------------------------------------------------
# Fonctions des checks E17 à E22 (préfixe _m26c_) : « kube », prom_requete / prom_api, loki_requete
# (locataires audit et plateforme), grafana_api, mailpit_api, gitlab_api ; fichiers de ~/m26/ (E22).
# ---------------------------------------------------------------------------------------------

_M26C_NOEUDS="${WB_M26_NOEUDS:-6}"
_M26C_TRAVAIL="${WB_M26_TRAVAIL:-$HOME/m26}"
_M26C_P_K8S="plateforme/k8s"
_M26C_P_POLITIQUES="plateforme/politiques"
_M26C_P_GITOPS="plateforme/gitops"
_M26C_P_OBS="plateforme/observabilite"
_M26C_P_DOC="plateforme/medisphere"
_M26C_DOC="docs/securite/durcissement"

# _m26c_k ARGS… — kubectl en lecture par le compte des checks (sortie vide en cas d'erreur).
_m26c_k() { kube "$@" 2>/dev/null || true; }

# _m26c_json JSON [--arg NOM VALEUR]… FILTRE — 0 si le filtre jq (-e), DERNIER argument, est vrai.
_m26c_json() {
  local donnees="$1"
  shift
  local filtre="${*: -1}"
  local -a options=("${@:1:$#-1}")
  [[ -n "$donnees" ]] && jq -e "${options[@]}" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m26c_uri TEXTE — encodage pour une URL.
_m26c_uri() { jq -rn --arg v "$1" '$v | @uri'; }

# _m26c_fichier PROJET CHEMIN [BRANCHE=main] — le fichier existe sur la branche.
_m26c_fichier() {
  gitlab_api "projects/$(_m26c_uri "$1")/repository/files/$(_m26c_uri "$2")?ref=$(_m26c_uri "${3:-main}")" >/dev/null 2>&1
}

# _m26c_contenu PROJET CHEMIN [BRANCHE=main] — contenu brut (vide si absent).
_m26c_contenu() {
  gitlab_api "projects/$(_m26c_uri "$1")/repository/files/$(_m26c_uri "$2")/raw?ref=$(_m26c_uri "${3:-main}")" 2>/dev/null || true
}

# _m26c_job_reussi PROJET JOB — un job de ce nom a réussi sur main parmi les 100 derniers jobs réussis
#   du projet (un job conditionné par « changes » n'existe pas dans tous les pipelines).
_m26c_job_reussi() {
  gitlab_api "projects/$(_m26c_uri "$1")/jobs?scope%5B%5D=success&per_page=100" 2>/dev/null \
    | jq -e --arg j "$2" 'any(.[]; .name == $j and .ref == "main")' >/dev/null 2>&1
}

# _m26c_ds_pret ESPACE NOM — DaemonSet entièrement disponible, sur au moins _M26C_NOEUDS nœuds.
_m26c_ds_pret() {
  _m26c_json "$(_m26c_k get daemonset -n "$1" "$2" -o json)" --argjson n "$_M26C_NOEUDS" \
    '.status.desiredNumberScheduled >= $n and .status.numberReady == .status.desiredNumberScheduled
     and (.status.updatedNumberScheduled // 0) == .status.desiredNumberScheduled'
}

# _m26c_prom_nb 'PromQL' — nombre de séries du résultat (0 si vide ou erreur).
_m26c_prom_nb() {
  local n
  n="$(prom_requete "$1" 2>/dev/null | jq -r 'if .status == "success" then (.data.result | length) else 0 end' 2>/dev/null || true)"
  echo "${n:-0}"
}

# _m26c_prom_existe 'PromQL' — la requête renvoie au moins une série.
_m26c_prom_existe() { (( $(_m26c_prom_nb "$1") > 0 )); }

# _m26c_alertes_chargees NOM… — chaque alerte est chargée par Prometheus (API rules).
_m26c_alertes_chargees() {
  local regles a
  regles="$(prom_api 'rules?type=alert' 2>/dev/null || true)"
  [[ -n "$regles" ]] || return 1
  for a in "$@"; do
    jq -e --arg a "$a" '[.data.groups[]?.rules[]? | select(.name == $a)] | length > 0' <<<"$regles" >/dev/null 2>&1 || return 1
  done
}

# _m26c_loki_nb 'LogQL' LOCATAIRE DURÉE — nombre de lignes renvoyées (au plus 100 : limite de loki_requete).
_m26c_loki_nb() {
  local n
  n="$(loki_requete "$1" "$2" "$3" 2>/dev/null | jq -r '[.data.result[]?.values[]?] | length' 2>/dev/null || true)"
  echo "${n:-0}"
}

# _m26c_loki_present 'LogQL' LOCATAIRE DURÉE — au moins une ligne.
_m26c_loki_present() { (( $(_m26c_loki_nb "$1" "$2" "$3") > 0 )); }

# _m26c_loki_absent 'LogQL' LOCATAIRE DURÉE — la requête RÉUSSIT et ne renvoie aucune ligne
#   (une erreur de requête n'est pas une absence).
_m26c_loki_absent() {
  loki_requete "$1" "$2" "$3" 2>/dev/null | jq -e '.status == "success" and ([.data.result[]?.values[]?] | length) == 0' >/dev/null 2>&1
}

# _M26C_ECARTS_JQ — filtre jq de la norme « charge sûre » (M26-E21) : une ligne TSV par écart
#   (espace, pod, conteneur, critère) pour les pods en marche des espaces dont le nom correspond à $motif.
#   Exception inscrite au registre : C6 pour les instances CloudNativePG (cnpg.io/podRole=instance).
_M26C_ECARTS_JQ='
  def conteneurs($p): [($p.spec.initContainers // [])[], $p.spec.containers[]];
  def ecarts($p; $c):
    ($p.spec.securityContext // {}) as $ps | ($c.securityContext // {}) as $cs
    | ($p.metadata.namespace | test("-dev$")) as $dev
    | [ (if (($cs.runAsNonRoot // $ps.runAsNonRoot) == true) then empty else "C1 runAsNonRoot" end),
        (if $cs.allowPrivilegeEscalation == false then empty else "C2 allowPrivilegeEscalation" end),
        (if $cs.readOnlyRootFilesystem == true then empty else "C3 readOnlyRootFilesystem" end),
        (if (($cs.capabilities.drop // []) | index("ALL")) != null and (($cs.capabilities.add // []) | length) == 0
           then empty else "C4 capacités" end),
        (if ((($cs.seccompProfile.type // $ps.seccompProfile.type) // "") | test("^(RuntimeDefault|Localhost)$"))
           then empty else "C5 seccompProfile" end),
        (if ($dev or ($c.image | test("@sha256:[a-f0-9]{64}$"))) then empty else "C7 image sans condensé" end),
        (if ($c.resources.requests.cpu and $c.resources.requests.memory and $c.resources.limits.memory)
           then empty else "C8 ressources" end) ];
  .items[]
  | select(.metadata.namespace | test($motif))
  | select(.status.phase == "Running" or .status.phase == "Pending")
  | . as $p
  | ( (if ([($p.spec.volumes // [])[] | select(any(.projected.sources[]?; has("serviceAccountToken")))] | length) == 0
            or (($p.metadata.labels["cnpg.io/podRole"] // "") == "instance")
         then empty
         else [$p.metadata.namespace, $p.metadata.name, "-", "C6 jeton monté"] end),
      (conteneurs($p)[] as $c | ecarts($p; $c)[] | [$p.metadata.namespace, $p.metadata.name, $c.name, .]) )
  | @tsv'

# _m26c_ecarts_charges MOTIF — écarts à la norme « charge sûre » (vide si aucun, « ERREUR » si l'API
#   n'a pas répondu : une absence de réponse n'est pas une absence d'écart).
_m26c_ecarts_charges() {
  local pods
  pods="$(kube get pods -A -o json 2>/dev/null)" || { echo "ERREUR lecture des pods"; return; }
  jq -r --arg motif "$1" "$_M26C_ECARTS_JQ" <<<"$pods" 2>/dev/null || echo "ERREUR filtre"
}

# _m26c_yq_local FICHIER 'expression' — yq (mikefarah) sur un fichier de travail local ; vide si erreur.
_m26c_yq_local() { yq -r "$2" "$1" 2>/dev/null || true; }
