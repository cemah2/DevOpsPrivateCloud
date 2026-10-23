# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# _f4-migrations.sh — fonctions partagées par les vérifications des phases 3 et 4 du final F4
# (check-S09 à check-S14). Sourcé, jamais lancé seul. Préfixe _f4g_.
#
# Lecture seule :
#   - pve01 en root (WB_PVE_HOST) : pvesh/qm/pvesm en lecture, « qm guest exec » de commandes qui ne
#     modifient rien dans les VMs migrées (dpkg-query, grep, mariadb SELECT/SHOW…) ;
#   - GitLab en GET (jeton des checks), NetBox en GET, DNS, HTTP(S) en GET depuis adm01 ;
#   - Kubernetes par « kube » (compte wb-checks : jamais les Secrets).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée.
#
# Variables de lab/lab.env (défauts ci-dessous) : WB_F4_STOCKAGE_EXPORT, WB_F4_RDV_URL,
# WB_F4_LEGACY_RECETTE_URL, WB_F4_LEGACY_PROD_URL, WB_F4_INFRA, WB_F4_DOC, WB_F4_PROJET_DOC (communes
# avec _f4-montees.sh) ; et WB_PVE_HOST, WB_GITLAB_*,
# WB_NETBOX_*, WB_K8S_KUBECONFIG, WB_TIMEOUT.

_f4g_stockage="${WB_F4_STOCKAGE_EXPORT:-hdd-bulk}"
_f4g_rdv="${WB_F4_RDV_URL:-https://rdv.par1.medisphere.internal}"
_f4g_recette="${WB_F4_LEGACY_RECETTE_URL:-https://legacy-rdv-recette.apps.par1.medisphere.internal}"
_f4g_prod="${WB_F4_LEGACY_PROD_URL:-https://legacy-rdv.apps.par1.medisphere.internal}"
_f4g_infra="${WB_F4_INFRA:-${WB_SRC:-$HOME/src}/infra}"
_f4g_doc_projet="${WB_F4_PROJET_DOC:-plateforme/medisphere}"
_f4g_doc_dir="${WB_F4_DOC:-docs/changements}"

# Plan figé (PLAN §4.14) : nom → « vmid adresse ».
declare -A _F4G_VM=(
  [legacy-rdv01]="3401 10.10.20.44"
  [ftp-part01]="3402 10.10.20.45"
  [stats01]="3403 10.10.20.46"
)
_f4g_vmid() { local v="${_F4G_VM[$1]}"; echo "${v%% *}"; }
_f4g_ip() { local v="${_F4G_VM[$1]}"; echo "${v##* }"; }

# --- GitLab (lecture) ------------------------------------------------------------------------------

_f4g_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# _f4g_fichier PROJET CHEMIN [RÉF=main] — contenu brut du fichier.
_f4g_fichier() {
  gitlab_api "projects/$(_f4g_enc "$1")/repository/files/$(_f4g_enc "$2")/raw?ref=$(_f4g_enc "${3:-main}")"
}

# _f4g_arbre PROJET [DOSSIER] — chemins des fichiers (récursif) sur main.
_f4g_arbre() {
  local p page=1 r
  p="$(_f4g_enc "$1")"
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page${2:+&path=$(_f4g_enc "$2")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _f4g_doc DOSSIER MOTIF_NOM REGEX… — un fichier de plateforme/medisphere sous DOSSIER (main) dont le
# nom correspond à MOTIF_NOM contient chaque motif (insensible à la casse). Le chemin trouvé est écrit
# dans _F4G_DOC_TROUVE.
_F4G_DOC_TROUVE=""
_f4g_doc() {
  local d="$1" motif="$2" f c m ok
  shift 2
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    c="$(_f4g_fichier "$_f4g_doc_projet" "$f" 2>/dev/null)" || continue
    ok=1
    for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || { ok=0; break; }; done
    if ((ok)); then _F4G_DOC_TROUVE="$f"; return 0; fi
  done < <(_f4g_arbre "$_f4g_doc_projet" "$d")
  return 1
}

# _f4g_doc_texte DOSSIER MOTIF_NOM — contenu du premier fichier dont le nom correspond.
_f4g_doc_texte() {
  local f
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $2 ]] || continue
    _f4g_fichier "$_f4g_doc_projet" "$f" 2>/dev/null && return 0
  done < <(_f4g_arbre "$_f4g_doc_projet" "$1")
  return 1
}

# _f4g_doc_sans DOSSIER MOTIF_NOM CHAÎNE — le document existe et ne contient PAS la chaîne (fixe).
_f4g_doc_sans() {
  local c
  c="$(_f4g_doc_texte "$1" "$2")" || return 1
  [[ -n "$c" ]] || return 1
  ! grep -Fq -- "$3" <<<"$c"
}

