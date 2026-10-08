# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M09-E42 « Panne : impossible de modifier une VM »
#
# Cible : variantes 2 et 3, le nœud qui porte la VIP de l'API (10.10.10.200, hv.par1.medisphere.internal,
# M09-E18), par lequel passent Julien et OpenTofu (hv03 s'il n'y a pas de VIP) : le script de santé
# de keepalived (quorum + réponse de l'API) ne voit pas ces pannes, la VIP reste sur un nœud où l'on
# ne peut plus écrire. Variante 1 : un nœud qui NE porte PAS la VIP (hv03, ou hv02 si la VIP est sur
# hv03), utilisé en direct par Julien — sur le nœud de la VIP, le script de santé déplacerait la VIP.
# La HA est désarmée (freeze) avant chaque variante : sans quorum (1), sans base pmxcfs inscriptible
# (2 : le LRM et le CRM ne renouvellent plus leurs verrous) ou sans pmxcfs (3), le nœud se clôturerait.
# Variantes :
#   1. perte de quorum d'un nœud : table nftables « inet infoger_durcissement » sur la cible, qui jette
#      l'UDP 5404-5412 (Corosync) → la cible est seule et sans quorum, /etc/pve y est en lecture
#      seule, mais son interface affiche encore tout (lecture) ;
#   2. disque système plein sur la cible (/var/tmp/export-infoger.tar) → pmxcfs ne peut plus écrire
#      sa base (/var/lib/pve-cluster/config.db) : les écritures dans /etc/pve échouent ;
#   3. pve-cluster arrêté sur la cible, et un fichier parasite écrit DANS le dossier /etc/pve démonté
#      (« copie de secours » d'un 100.conf) → /etc/pve vide ; au redémarrage, pmxcfs peut refuser un
#      point de montage non vide (selon la version de FUSE).
# Sauvegardes : /var/lib/workbook/M09-E42.* sur la cible ; état local ~/.local/state/workbook/M09-E42/.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m09-commun.sh
source "$WB_ROOT/modules/09-cluster-proxmox/corrige/pannes/_m09-commun.sh"

_E42_PARASITE=/etc/pve/100.conf.sauvegarde
_E42_GROS=/var/tmp/export-infoger.tar

_e42_cible() {
  local c
  c="$(m09_lire E42 cible)"
  printf '%s\n' "${c:-hv03}"
}

# _e42_ecriture_ko — une écriture d'essai dans /etc/pve échoue sur la cible (fichier aussitôt retiré).
_e42_ecriture_ko() {
  ! m09_ssh "$(_e42_cible)" "mountpoint -q /etc/pve && echo essai >/etc/pve/.wb-essai-ecriture && rm -f /etc/pve/.wb-essai-ecriture" >/dev/null 2>&1
}

_e42_effet() {
  case "$1" in
    1) m09_pas_quorate "$(_e42_cible)" && _e42_ecriture_ko ;;
    2) _e42_ecriture_ko ;;
    3) ! m09_ssh "$(_e42_cible)" "mountpoint -q /etc/pve" >/dev/null 2>&1 ;;
  esac
}

_e42_precondition() {
  m09_cluster_sain || return 1
  local n
  m09_ecrire E42 vip "$(m09_noeud_vip)"
  for n in "${_M09_NOEUDS[@]}"; do
    if m09_ssh "$n" "nft list table inet $_M09_TABLE" >/dev/null 2>&1; then
      wb_avert "$n : une table nftables inet $_M09_TABLE existe déjà (panne précédente non close ?)"
      return 1
    fi
    m09_ecrire E42 cible "$n"
    if _e42_ecriture_ko; then
      wb_avert "$n : /etc/pve n'est déjà pas inscriptible avant la panne : lab/bin/check 09 42"
      return 1
    fi
  done
}

# _e42_choisir N — fixe la cible de la variante N (voir l'en-tête).
_e42_choisir() {
  local vip c
  vip="$(m09_lire E42 vip)"
  if [[ "$1" == 1 ]]; then
    c=hv03
    [[ "$vip" != hv03 ]] || c=hv02
  else
    c="${vip:-hv03}"
  fi
  m09_ecrire E42 cible "$c"
}

_mE42_une() {
  local n="$1" rc=0 c
  _e42_choisir "$n"
  c="$(_e42_cible)"
  case "$n" in
    1)
      m09_ha_geler E42 || return 1
      m09_exec "$c" >/dev/null <<'EOF' || rc=$?
table_poser <<'NFT'
  chain entree {
    type filter hook input priority -5; policy accept;
    udp dport 5404-5412 counter drop comment "InfoGer : ports non documentes"
  }
NFT
EOF
      ;;
    2)
      m09_ha_geler E42 || return 1
      m09_exec "$c" F="$_E42_GROS" >/dev/null <<'EOF' || rc=$?
[ -e "$F" ] && exit 10
: >"$WB_DIR/$WB_EX.gros"
# Journal AVANT de remplir le disque (après, plus rien ne s'écrit).
journal "$F créé : système de fichiers racine rempli"
libre=$(( $(stat -f -c '%f' /) * $(stat -f -c '%S' /) ))
fallocate -l "$libre" "$F" 2>/dev/null || fallocate -l $((libre - 1048576)) "$F" || exit 1
# Le reste, bloc par bloc, jusqu'au refus (blocs réservés à root compris).
dd if=/dev/zero of="$F" bs=64K oflag=append conv=notrunc status=none 2>/dev/null || true
exit 0
EOF
      ;;
    3)
      m09_ha_geler E42 || return 1
      m09_exec "$c" P="$_E42_PARASITE" >/dev/null <<'EOF' || rc=$?
