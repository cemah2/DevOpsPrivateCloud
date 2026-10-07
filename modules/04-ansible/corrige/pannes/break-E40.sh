# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M04-E40 « Panne : sshd ne redémarre plus après le playbook »
#
# Cible : runner01 (VMID 1007). La panne coupe SSH : injection ET annulation passent par l'agent
# QEMU (wb_exec_invite, depuis pve01). Chaque variante pose un défaut que les validations du rôle
# ssh_durci (validate: du fichier seul, sshd -t au moment du rechargement) ne pouvaient pas voir
# (introduit après le passage du rôle, ou non testé par sshd -t), puis redémarre ssh comme l'a
# fait la mise à jour d'openssh-server de la nuit :
#   1. /etc/ssh/sshd_config.d/20-infoger.conf (ancien fichier du prestataire) contient une faute
#      de frappe : « PermitRootLogn no » → Bad configuration option, sshd -t échoue ;
#   2. clés d'hôte déplacées hors de /etc/ssh (script de « préparation au clonage » lancé par
#      erreur sur une machine en service) → no hostkeys available ;
#   3. /etc/ssh/sshd_config.d/40-ecoute.conf : ListenAddress 10.10.20.115 (adresse qui n'existe
#      pas sur runner01) → sshd -t passe, mais le démarrage échoue (Cannot bind any address) ;
#   4. clés privées d'hôte passées en 0644 (tâche « file … recurse » d'un rôle de Lucas) →
#      sshd refuse des clés privées lisibles par tous → no hostkeys available.
# Sauvegardes : /var/lib/workbook/M04-E40.* dans runner01 (fichiers et clés, avec leurs droits).
# Annulation (agent) : seuls les fichiers encore dans l'état posé par la panne sont rétablis
# (clés régénérées, droits corrigés, fichier corrigé ou supprimé par l'apprenant : laissés), puis
# ssh redémarré.
# Le runner GitLab n'est pas touché (il ne dépend pas de sshd).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m04-commun.sh
source "$WB_ROOT/modules/04-ansible/corrige/pannes/_m04-commun.sh"

_E40_VMID=1007

_e40_port_ouvert() { timeout 5 bash -c "exec 3<>/dev/tcp/${_M04_IP[runner01]}/22" 2>/dev/null; }

_e40_precondition() {
  # En astreinte, une autre panne (M04-E35) peut déjà gêner SSH vers runner01 : seul l'agent compte.
  if [[ -z "${_M04_ASTREINTE:-}" ]] && ! m04_ssh_ok runner01; then
    wb_avert "runner01 ne répond déjà pas en SSH : lab/bin/check 04 40"
    return 1
  fi
  remote "$WB_PVE_HOST" "qm guest cmd $_E40_VMID ping" >/dev/null 2>&1 \
    || { wb_avert "agent QEMU de runner01 injoignable : la panne ne pourrait pas être annulée"; return 1; }
}

_e40_injecter() {
  _e40_precondition || return 1
  m04_wb_exec_invite "$_E40_VMID" N="$1" >/dev/null <<'EOF' || return 1
d=/etc/ssh/sshd_config.d
mkdir -p "$d"
case "$N" in
  1)
    f="$d/20-infoger.conf"; sauver "$f"
    cat >"$f" <<'CONF'
# Durcissement InfoGér (contrat 2023) — repris tel quel lors de la migration
PermitRootLogn no
X11Forwarding no
CONF
    chmod 644 "$f"; noter_injecte "$f"
    ;;
  2)
    ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 || exit 1
    for f in /etc/ssh/ssh_host_*; do sauver "$f"; done
    rm -f /etc/ssh/ssh_host_*
    # Empreinte « absent » notée pour chaque clé : une clé régénérée par l'apprenant sera gardée.
    while IFS="$(printf '\t')" read -r src _; do noter_injecte "$src"; done <"$WB_DIR/$WB_EX.manifeste"
    ;;
  3)
    f="$d/40-ecoute.conf"; sauver "$f"
    cat >"$f" <<'CONF'
# SEC-585 : sshd n'écoute que sur l'interface d'administration (Lucas)
ListenAddress 10.10.20.115
CONF
    chmod 644 "$f"; noter_injecte "$f"
    ;;
  4)
    ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 || exit 1
    for f in /etc/ssh/ssh_host_*_key; do sauver "$f"; chmod 644 "$f"; noter_injecte "$f"; done
    ;;
esac
journal "variante $N posée, redémarrage de ssh"
systemctl restart ssh >/dev/null 2>&1 || true
sleep 2
exit 0
EOF
  m04_fermer_ssh runner01
}

panne_E40_v1() { _e40_injecter 1; }
panne_E40_v2() { _e40_injecter 2; }
panne_E40_v3() { _e40_injecter 3; }
panne_E40_v4() { _e40_injecter 4; }

verifier_E40() {
  sleep 3
  ! _e40_port_ouvert && ! m04_ssh_ok runner01
}

annuler_E40() {
  m04_wb_exec_invite "$_E40_VMID" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur runner01 (agent QEMU) : voir le corrigé"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || { systemctl is-active -q ssh || systemctl restart ssh; exit 0; }
garder_reparations
restaurer_fichiers
systemctl reset-failed ssh 2>/dev/null || true
if sshd -t; then
  systemctl restart ssh && journal "annulation : ssh redémarré"
else
  journal "annulation : sshd -t échoue encore (réparation partielle ?), ssh non redémarré"
  echo "sshd -t échoue encore sur runner01" >&2
fi
exit 0
EOF
  m04_fermer_ssh runner01
}

resume_E40() {
  echo "Plus de SSH vers runner01 depuis cette nuit (rôle ssh_durci passé hier, mise à jour d'openssh-server cette nuit) : connexion refusée."
}

symptome_E40() {
  wb_symptome "Ticket INC-3146 — De : Nadia Roussel" \
    "Alerte à 6 h 12 : runner01 refuse toutes les connexions SSH (« Connection refused »). Le runner" \
    "GitLab, lui, prend encore les jobs. Hier soir, Lucas a passé le rôle ssh_durci et « fait un peu" \
    "de ménage » sur la machine ; cette nuit, la mise à jour de sécurité d'openssh-server a redémarré" \
    "le service. Lucas jure que le rôle valide la configuration complète avant de recharger sshd." \
    "Rétablis l'accès SANS réinstaller la VM, et explique pourquoi les validations n'ont rien empêché." \
    "" \
    "Accès de secours : l'agent QEMU (qm guest exec 1007 …) depuis pve01." \
    "Temps cible : 45 min. Contrôle : lab/bin/check 04 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 04 E40 4 "$@"; }
fi
