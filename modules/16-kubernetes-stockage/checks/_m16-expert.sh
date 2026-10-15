# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas shell)
# _m16-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du module
# 16 (check-E35 à check-E46). Sourcé par ces scripts, jamais lancé seul. LECTURE SEULE : kubectl en
# lecture avec le compte de service des checks (fonction « kube » de check-lib, pas de Secrets),
# commandes ceph de consultation sur le nœud admin de ceph-par1, lectures sur les travailleurs,
# API GitLab en GET.
# Préfixe _m16x_ : évite les collisions quand check-E43 charge plusieurs checks. Chargé une seule fois.

if [[ -z "${_M16X_CHARGE:-}" ]]; then
_M16X_CHARGE=1

_m16x_ns_t=wb-essais
_m16x_ns_db=mediagenda-recette
_m16x_cluster=mediagenda-db
_m16x_ns_csi=ceph-csi
_m16x_sc_rbd=ceph-rbd
_m16x_vsc_rbd=ceph-rbd-snap
_m16x_pool=k8s-rbd
_m16x_admin="${WB_CEPH_ADMIN:-ceph01}"
read -r -a _m16x_travailleurs <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"

# _m16x_j ARGS… — « kube get ARGS -o json » (vide si erreur).
_m16x_j() { kube get "$@" -o json 2>/dev/null || true; }

# _m16x_q JSON 'filtre' [args jq…] — 0 si le filtre est vrai.
_m16x_q() {
  local j="$1" f="$2"
  shift 2
  [[ -n "$j" ]] || return 1
  jq -e "$@" "$f" >/dev/null 2>&1 <<<"$j"
}

# _m16x_injection EXX — heure (epoch) de la dernière injection de la panne, 0 si jamais injectée.
_m16x_injection() {
  local f="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/m16-injections/$1"
  if [[ -f "$f" ]]; then cat "$f"; else echo 0; fi
}

# _m16x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M16-* si aucune) n'est marquée.
_m16x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M16-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M16-$e" ]] || return 1
  done
}

# _m16x_deploiement_pret ESPACE NOM
_m16x_deploiement_pret() {
  _m16x_q "$(_m16x_j deployment "$2" -n "$1")" \
    '(.spec.replicas // 1) >= 1 and (.status.availableReplicas // 0) >= (.spec.replicas // 1)'
}

