#!/usr/bin/env bash
# initiateur.sh — M08-E17 : initiateur open-iscsi sur la VM jetable m08-initiateur (2086).
# EN ROOT sur m08-initiateur. Secret CHAP dans /root/chap (600, déposé puis effacé). La commande
# « --op update … password » place le secret dans la ligne de commande d'iscsiadm le temps de
# l'appel : acceptable sur cette VM jetable sans autre utilisateur.
set -euo pipefail
IQN_CIBLE=iqn.2026-10.internal.medisphere.par1:cephcli01.legacy
IQN_INIT=iqn.2026-10.internal.medisphere.par1:m08-initiateur
PORTAIL=10.10.30.20

apt-get install -y open-iscsi xfsprogs
echo "InitiatorName=$IQN_INIT" > /etc/iscsi/initiatorname.iscsi
systemctl restart iscsid
iscsiadm -m discovery -t sendtargets -p "$PORTAIL"
noeud=(iscsiadm -m node -T "$IQN_CIBLE" -p "$PORTAIL")
"${noeud[@]}" --op update -n node.session.auth.authmethod -v CHAP
"${noeud[@]}" --op update -n node.session.auth.username -v scan-legacy
"${noeud[@]}" --op update -n node.session.auth.password -v "$(cat /root/chap)"
shred -u /root/chap
"${noeud[@]}" --login
sleep 2
lsblk -o NAME,SIZE,TRAN,VENDOR,MODEL
echo "Disque iSCSI : celui dont TRAN vaut « iscsi ». Puis : mkfs.xfs /dev/<DISQUE> && mount /dev/<DISQUE> /mnt"
