# shellcheck shell=bash
# outils/lib.sh — fonctions communes des outils de plateforme/ceph (M08-E23). Sourcé, jamais exécuté.
#
# Accès au cluster (fonction ms_ceph), trois modes, choisis dans cet ordre :
#   1. CEPH_ADMIN=<hôte>  (adm01) : ssh <hôte> sudo ceph … (ceph-common du palier 1 sur les nœuds ;
#                         repli : sudo cephadm shell -- ceph …) ; clé client.admin du nœud _admin,
#                         jamais copiée ; l'entrée standard est transmise (ceph orch apply -i -).
#   2. commande « ceph » présente (runner01, client Debian 13) : ceph --id/--keyring/-c pris dans
#                         CEPH_ID, CEPH_KEYRING, CEPH_CONF (ex. client.ci-lecture de la dérive).
#   3. sinon (sur un nœud Ceph, en root) : cephadm shell [-k CEPH_KEYRING] -- ceph [--id CEPH_ID].
# CEPH_SSH_OPTS : options ssh supplémentaires du mode 1 (ex. « -i ~/.ssh/id_ed25519_ceph_auto »
# pour les unités systemd, qui n'ont pas d'agent SSH).

MS_RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MS_RACINE

ms_info()   { printf '%s\n' "$*" >&2; }
ms_erreur() { printf 'ERREUR : %s\n' "$*" >&2; }

# ms_cephadm — chemin du binaire cephadm (sudo n'a pas /usr/local/bin dans son PATH sous Rocky).
ms_cephadm() {
  local c
  for c in "$(command -v cephadm 2>/dev/null)" /usr/sbin/cephadm /usr/local/sbin/cephadm /usr/local/bin/cephadm; do
    [[ -n "$c" && -x "$c" ]] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# ms_outil OUTIL ARGS… — lance ceph, rbd, radosgw-admin ou crushtool selon le mode d'accès.
ms_outil() {
  local outil="$1"; shift
  if [[ -n "${CEPH_ADMIN:-}" ]]; then
    # printf %q : les arguments arrivent intacts de l'autre côté de ssh.
    # shellcheck disable=SC2029  # développement local voulu
    # shellcheck disable=SC2086  # CEPH_SSH_OPTS doit être découpé en mots
    ssh -o BatchMode=yes ${CEPH_SSH_OPTS:-} "$CEPH_ADMIN" \
      "if command -v $outil >/dev/null 2>&1; then sudo -n $outil $(printf '%q ' "$@"); else c=\$(command -v cephadm || ls /usr/sbin/cephadm /usr/local/sbin/cephadm /usr/local/bin/cephadm 2>/dev/null | head -n 1); sudo -n \"\$c\" shell -- $outil $(printf '%q ' "$@") 2>/dev/null; fi"
  elif command -v "$outil" >/dev/null 2>&1; then
    local opts=()
    [[ -n "${CEPH_ID:-}" ]] && opts+=(--id "$CEPH_ID")
    [[ -n "${CEPH_KEYRING:-}" ]] && opts+=(--keyring "$CEPH_KEYRING")
    [[ -n "${CEPH_CONF:-}" ]] && opts+=(-c "$CEPH_CONF")
    "$outil" "${opts[@]}" "$@"
  else
    local c opts=() trousseau=()
    c="$(ms_cephadm)" || { ms_erreur "ni $outil ni cephadm sur cet hôte, et CEPH_ADMIN non défini"; return 2; }
    [[ -n "${CEPH_KEYRING:-}" ]] && trousseau=(-k "$CEPH_KEYRING")
    [[ -n "${CEPH_ID:-}" ]] && opts+=(--id "$CEPH_ID")
    "$c" shell "${trousseau[@]}" -- "$outil" "${opts[@]}" "$@" 2>/dev/null
  fi
}

ms_ceph() { ms_outil ceph "$@"; }

# ms_confirmer QUESTION — « oui » tapé en toutes lettres, sinon refus (aucune valeur par défaut).
ms_confirmer() {
  local r
  [[ -t 0 ]] || { ms_erreur "confirmation impossible sans terminal (utilise --oui en connaissance de cause)"; return 1; }
  read -r -p "$1 [oui/non] " r
  [[ "$r" == "oui" ]]
}

# ms_yq — yq de mikefarah (le paquet Debian « yq » est un autre outil, PLAN §6).
ms_yq() {
  if ! yq --version 2>/dev/null | grep -q mikefarah; then
    ms_erreur "yq (mikefarah) introuvable"; return 2
  fi
  yq "$@"
}
