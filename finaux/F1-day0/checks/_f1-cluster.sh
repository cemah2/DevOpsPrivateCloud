# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
# _f1-cluster.sh — fonctions partagées par les vérifications des phases 3 et 4 du final F1
# (check-S07 à check-S15). Sourcé, jamais lancé seul. Préfixe _f1c_ (aucune collision avec
# _f1-preparer.sh, préfixe _f1p_, ni avec les checks des modules).
#
# Lecture seule : « kube » (compte wb-checks : jamais les Secrets), GitLab en GET (jeton read_api des
# checks), OpenBao par l'AppRole wb-checks (configuration des méthodes, jamais de valeur), Harbor par
# le robot des checks, Keycloak par le client wb-checks, Prometheus en GET, DNS en lecture (dig),
# SSH + « sudo -n » de commandes de CONSULTATION sur les nœuds et les VMs, SSH root sur pve01 (qm,
# pvesh en lecture) et sur pbs01 (listage des instantanés du datastore, sans lire leur contenu).
# Les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut échouer
# hors des fonctions check_* est protégée.
#
# Variables de lab/lab.env (toutes facultatives) :
#   WB_F1_PROJET_DOC (plateforme/medisphere)  WB_F1_DOC (docs/day0)
#   WB_F1_K8S_VERSION (v1.36)          mineure attendue des nœuds reconstruits
#   WB_F1_NAISSANCE_JOURS (30)         âge maximal du cluster reconstruit
#   WB_F1_PBS_DATASTORE (ds-lab)       WB_F1_PBS_NS (par1/k8s)   (mêmes noms que check-S04)
#   WB_F1_NOEUDS_VMID (« 2141 2142 2143 2144 2145 2146 »)
#   WB_F1_PROD_URL (https://mediagenda.apps.par1.medisphere.internal)
#   WB_F1_DNS_AUTORITE (10.10.20.10)   WB_F1_DNS_PORT (5300)   WB_F1_GATEWAY_IP (10.10.41.10)

_f1c_projet_doc="${WB_F1_PROJET_DOC:-plateforme/medisphere}"
_f1c_doc="${WB_F1_DOC:-docs/day0}"
_f1c_version_k8s="${WB_F1_K8S_VERSION:-v1.36}"
_f1c_naissance_jours="${WB_F1_NAISSANCE_JOURS:-30}"
_f1c_prod_url="${WB_F1_PROD_URL:-https://mediagenda.apps.par1.medisphere.internal}"
_f1c_dns="${WB_F1_DNS_AUTORITE:-10.10.20.10}"
_f1c_dns_port="${WB_F1_DNS_PORT:-5300}"
_f1c_gw_ip="${WB_F1_GATEWAY_IP:-10.10.41.10}"
_f1c_zone_apps="apps.par1.medisphere.internal"
read -r -a _f1c_vmids <<<"${WB_F1_NOEUDS_VMID:-2141 2142 2143 2144 2145 2146}"
_f1c_noeuds=(k8s-cp01 k8s-cp02 k8s-cp03 k8s-w01 k8s-w02 k8s-w03)
_f1c_cp=(k8s-cp01 k8s-cp02 k8s-cp03)

# Racine du workbook (pour relancer d'autres checks, S14) : finaux/F1-day0/checks/ → ../../..
_f1c_racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# --- Divers --------------------------------------------------------------------------------------

_f1c_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# _f1c_epoch DATE_ISO — époque Unix (vide si la date est illisible).
_f1c_epoch() { [[ -n "${1:-}" ]] && date -d "$1" +%s 2>/dev/null || true; }

# _f1c_panne_close CLÉ — aucune panne marquée active sous cette clé (ex. F1-S12).
_f1c_panne_close() {
  [[ ! -e "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives/$1" ]]
}

# _f1c_aucune_panne_f1 — aucun marqueur de panne F1-* actif.
_f1c_aucune_panne_f1() {
  [[ -z "$(find "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" -maxdepth 1 -name 'F1-S*' 2>/dev/null)" ]]
}

# --- GitLab (lecture) ----------------------------------------------------------------------------

# _f1c_fichier PROJET CHEMIN [RÉF=main] — contenu du fichier (vide s'il est absent).
_f1c_fichier() {
  gitlab_api "projects/$(_f1c_enc "$1")/repository/files/$(_f1c_enc "$2")/raw?ref=$(_f1c_enc "${3:-main}")" 2>/dev/null || true
}

