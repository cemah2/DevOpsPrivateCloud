#!/usr/bin/env bash
# amorcer.sh — amorce le cluster ceph-par1 sur ceph01 (M08-E03). Projet plateforme/ceph.
#
# Usage (sur ceph01, en root, depuis une copie du dépôt) :
#   [root@ceph01 ~]# bash amorcer.sh            # contrôles puis amorçage
#   [root@ceph01 ~]# bash amorcer.sh --verifier # contrôles seulement
# Il ne fait RIEN si un cluster existe déjà sur l'hôte : un second amorçage créerait un second
# cluster (nouveau fsid), pas une réparation.
set -euo pipefail

IMAGE="quay.io/ceph/ceph:v20.2.3"     # épinglée : jamais « v20 » ni « latest »
MON_IP="10.10.30.51"                  # ceph01, réseau public (VLAN 30)
RESEAU_CLUSTER="10.10.31.0/24"        # réplication, récupération, battements de cœur (VLAN 31)
UTILISATEUR_SSH="cephadm"             # compte de l'orchestrateur (rôle ceph_noeud)
DOSSIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$DOSSIER/initial-ceph.conf"

erreur() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }
ok() { printf 'OK      %s\n' "$*"; }

verifier() {
  [[ $EUID -eq 0 ]] || erreur "à lancer en root (sudo)."
  [[ "$(hostname -s)" == "ceph01" ]] || erreur "à lancer sur ceph01 (ici : $(hostname -s))."
  [[ -r "$CONFIG" ]] || erreur "configuration initiale introuvable : $CONFIG"
  command -v cephadm >/dev/null || erreur "cephadm absent : rôle ceph_noeud non appliqué ?"
  cephadm version | grep -q 'version 20\.2\.3 ' || erreur "cephadm n'est pas en 20.2.3 : $(cephadm version)"
  ok "cephadm $(cephadm version | awk '{print $3}')"
  if [[ -e /etc/ceph/ceph.conf ]] || [[ "$(cephadm ls 2>/dev/null)" != "[]" ]]; then
    erreur "un cluster existe déjà sur cet hôte (/etc/ceph/ceph.conf ou démons cephadm) : rien n'est fait."
  fi
  ok "aucun cluster existant"
  ip -4 -o addr show | grep -q " ${MON_IP}/24 " || erreur "$MON_IP n'est porté par aucune carte."
  ip -4 -o addr show | grep -q " 10\.10\.31\.51/24 " || erreur "carte du réseau cluster (10.10.31.51) absente."
  ok "adresses publique et cluster présentes"
  getent passwd "$UTILISATEUR_SSH" >/dev/null || erreur "compte $UTILISATEUR_SSH absent."
  sudo -n -l -U "$UTILISATEUR_SSH" | grep -q 'NOPASSWD: *ALL' || erreur "$UTILISATEUR_SSH n'a pas sudo sans mot de passe."
  ok "compte $UTILISATEUR_SSH prêt"
  cephadm check-host --expect-hostname ceph01 >/dev/null 2>&1 || erreur "cephadm check-host échoue : lance-le pour lire le détail."
  ok "cephadm check-host"
}

amorcer() {
  # --image AVANT la sous-commande : option globale de cephadm. Sans elle, cephadm prend son
  # image par défaut, qui est une étiquette FLOTTANTE (quay.io/ceph/ceph:v20).
  # --skip-monitoring-stack : ni Prometheus, ni Grafana, ni Alertmanager, ni node-exporter
  # (mémoire du lab ; la supervision passe par le module prometheus du mgr, M08-E24).
  # Pas de --initial-dashboard-password : un secret ne passe jamais en argument de commande.
  cephadm --image "$IMAGE" bootstrap \
    --mon-ip "$MON_IP" \
    --cluster-network "$RESEAU_CLUSTER" \
    --ssh-user "$UTILISATEUR_SSH" \
    --config "$CONFIG" \
    --skip-monitoring-stack
}

verifier
[[ "${1:-}" == "--verifier" ]] && exit 0
amorcer
echo
echo "Amorçage terminé. Suite (M08-E03) : fsid et clé publique dans l'inventaire, ceph-noeuds.yml,"
echo "puis specs/mon.yaml, specs/mgr.yaml et specs/hosts.yaml. Change le mot de passe du tableau de bord."