_f4g_etiquette() {
  gitlab_api "projects/$(_f4g_enc "$_f4g_doc_projet")/repository/tags/$(_f4g_enc "$1")" 2>/dev/null \
    | jq -e --arg t "$1" '.name == $t' >/dev/null 2>&1
}

# --- pve01 (root, lecture) -------------------------------------------------------------------------

_f4g_pve() { remote "$WB_PVE_HOST" "$@"; }

# _f4g_export_dir — dossier de l'export d'InfoGér sur pve01.
_f4g_export_dir() {
  local r
  r="$(_f4g_pve "pvesh get /storage/$_f4g_stockage --output-format json" 2>/dev/null \
    | jq -r '.path // empty' 2>/dev/null)" || return 1
  [[ -n "$r" ]] || return 1
  echo "$r/import/infoger-export"
}

# _f4g_export_conforme NOM — l'export de la VM est complet et conforme à son manifeste.
_f4g_export_conforme() {
  local d
  d="$(_f4g_export_dir)" || return 1
  _f4g_pve "cd '$d/$1' && test -f '$1.ovf' -a -f '$1-disk1.vmdk' && sed -nE 's/^SHA256\(([^)]+)\)= ([0-9a-f]{64})\$/\2  \1/p' '$1.mf' | sha256sum --quiet -c -" >/dev/null 2>&1
}

# _f4g_workbook FICHIER — fichier du dossier .workbook de l'export (témoins, etc.).
_f4g_workbook() {
  local d
  d="$(_f4g_export_dir)" || return 1
  _f4g_pve "cat '$d/.workbook/$1'" 2>/dev/null
}

_F4G_VMS_CACHE=""
_f4g_vms() {
  if [[ -z "$_F4G_VMS_CACHE" ]]; then
    _F4G_VMS_CACHE="$(_f4g_pve "pvesh get /cluster/resources --type vm --output-format json" 2>/dev/null)" || _F4G_VMS_CACHE="[]"
    jq -e 'type == "array"' >/dev/null 2>&1 <<<"$_F4G_VMS_CACHE" || _F4G_VMS_CACHE="[]"
  fi
  printf '%s\n' "$_F4G_VMS_CACHE"
}
# _f4g_vm_filtre VMID 'filtre jq' — la VM existe et satisfait le filtre (champs de /cluster/resources).
_f4g_vm_filtre() { _f4g_vms | jq -e --argjson v "$1" "any(.[]; .vmid == \$v and ($2))" >/dev/null 2>&1; }
_f4g_vm_existe() { _f4g_vm_filtre "$1" 'true'; }

_f4g_config() { _f4g_pve "qm config $1" 2>/dev/null; }
_f4g_agent() { _f4g_pve "qm guest cmd $1 ping" >/dev/null 2>&1; }

# _f4g_conforme VMID — matériel MédiSphère : VirtIO SCSI, carte virtio sur vinfra, agent activé,
# aucun disque SATA/IDE hors lecteur optique ou cloud-init, aucune carte vmxnet3/e1000, pas de virtio-blk.
_f4g_conforme() {
  local c
  c="$(_f4g_config "$1")" || return 1
  grep -Eq '^scsihw: virtio-scsi-(single|pci)$' <<<"$c" || return 1
  grep -Eq '^net0: virtio=[0-9A-Fa-f:]{17},.*bridge=vinfra(,|$)' <<<"$c" || return 1
  grep -Eq '^agent: (1|enabled=1)' <<<"$c" || return 1
  grep -Eq '^scsi0: ' <<<"$c" || return 1
  ! grep -Eq '^net[0-9]+: (vmxnet3|e1000|e1000e)=' <<<"$c" || return 1
  ! grep -Eq '^virtio[0-9]+: ' <<<"$c" || return 1
  ! grep -E '^(sata|ide)[0-9]+: ' <<<"$c" | grep -Evq 'media=cdrom|cloudinit'
}

# _f4g_ips VMID — adresses IPv4 vues par l'agent.
_f4g_ips() {
  _f4g_pve "qm guest cmd $1 network-get-interfaces" 2>/dev/null \
    | jq -r '.[]."ip-addresses"[]? | select(."ip-address-type" == "ipv4") | ."ip-address"' 2>/dev/null
}

# _f4g_invite VMID 'commande sh' — exécutée dans la VM par l'agent (commandes de LECTURE seulement) ;
# écrit la sortie standard, rend le code de sortie de la commande.
_f4g_invite() {
  local j
  j="$(_f4g_pve "qm guest exec $1 --timeout 30 -- sh -c $(printf '%q' "$2")" 2>/dev/null)" || return 1
  jq -r '."out-data" // empty' <<<"$j" 2>/dev/null
  jq -e '.exitcode == 0' >/dev/null 2>&1 <<<"$j"
}