# _f1c_arbre PROJET [DOSSIER] [RÉF=main] — chemins des fichiers (récursif), un par ligne.
_f1c_arbre() {
  local p page=1 r ref
  p="$(_f1c_enc "$1")"
  ref="$(_f1c_enc "${3:-main}")"
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=$ref&recursive=true&per_page=100&page=$page${2:+&path=$(_f1c_enc "$2")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r" 2>/dev/null || return 0
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _f1c_contient TEXTE REGEX… — le texte contient chaque motif (ERE, insensible à la casse).
_f1c_contient() {
  local t="$1" m
  shift
  [[ -n "$t" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$t" || return 1; done
}

# _f1c_doc_chemin MOTIF_NOM [DOSSIER] — premier fichier de la documentation (main, récursif) dont le
# nom correspond à l'expression régulière ; vide si aucun.
_f1c_doc_chemin() {
  local motif="$1" d="${2:-$_f1c_doc}" f
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] && { printf '%s\n' "$f"; return 0; }
  done < <(_f1c_arbre "$_f1c_projet_doc" "$d")
  return 1
}

# _f1c_doc MOTIF_NOM REGEX… — un document de docs/day0 (main, récursif) dont le nom correspond
# contient chaque motif.
_f1c_doc() {
  local motif="$1" f
  shift
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    _f1c_contient "$(_f1c_fichier "$_f1c_projet_doc" "$f")" "$@" && return 0
  done < <(_f1c_arbre "$_f1c_projet_doc" "$_f1c_doc")
  return 1
}

# _f1c_doc_texte MOTIF_NOM — contenu du premier document de docs/day0 dont le nom correspond.
_f1c_doc_texte() {
  local f
  f="$(_f1c_doc_chemin "$1")" || return 0
  _f1c_fichier "$_f1c_projet_doc" "$f"
}

# _f1c_derniere_etiquette PROJET — JSON de l'étiquette vX.Y.Z la plus récente (date du commit).
_f1c_derniere_etiquette() {
  gitlab_api "projects/$(_f1c_enc "$1")/repository/tags?order_by=updated&sort=desc&per_page=20" 2>/dev/null \
    | jq -c '[.[]? | select(.name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] | .[0] // empty' 2>/dev/null || true
}

# --- Kubernetes (lecture, wb-checks) ---------------------------------------------------------------

_f1c_api_repond() { kube get --raw /livez >/dev/null 2>&1; }

# _f1c_kj ARGS… — JSON de « kube get ARGS -o json » (vide si erreur ou droit refusé).
_f1c_kj() { kube get "$@" -o json 2>/dev/null || true; }

# _f1c_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_f1c_kq() {
  local f="$1" j
  shift
  j="$(_f1c_kj "$@")"
  [[ -n "$j" ]] && jq -e "$f" >/dev/null 2>&1 <<<"$j"
}

# _f1c_peut VERBE RESSOURCE [ARGS…] — le compte des checks a ce droit (kubectl auth can-i).
_f1c_peut() { [[ "$(kube auth can-i "$@" 2>/dev/null || true)" == yes ]]; }

# _f1c_lit TYPE — le compte des checks peut lister ce type (droit accordé et CRD présente).
_f1c_lit() { kube get "$1" -A -o name >/dev/null 2>&1; }

# _f1c_naissance — date de création du cluster (époque) : celle de l'espace kube-system.
_f1c_naissance() {
  _f1c_epoch "$(kube get ns kube-system -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || true)"
}

# _f1c_naissance_iso — même date, en ISO 8601 UTC (pour comparer aux dates de GitLab et des objets).
_f1c_naissance_iso() {
  local e
  e="$(_f1c_naissance)"
  [[ -n "$e" ]] && date -u -d "@$e" +%Y-%m-%dT%H:%M:%SZ
}

# _f1c_deploiement_pret ESPACE NOM — Deployment avec toutes ses répliques disponibles (au moins une).
_f1c_deploiement_pret() {
  _f1c_kq '(.status.availableReplicas // 0) >= 1 and (.status.availableReplicas // 0) >= (.spec.replicas // 1)' \
    -n "$1" deployment "$2"
}

# _f1c_espace_pret ESPACE — au moins un Deployment/StatefulSet/DaemonSet dans l'espace, tous prêts.
_f1c_espace_pret() {
  local d s ds
  d="$(_f1c_kj -n "$1" deployments)"
  s="$(_f1c_kj -n "$1" statefulsets)"
  ds="$(_f1c_kj -n "$1" daemonsets)"
  jq -e -n --argjson d "${d:-null}" --argjson s "${s:-null}" --argjson ds "${ds:-null}" '
    ([($d.items // [])[] | (.status.availableReplicas // 0) >= (.spec.replicas // 1)]
     + [($s.items // [])[] | (.status.readyReplicas // 0) >= (.spec.replicas // 1)]
     + [($ds.items // [])[] | (.status.numberReady // 0) >= (.status.desiredNumberScheduled // 1) and (.status.desiredNumberScheduled // 0) >= 1])
    | length > 0 and all' >/dev/null 2>&1
}

# _f1c_app_saine NOM — Application Argo CD Synced et Healthy.
_f1c_app_saine() {
  _f1c_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy"' -n argocd applications.argoproj.io "$1"
}

# _f1c_apps_non_saines [EXCEPTION…] — noms des Applications non Synced/Healthy (hors exceptions).
_f1c_apps_non_saines() {
  local exc
  exc="$(printf '%s\n' "$@" | jq -R . | jq -sc '[.[] | select(length > 0)]')"
  _f1c_kj -n argocd applications.argoproj.io | jq -r --argjson e "$exc" '
    .items[]? | select((.metadata.name as $n | $e | index($n)) | not)
    | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")
    | "\(.metadata.name) (\(.status.sync.status // "?")/\(.status.health.status // "?"))"' 2>/dev/null || true
}

# _f1c_es_non_prets — ExternalSecrets dont la condition Ready n'est pas True (espace/nom).
_f1c_es_non_prets() {
  _f1c_kj externalsecrets.external-secrets.io -A | jq -r '
    .items[]? | select([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 0)
    | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || true
}

# _f1c_nb TYPE [ARGS…] — nombre d'objets (0 si illisible).
_f1c_nb() {
  local j
  j="$(_f1c_kj "$@")"
  if [[ -n "$j" ]]; then jq '.items | length' <<<"$j" 2>/dev/null || echo 0; else echo 0; fi
}

# --- Autorités de certification ----------------------------------------------------------------------

# _f1c_empreinte — empreinte SHA-256 d'un certificat PEM lu sur l'entrée standard (vide sinon).
_f1c_empreinte() {
  openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed 's/^.*=//' || true
}

# _f1c_ca_cluster — empreinte de l'autorité du cluster (ConfigMap publique kube-root-ca.crt).
_f1c_ca_cluster() {
  kube -n default get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' 2>/dev/null | _f1c_empreinte
}

# _f1c_ca_openbao — empreinte de l'autorité configurée dans auth/k8s-par1/config d'OpenBao.
_f1c_ca_openbao() {
  bao_api auth/k8s-par1/config 2>/dev/null | jq -r '.data.kubernetes_ca_cert // empty' 2>/dev/null | _f1c_empreinte
}

# _f1c_ca_coherente — OpenBao fait confiance à l'autorité du cluster actuel.
_f1c_ca_coherente() {
  local a b
  a="$(_f1c_ca_cluster)"
  b="$(_f1c_ca_openbao)"
  [[ -n "$a" && "$a" == "$b" ]]
}

# --- DNS -----------------------------------------------------------------------------------------------

# _f1c_dig NOM [TYPE=A] — réponse courte du DNS faisant autorité (sans récursion ni cache).
_f1c_dig() {
  dig +short +norec +time=3 +tries=1 -p "$_f1c_dns_port" "@$_f1c_dns" "$1" "${2:-A}" 2>/dev/null || true
}

# _f1c_noms_publies — noms *.apps des HTTPRoutes attachées à gw-par1 (sans l'étiquette dns=non).
_f1c_noms_publies() {
  _f1c_kj httproutes.gateway.networking.k8s.io -A | jq -r --arg z ".$_f1c_zone_apps" '
    .items[]? | select((.metadata.labels["medisphere.internal/dns"] // "") != "non")
    | select(any(.spec.parentRefs[]?; .name == "gw-par1"))
    | .spec.hostnames[]? | select(endswith($z)) | select(startswith("*") | not)' 2>/dev/null | sort -u || true
}

# _f1c_noms_mal_publies — noms publiés dont l'adresse faisant autorité n'est pas exactement la
# Gateway, ou dont l'enregistrement de propriété (TXT) désigne un autre propriétaire que k8s-par1.
_f1c_noms_mal_publies() {
  local n a t
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    a="$(_f1c_dig "$n" A | sort -u | paste -sd, -)"
    if [[ "$a" != "$_f1c_gw_ip" ]]; then
      printf '%s (A : %s)\n' "$n" "${a:-aucune}"
      continue
    fi
    # Propriété : nouveau format (préfixe du type) puis ancien format (même nom).
    t="$(_f1c_dig "a-$n" TXT; _f1c_dig "$n" TXT)"
    if grep -q 'heritage=external-dns' <<<"$t" && ! grep -Eq 'external-dns/owner=k8s-par1([,"]|$)' <<<"$t"; then
      printf '%s (propriétaire TXT différent de k8s-par1)\n' "$n"
    fi
  done < <(_f1c_noms_publies)
}

# --- Hôtes (lecture) -------------------------------------------------------------------------------------

# _f1c_hote HÔTE 'commande' — commande de CONSULTATION en root (sudo -n) sur une VM ; code retour.
_f1c_hote() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null >/dev/null 2>&1; }

# _f1c_hote_sortie HÔTE 'commande' — sortie de la commande de consultation (root, sudo -n).
_f1c_hote_sortie() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null 2>/dev/null || true; }

# _f1c_pve 'commande' — commande de lecture sur pve01 (root) ; sortie.
_f1c_pve() { remote "$WB_PVE_HOST" "$1" </dev/null 2>/dev/null || true; }

# _f1c_vm_ctime VMID — date de création de la VM (meta ctime de Proxmox), vide si inconnue.
_f1c_vm_ctime() {
  _f1c_pve "qm config $1" | sed -n 's/^meta: .*ctime=\([0-9][0-9]*\).*/\1/p' | head -n 1
}

# _f1c_pbs_dates VMID… — « VMID époque » pour CHAQUE instantané complet de ces VMs dans l'espace de
# noms PBS du filet (même lecture que check-S04 : arborescence du datastore, sans lire le contenu).
_f1c_pbs_dates() {
  local ds="${WB_F1_PBS_DATASTORE:-ds-lab}" ns="${WB_F1_PBS_NS:-par1/k8s}" nsdir script
  nsdir="ns/${ns//\//\/ns\/}"
  script='p="$(proxmox-backup-manager datastore show "$1" --output-format json | perl -MJSON::PP -0777 -ne '"'"'print decode_json($_)->{path}'"'"')" || exit 1
ns="$2"; shift 2
for v in "$@"; do
  for d in "$p/$ns/vm/$v"/*/; do
    [ -f "${d}index.json.blob" ] || continue
    echo "$v $(date -d "$(basename "$d")" +%s)"
  done
done'
  remote "$WB_PBS_HOST" "bash -c $(printf '%q' "$script") _ $(printf '%q ' "$ds" "$nsdir" "$@")" </dev/null 2>/dev/null || true
}

# _f1c_pbs_avant DATES VMID CTIME — un instantané de cette VM existe dans les 30 jours qui précèdent
# CTIME (la VM actuelle a été créée APRÈS une sauvegarde récente de celle qu'elle remplace).
_f1c_pbs_avant() {
  local dates="$1" v="$2" c="$3"
  [[ "$c" =~ ^[0-9]+$ ]] || return 1
  awk -v v="$v" -v c="$c" '$1 == v && $2 < c && $2 > c - 30 * 86400 { ok = 1 } END { exit !ok }' <<<"$dates"
}

# --- Prometheus --------------------------------------------------------------------------------------------

_f1c_prom_val() {
  prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true
}

# --- CloudNativePG -----------------------------------------------------------------------------------------

# _f1c_cnpg ESPACE NOM — JSON du Cluster CNPG (vide si absent ou illisible).
_f1c_cnpg() { _f1c_kj -n "$1" clusters.postgresql.cnpg.io "$2"; }

# _f1c_cnpg_server_name JSON — serverName d'archivage (plugin Barman Cloud ; défaut = nom du cluster).
_f1c_cnpg_server_name() {
  jq -r '[.spec.plugins[]? | select(.name == "barman-cloud.cloudnative-pg.io" and (.isWALArchiver // false))
          | .parameters.serverName // empty] | first // empty' <<<"$1" 2>/dev/null || true
}
