# shellcheck shell=bash
# _m09-expert.sh — fonctions partagées par les vérifications du palier 4 du module 09 (check-E35 à
# check-E44). Sourcé par ces scripts, jamais lancé seul. Lecture seule : commandes d'état de Corosync,
# de pvesh (GET), de ha-manager, de Ceph et de ZFS, lancées en root sur les nœuds depuis adm01.
# Préfixe _m09x_ : évite les collisions quand check-E43 charge plusieurs checks.

_m09x_noeuds=(hv01 hv02 hv03)
# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
declare -A _m09x_ip=([hv01]=10.10.10.51 [hv02]=10.10.10.52 [hv03]=10.10.10.53)
# shellcheck disable=SC2034
declare -A _m09x_stopub=([hv01]=10.10.30.71 [hv02]=10.10.30.72 [hv03]=10.10.30.73)
# shellcheck disable=SC2034
declare -A _m09x_stoclu=([hv01]=10.10.31.71 [hv02]=10.10.31.72 [hv03]=10.10.31.73)
_m09x_table=infoger_durcissement
# shellcheck disable=SC2034
_m09x_depot="${WB_DEPOT:-$HOME/medisphere}"

# _m09x_cible NŒUD — root@IP MGMT (ne dépend pas du DNS).
_m09x_cible() { printf 'root@%s\n' "${_m09x_ip[$1]}"; }

# _m09x_hv NŒUD "commande" — exécute une commande de lecture en root sur le nœud.
_m09x_hv() {
  local n="$1"
  shift
  remote "$(_m09x_cible "$n")" "$@"
}

# _m09x_quorum NŒUD — sortie de corosync-quorumtool -s sur le nœud.
_m09x_quorum() { _m09x_hv "$1" "corosync-quorumtool -s" 2>/dev/null; }

# _m09x_un_noeud — premier nœud joignable et quorate (hv01 à défaut).
_m09x_un_noeud() {
  local n
  for n in "${_m09x_noeuds[@]}"; do
    if _m09x_quorum "$n" | grep -Eq '^Quorate:[[:space:]]+Yes'; then
      printf '%s\n' "$n"
      return 0
    fi
  done
  printf 'hv01\n'
}

# _m09x_json NŒUD "chemin" [options…] — pvesh get en JSON.
_m09x_json() {
  local n="$1" p="$2"
  shift 2
  _m09x_hv "$n" "pvesh get $p --output-format json $*" 2>/dev/null
}

# _m09x_ha_status — sortie de ha-manager status (depuis un nœud quorate).
_m09x_ha_status() { _m09x_hv "$(_m09x_un_noeud)" "ha-manager status" 2>/dev/null; }

# _m09x_aucune_panne_active EXX — la panne M09-EXX n'est plus marquée active (lab/bin/break … --annuler).
_m09x_aucune_panne_active() {
  [[ ! -f "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives/M09-$1" ]]
}

# _m09x_pas_de_table NŒUD — aucune table nftables « inet infoger_durcissement » sur le nœud.
_m09x_pas_de_table() {
  ! _m09x_hv "$1" "nft list table inet $_m09x_table" >/dev/null 2>&1
}

# _m09x_membres_ok NŒUD — le nœud voit les 3 nœuds, quorate, 3 votes attendus et présents.
_m09x_membres_ok() {
  local q
  q="$(_m09x_quorum "$1")"
  grep -Eq '^Quorate:[[:space:]]+Yes' <<<"$q" \
    && grep -Eq '^Expected votes:[[:space:]]+3$' <<<"$q" \
    && grep -Eq '^Total votes:[[:space:]]+3$' <<<"$q"
}

# _m09x_liens_ok NŒUD — Corosync : les deux liens (0 et 1) connectés vers les deux autres nœuds.
#   Format de corosync-cfgtool -s (Corosync 3) : « LINK ID n … nodeid: N: connected ».
_m09x_liens_ok() {
  local s
  s="$(_m09x_hv "$1" "corosync-cfgtool -s" 2>/dev/null)" || return 1
  awk '/^LINK ID/ { l = $3 } /nodeid/ && $NF == "connected" { c[l]++ }
       END { exit !(c[0] >= 2 && c[1] >= 2) }' <<<"$s"
}

# _m09x_pas_desarmee — la pile HA n'est pas désarmée (pas de « disarm » dans ha-manager status).
_m09x_pas_desarmee() { ! _m09x_ha_status | grep -qi 'disarm'; }

# _m09x_ecriture_pve_possible NŒUD — /etc/pve monté et quorum : pmxcfs accepte les écritures.
#   (Pas d'essai d'écriture : un check est en lecture seule.)
_m09x_ecriture_pve_possible() {
  _m09x_hv "$1" "mountpoint -q /etc/pve && systemctl is-active -q pve-cluster" >/dev/null 2>&1 \
    && _m09x_quorum "$1" | grep -Eq '^Quorate:[[:space:]]+Yes'
}

# _m09x_doc_commite CHEMIN_RELATIF — fichier présent dans le dépôt de documentation, commité, propre.
_m09x_doc_commite() {
  (cd "$_m09x_depot" && git ls-files --error-unmatch "$1" >/dev/null 2>&1 && [[ -z "$(git status --porcelain -- "$1")" ]])
}
