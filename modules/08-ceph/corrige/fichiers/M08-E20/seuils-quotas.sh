#!/usr/bin/env bash
# seuils-quotas.sh — M08-E20 (PLAT-930) : seuils de remplissage, quotas, taille cible, clé de lecture
# du rapport. Depuis adm01. Idempotent. (Le pool d'essai « essai-plein » se crée et se supprime à la
# main, voir le corrigé : une suppression de pool ne s'automatise pas dans un script d'exercice.)
# shellcheck disable=SC2029  # développement local voulu dans les commandes ssh
set -euo pipefail

ADMIN=${WB_CEPH_ADMIN:-ceph01}
c() { ssh -o BatchMode=yes "$ADMIN" "sudo ceph $(printf '%q ' "$@")" 2>/dev/null; }

c osd set-nearfull-ratio 0.75
c osd set-backfillfull-ratio 0.85
c osd dump | grep ratio

c osd pool set-quota rbd-test max_bytes 107374182400          # 100 Gio stockés (300 Gio bruts)
c osd pool set-quota rbd-ec-donnees max_bytes 64424509440     # 60 Gio stockés (90 Gio bruts)
c osd pool set rbd-test target_size_ratio 0.5
c osd pool autoscale-status

c config get mon mon_allow_pool_delete                          # doit afficher false

# Clé du rapport : lectures de cartes et de statistiques seulement. Trousseau sur ceph01 (600).
c auth get-or-create client.rapport mon 'allow r' mgr 'allow r' >/dev/null
ssh "$ADMIN" 'sudo install -m 600 -o root -g root /dev/null /etc/ceph/ceph.client.rapport.keyring'
c auth get client.rapport | ssh "$ADMIN" 'sudo tee /etc/ceph/ceph.client.rapport.keyring >/dev/null'