# --- NetBox, HTTP ----------------------------------------------------------------------------------

# _f4g_netbox_ip NOM — adresse primaire IPv4 de la VM dans NetBox (sans le préfixe).
_f4g_netbox_ip() {
  netbox_api "virtualization/virtual-machines/?name=$1" 2>/dev/null \
    | jq -r '.results[0].primary_ip4.address // empty | sub("/.*$"; "")' 2>/dev/null
}
_f4g_netbox_actif() {
  netbox_api "virtualization/virtual-machines/?name=$1" 2>/dev/null | jq -e '.results[0].status.value == "active"' >/dev/null 2>&1
}

# _f4g_get URL — corps de la réponse (200 exigé).
_f4g_get() { curl -sf --max-time "$WB_TIMEOUT" "$1"; }

# _f4g_session_partagee URL — six chargements du formulaire avec le même cookie : le jeton CSRF ne
# change jamais (session retrouvée quel que soit le réplica qui répond). Lecture seule (GET).
_f4g_session_partagee() {
  local jar t premier="" i
  jar="$(mktemp)"
  for i in 1 2 3 4 5 6; do
    t="$(curl -sf --max-time "$WB_TIMEOUT" -b "$jar" -c "$jar" "$1/prendre.php" 2>/dev/null \
      | sed -nE 's/.*name="csrf" value="([0-9a-f]+)".*/\1/p' | head -n 1)"
    if [[ -z "$t" ]]; then rm -f "$jar"; return 1; fi
    [[ -z "$premier" ]] && premier="$t"
    if [[ "$t" != "$premier" ]]; then rm -f "$jar"; return 1; fi
    : "$i"
  done
  rm -f "$jar"
}

# _f4g_temoins_affiches URL — chaque témoin de l'export (patient + date/heure affichées) apparaît dans
# la liste des rendez-vous à venir de dr-temoin.
_f4g_temoins_affiches() {
  local page t id patient prat date aff piece n=0
  t="$(_f4g_workbook temoins.csv)" || return 1
  page="$(_f4g_get "$1/index.php?praticien=dr-temoin")" || return 1
  while IFS=';' read -r id patient prat date aff piece; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    grep -Fq -- "$patient" <<<"$page" || return 1
    grep -Fq -- "$aff" <<<"$page" || return 1
    n=$((n + 1))
    : "$prat$date$piece"
  done <<<"$t"
  ((n >= 3))
}

# _f4g_piece_temoin URL — la pièce jointe témoin (rendez-vous 9003) se télécharge à l'identique.
_f4g_piece_temoin() {
  local attendue obtenue
  attendue="$(_f4g_workbook temoins-pieces.sha256 | awk 'NR == 1 {print $1}')" || return 1
  [[ -n "$attendue" ]] || return 1
  obtenue="$(curl -sf --max-time "$WB_TIMEOUT" "$1/piece.php?id=9003" | sha256sum | awk '{print $1}')" || return 1
  [[ "$obtenue" == "$attendue" ]]
}

# --- Kubernetes (wb-checks) ------------------------------------------------------------------------

_f4g_api() { kube get --raw /readyz >/dev/null 2>&1; }

# _f4g_kq 'filtre jq' ARGS… — « kube get ARGS -o json » satisfait le filtre.
_f4g_kq() {
  local f="$1" j
  shift
  j="$(kube get "$@" -o json 2>/dev/null)" || return 1
  jq -e "$f" >/dev/null 2>&1 <<<"$j"
}

_f4g_app_saine() {
  _f4g_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy"' -n argocd applications.argoproj.io "$1"
}

# _f4g_pods_legacy ESPACE MIN [NŒUDS_DISTINCTS] — au moins MIN pods prêts dont l'image est celle de
# Legacy-RDV désignée par empreinte (et, si demandé, sur au moins autant de nœuds distincts).
_f4g_pods_legacy() {
  local j
  j="$(kube get pods -n "$1" -o json 2>/dev/null)" || return 1
  jq -e --argjson min "$2" --argjson noeuds "${3:-1}" '
    [.items[] | select(any(.spec.containers[]; .image | test("/medisphere/legacy-rdv(:[^@]*)?@sha256:")))
              | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))]
    | (length >= $min) and (([.[].spec.nodeName] | unique | length) >= $noeuds)' >/dev/null 2>&1 <<<"$j"
}

# _f4g_mariadb_prete ESPACE — une MariaDB de l'espace est prête, en 11.8.
_f4g_mariadb_prete() {
  _f4g_kq '[.items[] | select((.spec.image // "") | test(":11\\.8"))
            | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length >= 1' \
    -n "$1" mariadbs.k8s.mariadb.com
}
