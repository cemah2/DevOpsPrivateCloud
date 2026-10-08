#!/usr/bin/env bash
# cible-iscsi.sh — M08-E17 (PLAT-927) : cible LIO sur cephcli01 exportant rbd-test/iscsi-scan
# (mappée par rbdmap) au seul initiateur m08-initiateur, avec CHAP. À lancer EN ROOT sur cephcli01.
# Le secret CHAP est lu dans /root/chap-scan-legacy (600, déposé depuis le Vault « lab », effacé
# ensuite par le script) et transmis à targetcli par son ENTRÉE STANDARD : ni ps, ni historique.
# Il reste en clair dans /etc/rtslib-fb-target/saveconfig.json (600) : limite de LIO, au registre.
set -euo pipefail
umask 077

IQN_CIBLE=iqn.2026-10.internal.medisphere.par1:cephcli01.legacy
IQN_INIT=iqn.2026-10.internal.medisphere.par1:m08-initiateur
PORTAIL=10.10.30.20
DEV=/dev/rbd/rbd-test/iscsi-scan
CHAP_ID=scan-legacy
CHAP_FICHIER=/root/chap-scan-legacy
TPG="/iscsi/$IQN_CIBLE/tpg1"

[[ $EUID -eq 0 ]] || { echo "à lancer en root" >&2; exit 1; }
[[ -b "$DEV" ]] || { echo "$DEV absent : rbdmap.service a-t-il mappé l'image ?" >&2; exit 1; }
[[ -s "$CHAP_FICHIER" ]] || { echo "secret CHAP absent : $CHAP_FICHIER" >&2; exit 1; }
secret="$(tr -d '\n' <"$CHAP_FICHIER")"
(( ${#secret} >= 16 )) || { echo "secret CHAP trop court (16 caractères au moins)" >&2; exit 1; }
[[ "$secret" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "secret CHAP : lettres, chiffres, . _ - seulement" >&2; exit 1; }

command -v targetcli >/dev/null || apt-get install -y targetcli-fb

existe() { targetcli "$1" ls >/dev/null 2>&1; }

existe /backstores/block/iscsi-scan || targetcli /backstores/block create name=iscsi-scan dev="$DEV"
existe "/iscsi/$IQN_CIBLE" || targetcli /iscsi create "$IQN_CIBLE"
existe "$TPG/luns/lun0" || targetcli "$TPG/luns" create /backstores/block/iscsi-scan
existe "$TPG/portals/0.0.0.0:3260" && targetcli "$TPG/portals" delete 0.0.0.0 3260
existe "$TPG/portals/$PORTAIL:3260" || targetcli "$TPG/portals" create "$PORTAIL" 3260
existe "$TPG/acls/$IQN_INIT" || targetcli "$TPG/acls" create "$IQN_INIT"
# CHAP : commandes lues sur l'entrée standard de targetcli (le secret n'est pas un argument).
printf 'cd %s/acls/%s\nset auth userid=%s password=%s\nexit\n' "$TPG" "$IQN_INIT" "$CHAP_ID" "$secret" | targetcli >/dev/null
unset secret
targetcli "$TPG" set attribute authentication=1 generate_node_acls=0 demo_mode_write_protect=1
targetcli saveconfig
shred -u "$CHAP_FICHIER"

# Au démarrage : mapper l'image AVANT de restaurer la configuration de LIO.
# ⚠️ À vérifier sur ton lab : nom de l'unité de restauration (systemctl list-unit-files | grep -i rtslib).
UNITE=rtslib-fb-targetctl.service
install -d /etc/systemd/system/$UNITE.d
cat > /etc/systemd/system/$UNITE.d/apres-rbdmap.conf <<'FIN'
# Géré par cible-iscsi.sh (M08-E17) : le backstore /dev/rbd/… doit exister avant la restauration.
[Unit]
Requires=rbdmap.service
After=rbdmap.service
FIN
systemctl daemon-reload
systemctl enable rbdmap.service "$UNITE"

targetcli ls "/iscsi/$IQN_CIBLE"
ss -Hltn "sport = :3260"