# _m16x_ds_complet ESPACE NOM — DaemonSet entièrement prêt, au moins sur chaque travailleur.
_m16x_ds_complet() {
  _m16x_q "$(_m16x_j daemonset "$2" -n "$1")" \
    '.status.desiredNumberScheduled >= $n and .status.numberReady == .status.desiredNumberScheduled
     and (.status.numberUnavailable // 0) == 0' --argjson n "${#_m16x_travailleurs[@]}"
}

# _m16x_noeuds_prets — tous les nœuds Ready.
_m16x_noeuds_prets() {
  _m16x_q "$(_m16x_j nodes)" \
    '(.items | length) > 0 and all(.items[]; any(.status.conditions[]; .type == "Ready" and .status == "True"))'
}

# _m16x_noeuds_planifiables — aucun nœud cordonné.
_m16x_noeuds_planifiables() {
  _m16x_q "$(_m16x_j nodes)" 'all(.items[]; (.spec.unschedulable // false) == false)'
}

# _m16x_temoins_prets — témoins temoin-rbd et temoin-cephfs disponibles (créés par la 1re panne).
_m16x_temoins_prets() {
  _m16x_deploiement_pret "$_m16x_ns_t" temoin-rbd && _m16x_deploiement_pret "$_m16x_ns_t" temoin-cephfs
}

# _m16x_cnpg — Cluster mediagenda-db (JSON).
_m16x_cnpg() { _m16x_j cluster.postgresql.cnpg.io "$_m16x_cluster" -n "$_m16x_ns_db"; }

# _m16x_cree_apres JSON_LISTE EPOCH 'sélection jq' — un élément créé après EPOCH satisfait la sélection.
_m16x_cree_apres() {
  _m16x_q "$1" 'any(.items[]; ((.metadata.creationTimestamp | fromdateiso8601) >= $t) and ('"$3"'))' --argjson t "$2"
}

# _m16x_ceph ARGS… — commande ceph de consultation sur le nœud admin (CLI native ou cephadm shell).
_m16x_ceph() {
  local c
  c="$(printf '%q ' "$@")"
  remote "$_m16x_admin" "sudo -n bash -s" 2>/dev/null <<EOF
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if command -v ceph >/dev/null 2>&1 && [ -r /etc/ceph/ceph.client.admin.keyring ]; then
  timeout 60 ceph --connect-timeout 15 $c </dev/null
else
  timeout 120 cephadm shell -- ceph --connect-timeout 15 $c </dev/null 2>/dev/null
fi
EOF
}

# _m16x_caps_k8s — droits de client.k8s (JSON), jamais la clé.
_M16X_CAPS="${_M16X_CAPS:-}"
_m16x_caps_k8s() {
  if [[ -z "$_M16X_CAPS" ]]; then
    _M16X_CAPS="$(_m16x_ceph auth get client.k8s -f json | jq -c '.[0].caps // empty' 2>/dev/null)"
  fi
  printf '%s\n' "$_M16X_CAPS"
}

# _m16x_pool_sain — le pool k8s-rbd n'est ni plein ni presque plein, et son quota n'est pas saturé.
_m16x_pool_sain() {
  local h q s
  h="$(_m16x_ceph health detail -f json)"
  [[ -n "$h" ]] || return 1
  jq -e --arg p "$_m16x_pool" '[(.checks.POOL_FULL.detail // []), (.checks.POOL_NEAR_FULL.detail // [])] | flatten
        | any(.[]; .message | contains("\u0027" + $p + "\u0027")) | not' >/dev/null 2>&1 <<<"$h" || return 1
  q="$(_m16x_ceph osd pool get-quota "$_m16x_pool" -f json | jq -r '.quota_max_bytes // 0')"
  s="$(_m16x_ceph df detail -f json | jq -r --arg p "$_m16x_pool" '.pools[] | select(.name == $p) | .stats.stored')"
  [[ "$q" =~ ^[0-9]+$ && "$s" =~ ^[0-9]+$ ]] || return 1
  ((q == 0 || q * 10 >= s * 12))
}

# --- GitLab (jeton des checks, lecture) -----------------------------------------------------------

# _m16x_fichier_main PROJET CHEMIN — contenu d'un fichier de la branche main.
_m16x_fichier_main() {
  local p="${1//\//%2F}" f="${2//\//%2F}"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main"
}

# _m16x_doc_main CHEMIN MOTIF… — le fichier existe sur main de plateforme/medisphere et contient
# chaque motif (grep -E, insensible à la casse).
_m16x_doc_main() {
  local c m chemin="$1"
  shift
  c="$(_m16x_fichier_main plateforme/medisphere "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m16x_arbre PROJET DOSSIER — chemins des fichiers (récursif, main), un par ligne.
_m16x_arbre() {
  local p="${1//\//%2F}" d="${2//\//%2F}" page=1 r
  while ((page <= 5)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=main&path=$d&recursive=true&per_page=100&page=$page" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    [[ "$(jq 'length' <<<"$r" 2>/dev/null)" == 100 ]] || return 0
    page=$((page + 1))
  done
}

# _m16x_doc_prefixe DOSSIER PRÉFIXE — un fichier dont le nom commence par PRÉFIXE existe sous DOSSIER.
_m16x_doc_prefixe() {
  _m16x_arbre plateforme/medisphere "$1" | awk -F/ '{ print $NF }' | grep -q -- "^$2"
}

# _m16x_doc_prefixe_motifs DOSSIER PRÉFIXE MOTIF… — ce fichier existe et contient chaque motif.
_m16x_doc_prefixe_motifs() {
  local d="$1" pre="$2" f
  shift 2
  f="$(_m16x_arbre plateforme/medisphere "$d" | awk -F/ -v p="$pre" 'index($NF, p) == 1' | head -n1)"
  [[ -n "$f" ]] || return 1
  _m16x_doc_main "$f" "$@"
}

fi
