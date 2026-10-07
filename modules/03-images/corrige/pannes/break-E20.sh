# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E20.sh — M03-E20 « Panne : les clones se marchent dessus »
#
# La panne fabrique sa propre « image de test de Lucas » : template 9095 (clone complet de
# l'image dorée Debian « current », démarré une fois puis converti, préparation incomplète),
# puis deux clones liés 2038 et 2039 démarrés sur vsandbox. Variantes :
#   1. machine-id conservé dans le template (cloud-init nettoyé, clés d'hôte supprimées) :
#      mêmes identifiants DHCP (DUID dérivé du machine-id) → même adresse IPv4 ;
#   2. clés d'hôte SSH conservées + « ssh_deletekeys: false » dans cloud.cfg.d : mêmes clés ;
#   3. « preserve_hostname: true » + nom figé dans l'image : même nom d'hôte, conflit DNS/DHCP ;
#   4. image correcte, mais 2039 créée avec l'adresse MAC de 2038 (script de Lucas) : conflit L2.
# Aucune ressource de l'apprenant n'est modifiée : l'image source n'est que clonée (clone
# complet, aucun lien vers elle). Les VMID créés sont notés dans /var/lib/workbook/M03-E20.vms
# sur pve01 ; l'annulation les détruit (ce sont des ressources de l'exercice).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m03-commun.sh
source "$WB_ROOT/modules/03-images/corrige/pannes/_m03-commun.sh"

_e20_pve() { { printf '%s\n' "$_M03_PVE_FONCTIONS"; cat; } | wb_exec "$WB_PVE_HOST" "$@"; }

# Préparation « à la Lucas » exécutée dans la VM 9095 avant conversion, selon la variante.
_e20_preparation() {
  local commun='apt-get clean; rm -f /root/.bash_history /home/*/.bash_history; '
  case "$1" in
    1) printf '%s' "${commun}rm -f /etc/ssh/ssh_host_*; cloud-init clean --logs --seed" ;;
    2) printf '%s' "${commun}printf 'ssh_deletekeys: false\n' >/etc/cloud/cloud.cfg.d/90-mediagenda.cfg; cloud-init clean --logs --seed --machine-id" ;;
    3) printf '%s' "${commun}printf 'preserve_hostname: true\n' >/etc/cloud/cloud.cfg.d/90-mediagenda.cfg; hostnamectl set-hostname mediagenda-test; rm -f /etc/ssh/ssh_host_*; cloud-init clean --logs --seed --machine-id" ;;
    *) printf '%s' "${commun}rm -f /etc/ssh/ssh_host_*; cloud-init clean --logs --seed --machine-id" ;;
  esac
}