systemctl stop pve-cluster || exit 1
sleep 2
mountpoint -q /etc/pve && exit 1
: >"$WB_DIR/$WB_EX.arret"
printf 'name: copie-de-secours\nmemory: 2048\n' >"$P"
journal "pve-cluster arrêté, $P écrit dans le dossier /etc/pve démonté"
# Essai de redémarrage, comme un administrateur pressé : s'il réussit, on le ré-arrête (la panne
# minimale reste « pve-cluster arrêté »).
if systemctl start pve-cluster 2>/dev/null; then
  sleep 3
  systemctl stop pve-cluster
  journal "pve-cluster a accepté le point de montage non vide : ré-arrêté"
fi
EOF
      ;;
  esac
  ((rc == 0)) || { _e42_defaire "$n"; return "$rc"; }
  if ! m09_attendre 60 _e42_effet "$n"; then
    _e42_defaire "$n"
    return 10
  fi
}

_e42_defaire() {
  local c
  c="$(_e42_cible)"
  case "$1" in
    1)
      m09_exec "$c" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $c (table nftables)"
table_retirer
EOF
      if [[ -n "$(m09_lire E42 ha-desarmee)" ]]; then m09_attendre 60 m09_quorate "$c" || true; fi
      m09_ha_rearmer E42
      ;;
    2)
      m09_exec "$c" F="$_E42_GROS" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $c (fichier volumineux)"
[ -f "$WB_DIR/$WB_EX.gros" ] || exit 0
if [ -e "$F" ]; then rm -f "$F" && journal "annulation : $F supprimé"
else journal "annulation : $F déjà supprimé (réparation)"
fi
rm -f "$WB_DIR/$WB_EX.gros"
# pmxcfs peut garder une erreur d'écriture : on ne le redémarre que si /etc/pve reste inscriptible-KO.
if ! { echo essai >/etc/pve/.wb-essai-ecriture && rm -f /etc/pve/.wb-essai-ecriture; } 2>/dev/null; then
  systemctl restart pve-cluster || true
fi
# Le moniteur Ceph du nœud s'arrête quand son disque est presque plein (mon_data_avail_crit).
u="ceph-mon@$(hostname -s)"
if systemctl cat "$u" >/dev/null 2>&1 && ! systemctl is-active -q "$u"; then
  systemctl reset-failed "$u" 2>/dev/null || true
  systemctl start "$u" && journal "annulation : $u relancé"
fi
EOF
      m09_ha_rearmer E42
      ;;
    3)
      m09_exec "$c" P="$_E42_PARASITE" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $c (pve-cluster) : systemctl start pve-cluster"
[ -f "$WB_DIR/$WB_EX.arret" ] || exit 0
# Le parasite est dans le dossier sous le point de montage : on le voit par un montage lié de /.
m="$(mktemp -d)"
if mount --bind / "$m"; then
  if [ -f "$m$P" ]; then rm -f "$m$P" && journal "annulation : fichier parasite retiré du dossier /etc/pve"; fi
  umount "$m"
fi
rmdir "$m" 2>/dev/null || true
if mountpoint -q /etc/pve; then
  journal "annulation : pve-cluster déjà relancé (réparation)"
else
  systemctl start pve-cluster && journal "annulation : pve-cluster démarré"
fi
rm -f "$WB_DIR/$WB_EX.arret"
EOF
      m09_ha_rearmer E42
      ;;
  esac
}

_e42_injecter() {
  _e42_precondition || return 1
  m09_essayer E42 3 "$1"
}

panne_E42_v1() { _e42_injecter 1; }
panne_E42_v2() { _e42_injecter 2; }
panne_E42_v3() { _e42_injecter 3; }

verifier_E42() {
  _e42_effet "${WB_VAR:-1}"
}

annuler_E42() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e42_defaire "$WB_VAR" ;;
    *) _e42_defaire 3; _e42_defaire 2; _e42_defaire 1 ;;
  esac
  m09_effacer E42 cible
  m09_effacer E42 vip
}

# _e42_par_vip — la cible est le nœud de la VIP (Julien passe par hv.par1.medisphere.internal).
_e42_par_vip() {
  [[ -n "$(m09_lire E42 vip)" && "$(m09_lire E42 vip)" == "$(_e42_cible)" ]]
}

# _e42_autre — un nœud sain, différent de la cible (celui de Karim).
_e42_autre() {
  if [[ "$(_e42_cible)" == hv01 ]]; then echo hv02; else echo hv01; fi
}

resume_E42() {
  if _e42_par_vip; then
    echo "Par hv.par1.medisphere.internal, toute modification de VM échoue ; directement sur $(_e42_autre), ça passe."
  else
    echo "Sur $(_e42_cible), toute modification de VM échoue ; directement sur $(_e42_autre), ça passe."
  fi
}

symptome_E42() {
  local acces="https://hv.par1.medisphere.internal:8006 (l'adresse officielle)"
  _e42_par_vip || acces="https://$(_e42_cible).par1.medisphere.internal:8006 (en direct)"
  local note="Temps cible : 45 min. Contrôle : lab/bin/check 09 42"
  if [[ -n "$(m09_lire E42 ha-desarmee)" ]]; then
    note="Note : l'injection a désarmé la pile HA (mode freeze) ; ce n'est pas la cause. $note"
  fi
  wb_symptome "Ticket INC-3648 — De : Julien Petit" \
    "Impossible de modifier une VM depuis $acces :" \
    "ajouter un disque, changer la mémoire ou même une description échoue, avec une erreur qui" \
    "change selon l'écran. Le « tofu apply » de la recette échoue aussi. Karim, connecté" \
    "directement à $(_e42_autre), modifie ses VMs sans problème. Le tableau de bord n'affiche rien" \
    "d'alarmant au premier coup d'œil." \
    "" \
    "$note"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 09 E42 3 "$@"; }
fi
