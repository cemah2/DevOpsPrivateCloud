# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E21.sh — M03-E21 « Panne : cloud-init ignore la configuration »
#
# La panne crée la VM de Julien, agenda-dev01 (2037), clone complet de l'image dorée Debian
# « current », premier démarrage normal en DHCP. Puis Julien modifie la configuration
# cloud-init dans Proxmox (adresse fixe 10.10.99.37/24, sa clé SSH en plus) et redémarre :
# rien n'est appliqué. Variantes (ce qui a été fait à la VM avant le changement) :
#   1. le lecteur cloud-init a été retiré du matériel de la VM (« nettoyage » de Julien) ;
#   2. /etc/cloud/cloud.cfg.d/95-datasources.cfg : datasource_list [ ConfigDrive, OpenStack ]
#      (recopié d'une documentation OpenStack) : ds-identify ne trouve rien, cloud-init désactivé ;
#   3. /etc/cloud/cloud.cfg.d/95-cache.cfg : manual_cache_clean: true : cloud-init réutilise le
#      cache de l'instance sans comparer l'instance-id ;
#   4. /etc/cloud/cloud-init.disabled créé (« pour accélérer les redémarrages »).
# L'image source n'est que clonée. La VM 2037 est notée dans /var/lib/workbook/M03-E21.vms sur
# pve01 ; l'annulation la détruit (ressource de l'exercice).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m03-commun.sh
source "$WB_ROOT/modules/03-images/corrige/pannes/_m03-commun.sh"

_e21_pve() { { printf '%s\n' "$_M03_PVE_FONCTIONS"; cat; } | wb_exec "$WB_PVE_HOST" "$@"; }

_e21_dans_vm() {
  case "$1" in
    2) printf '%s' "printf 'datasource_list: [ ConfigDrive, OpenStack ]\n' >/etc/cloud/cloud.cfg.d/95-datasources.cfg" ;;
    3) printf '%s' "printf 'manual_cache_clean: true\n' >/etc/cloud/cloud.cfg.d/95-cache.cfg" ;;
    4) printf '%s' "touch /etc/cloud/cloud-init.disabled" ;;
    *) printf '%s' "true" ;;
  esac
}

_e21_injecter() {
  local cle
  cle="$(_m03_cle_adm01)" || return 1
  _e21_pve CLE="$cle" STO="$_M03_STOCKAGE" DANS_VM="$(_e21_dans_vm "$WB_VAR")" >/dev/null <<'EOF'
SRC="$(m03_current debian13)"
[ -n "$SRC" ] && m03_est_template "$SRC" || { echo "aucune image dorée Debian étiquetée current" >&2; exit 1; }
m03_libre 2037 || { echo "VMID 2037 déjà utilisé : libère-le avant l'exercice" >&2; exit 1; }
printf '%s\n' "$CLE" >"$WB_DIR/M03-E21.cles.pub"
# Clé de Julien : seule sa partie publique sert (repérée par son commentaire).
t="$(mktemp -d)"
ssh-keygen -q -t ed25519 -N '' -C 'julien.petit@medisphere' -f "$t/julien" || exit 1
cat "$t/julien.pub" >>"$WB_DIR/M03-E21.cles.pub"
rm -rf -- "$t"
qm clone "$SRC" 2037 --name agenda-dev01 --full 1 --storage "$STO" --pool lab >/dev/null || exit 1
echo 2037 >"$WB_DIR/M03-E21.vms"
head -n 1 "$WB_DIR/M03-E21.cles.pub" >"$WB_DIR/M03-E21.adm01.pub"
qm set 2037 --net0 virtio,bridge=vsandbox --ipconfig0 ip=dhcp --ciuser admin \
  --sshkeys "$WB_DIR/M03-E21.adm01.pub" --ciupgrade 0 --nameserver 10.10.20.10 \
  --searchdomain par1.medisphere.internal --tags env-m03 >/dev/null || exit 1
[ -n "$(m03_disque_cloudinit 2037)" ] || qm set 2037 --ide2 "$STO:cloudinit" >/dev/null || exit 1
qm start 2037 || exit 1
m03_attendre_agent 2037 300 || { echo "agent muet sur 2037" >&2; exit 1; }
# Code 2 = erreurs récupérables (avertissements) : le premier démarrage reste exploitable.
m03_gexec 2037 cloud-init status --wait >/dev/null
[ $? -le 2 ] || { echo "premier démarrage de 2037 en erreur" >&2; exit 1; }
m03_gexec 2037 bash -c "$DANS_VM" >/dev/null || exit 1
qm shutdown 2037 --timeout 120 >/dev/null 2>&1 || qm stop 2037 >/dev/null
# Le changement de Julien
qm set 2037 --ipconfig0 ip=10.10.99.37/24,gw=10.10.99.1 --sshkeys "$WB_DIR/M03-E21.cles.pub" >/dev/null || exit 1
if [ "$WB_VAR" = 1 ]; then
  d="$(m03_disque_cloudinit 2037)"
  [ -n "$d" ] && qm set 2037 --delete "$d" >/dev/null || exit 1
fi
qm start 2037 || exit 1
m03_attendre_agent 2037 300 || exit 1
sleep 20
journal "VM 2037 créée depuis $SRC ; configuration cloud-init modifiée après le premier démarrage"
EOF
}

panne_E21_v1() { _e21_injecter; }
panne_E21_v2() { _e21_injecter; }
panne_E21_v3() { _e21_injecter; }
panne_E21_v4() { _e21_injecter; }

verifier_E21() {
  _e21_pve >/dev/null <<'EOF'
m03_attendre_agent 2037 60 || exit 1
! m03_gexec 2037 ip -4 -o addr show | grep -q '10\.10\.99\.37/' \
  && ! m03_gexec 2037 cat /home/admin/.ssh/authorized_keys | grep -q 'julien\.petit@medisphere'
EOF
}

annuler_E21() {
  _e21_pve >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pve01 (VM 2037)"
if [ -f "$WB_DIR/M03-E21.vms" ]; then
  grep -qx 2037 "$WB_DIR/M03-E21.vms" && m03_detruire 2037
  rm -f "$WB_DIR/M03-E21.vms" "$WB_DIR/M03-E21.cles.pub" "$WB_DIR/M03-E21.adm01.pub"
  journal "annulation : VM 2037 détruite"
fi
exit 0
EOF
}

resume_E21() {
  echo "la VM agenda-dev01 (2037) n'applique pas la nouvelle configuration cloud-init (adresse fixe, clé de Julien)."
}

symptome_E21() {
  wb_symptome "Ticket INC-3007 — De : Julien Petit" \
    "Ma VM agenda-dev01 (2037), clonée depuis l'image dorée Debian, tournait en DHCP. Dans" \
    "l'onglet Cloud-Init de Proxmox, je lui ai donné l'adresse fixe 10.10.99.37/24 (passerelle" \
    "10.10.99.1) et j'ai ajouté ma clé SSH (julien.petit@medisphere), puis j'ai redémarré." \
    "Rien n'est pris en compte : elle a gardé une adresse DHCP et ma clé est refusée. Je l'ai" \
    "redémarrée deux fois. Sur les autres VMs, ça marche. (2037 sera supprimée par --annuler.)" \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 03 21"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 03 E21 4 "$@"; }
fi