_e20_injecter() {
  local cle
  cle="$(_m03_cle_adm01)" || return 1
  _e20_pve CLE="$cle" STO="$_M03_STOCKAGE" PREP="$(_e20_preparation "$WB_VAR")" >/dev/null <<'EOF'
SRC="$(m03_current debian13)"
[ -n "$SRC" ] && m03_est_template "$SRC" || { echo "aucune image dorée Debian étiquetée current" >&2; exit 1; }
for id in 9095 2038 2039; do
  m03_libre "$id" || { echo "VMID $id déjà utilisé : libère-le avant l'exercice" >&2; exit 1; }
done
printf '%s\n' "$CLE" >"$WB_DIR/M03-E20.cle.pub"
: >"$WB_DIR/M03-E20.vms"
# 1. VM de préparation de Lucas, démarrée une fois
qm clone "$SRC" 9095 --name mediagenda-image --full 1 --storage "$STO" --pool lab >/dev/null || exit 1
echo 9095 >>"$WB_DIR/M03-E20.vms"
qm set 9095 --net0 virtio,bridge=vsandbox --ipconfig0 ip=dhcp --ciuser admin \
  --sshkeys "$WB_DIR/M03-E20.cle.pub" --ciupgrade 0 --tags env-m03 \
  --description "Image de test MédiAgenda (Lucas) — préparée à la main" >/dev/null || exit 1
[ -n "$(m03_disque_cloudinit 9095)" ] || qm set 9095 --ide2 "$STO:cloudinit" >/dev/null || exit 1
qm start 9095 || exit 1
m03_attendre_agent 9095 300 || { echo "agent muet sur 9095" >&2; exit 1; }
m03_gexec 9095 cloud-init status --wait >/dev/null
m03_gexec 9095 bash -c "$PREP" >/dev/null || exit 1
qm shutdown 9095 --timeout 120 >/dev/null 2>&1 || qm stop 9095 >/dev/null
qm template 9095 >/dev/null || exit 1
# 2. Deux clones liés, comme le script de Lucas
for id in 2038 2039; do
  qm clone 9095 "$id" --name "mediagenda-test$((id - 2037))" --pool lab >/dev/null || exit 1
  echo "$id" >>"$WB_DIR/M03-E20.vms"
  qm set "$id" --tags env-m03 >/dev/null
done
if [ "$WB_VAR" = 4 ]; then
  mac="$(qm config 2038 | sed -nE 's/^net0: virtio=([0-9A-Fa-f:]{17}),.*/\1/p')"
  [ -n "$mac" ] || exit 1
  qm set 2039 --net0 "virtio=$mac,bridge=vsandbox" >/dev/null || exit 1
fi
qm start 2038 && qm start 2039 || exit 1
m03_attendre_agent 2038 300 && m03_attendre_agent 2039 300 || exit 1
m03_gexec 2038 cloud-init status --wait >/dev/null
m03_gexec 2039 cloud-init status --wait >/dev/null
journal "image 9095 (préparation variante $WB_VAR) et clones 2038, 2039 créés depuis $SRC"
EOF
}

panne_E20_v1() { _e20_injecter; }
panne_E20_v2() { _e20_injecter; }
panne_E20_v3() { _e20_injecter; }
panne_E20_v4() { _e20_injecter; }

verifier_E20() {
  _e20_pve >/dev/null <<'EOF'
identite() {   # identite VMID — empreinte de ce qui doit être unique selon la variante
  case "$WB_VAR" in
    1) m03_gexec "$1" cat /etc/machine-id ;;
    2) m03_gexec "$1" ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub ;;
    3) m03_gexec "$1" hostname ;;
    4) qm config "$1" | sed -nE 's/^net0: virtio=([0-9A-Fa-f:]{17}),.*/\1/p' ;;
  esac
}
a="$(identite 2038)"; b="$(identite 2039)"
[ -n "$a" ] && [ "$a" = "$b" ]
EOF
}

annuler_E20() {
  _e20_pve >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pve01 (VM 2038, 2039 ou 9095)"
if [ -f "$WB_DIR/M03-E20.vms" ]; then
  # Les clones d'abord (clones liés de 9095), le template ensuite.
  for id in $(sort -r "$WB_DIR/M03-E20.vms" | grep -v '^9095$') 9095; do
    grep -qx "$id" "$WB_DIR/M03-E20.vms" && m03_detruire "$id"
  done
  rm -f "$WB_DIR/M03-E20.vms" "$WB_DIR/M03-E20.cle.pub"
  journal "annulation : VM 2038, 2039 et image 9095 détruites"
fi
exit 0
EOF
}

resume_E20() {
  echo "les deux VMs de test MédiAgenda clonées depuis l'image de Lucas se gênent mutuellement (SSH, adresses, noms)."
}

symptome_E20() {
  wb_symptome "Ticket INC-3004 — De : Julien Petit" \
    "Lucas m'a préparé une image de test pour MédiAgenda (template 9095) et deux VMs clonées" \
    "dessus, mediagenda-test1 (2038) et mediagenda-test2 (2039), sur le VLAN bac à sable." \
    "Elles se marchent dessus : selon le moment, SSH m'envoie sur l'une ou l'autre, ou râle sur" \
    "la clé d'hôte, et les déploiements de l'une écrasent ce que je vois sur l'autre. Je ne sais" \
    "pas si c'est le réseau ou l'image. Je voudrais les deux VMs utilisables, et que la prochaine" \
    "image de Lucas n'ait pas le problème. (2038, 2039 et 9095 seront supprimés par --annuler.)" \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 03 20"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 03 E20 4 "$@"; }
fi
