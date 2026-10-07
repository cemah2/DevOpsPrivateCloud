# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E19.sh — M03-E19 « Panne : le build attend SSH indéfiniment »
#
# Le build de l'image de base Debian (proxmox-iso, preseed) reste sur « Waiting for SSH to
# become available... ». Variantes :
#   1. gw01 : la plage de ports du serveur HTTP de Packer (8100-8199) est remplacée par
#      8000-8099 dans /etc/nftables.conf, rechargé (« nettoyage » du pare-feu) : l'installeur
#      ne récupère plus le preseed. Repli si aucune règle 8100-8199 n'existe : règle de rejet
#      insérée à chaud (vsandbox → TCP 8100-8199).
#   2. dns01 : la plage DHCP du VLAN 99 passe en mode « static » (dnsmasq ne distribue plus
#      d'adresse aux inconnus) : l'installeur n'obtient pas d'adresse.
#   3. gw01 : règle insérée à chaud qui jette le DNS du VLAN 99 vers dns01 : le preseed est
#      lu (URL par adresse IP) mais le miroir Debian ne se résout pas.
#   4. adm01 : qemu-guest-agent retiré du preseed de ~/src/images (copie de travail) :
#      l'installation se termine, mais Packer ne découvre jamais l'adresse de la VM.
# Sauvegardes : /var/lib/workbook/M03-E19.* sur l'hôte modifié (fichier d'origine et empreinte
# de l'état cassé). L'annulation ne restaure un fichier que s'il est encore dans l'état cassé
# (une réparation de l'apprenant n'est jamais écrasée) ; les règles insérées à chaud sont
# retirées par leur handle.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m03-commun.sh
source "$WB_ROOT/modules/03-images/corrige/pannes/_m03-commun.sh"

_E19_PRESEED="${WB_SRC:-$HOME/src}/images/debian13-base/http/preseed.cfg"

# Fonctions distantes communes : remplacer un fichier en mémorisant l'état cassé, et ne
# restaurer que si cet état est toujours là.
read -r -d '' _E19_FICHIER <<'FICHIER' || true
casser_fichier() {   # casser_fichier FICHIER EXPRESSION_SED
  local f="$1" expr="$2"
  sauver "$f"
  sed -i -E "$expr" "$f" || return 1
  sha256sum "$f" >"$WB_DIR/$WB_EX.casse"
}
reparer_si_casse() { # 0 si le fichier a été restauré, 1 s'il avait déjà été modifié
  [ -f "$WB_DIR/$WB_EX.manifeste" ] || return 1
  if [ -f "$WB_DIR/$WB_EX.casse" ] && sha256sum -c --status "$WB_DIR/$WB_EX.casse"; then
    restaurer_fichiers
    rm -f "$WB_DIR/$WB_EX.casse"
    return 0
  fi
  # Le fichier a changé depuis l'injection : réparation de l'apprenant, on n'y touche pas.
  journal "annulation : fichier modifié depuis l'injection, conservé tel quel"
  awk -F '\t' '$2 != "ABSENT" {print $2}' "$WB_DIR/$WB_EX.manifeste" | xargs -r rm -f
  rm -f "$WB_DIR/$WB_EX.manifeste" "$WB_DIR/$WB_EX.casse"
  return 1
}
FICHIER

_e19_gw01() { { printf '%s\n' "$_E19_FICHIER"; cat; } | wb_exec gw01 "$@"; }
_e19_dns01() { { printf '%s\n' "$_E19_FICHIER"; cat; } | wb_exec dns01 "$@"; }
_e19_local() { { printf '%s\n' "$_E19_FICHIER"; cat; } | wb_exec localhost "$@"; }

panne_E19_v1() {
  _e19_gw01 >/dev/null <<'EOF'
nft -c -f /etc/nftables.conf || { echo "nftables.conf invalide avant la panne" >&2; exit 1; }
if grep -q '8100-8199' /etc/nftables.conf; then
  casser_fichier /etc/nftables.conf 's/8100-8199/8000-8099/g' || exit 1
  if ! nft -c -f /etc/nftables.conf; then restaurer_fichiers; exit 1; fi
  systemctl reload nftables || nft -f /etc/nftables.conf || exit 1
  journal "nftables.conf : 8100-8199 remplacé par 8000-8099, rechargé"
else
  nft_inserer inet filter forward 'ip saddr 10.10.99.0/24 tcp dport 8100-8199 drop' || exit 1
  journal "règle à chaud : rejet vsandbox → TCP 8100-8199"
fi
EOF
}

panne_E19_v2() {
  _e19_dns01 >/dev/null <<'EOF'
f="$(grep -lE '^[[:space:]]*dhcp-range=.*10\.10\.99\.100' /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf 2>/dev/null | head -n 1)"
[ -n "$f" ] || { echo "plage DHCP 10.10.99.100 introuvable (dnsmasq)" >&2; exit 1; }
casser_fichier "$f" '/^[[:space:]]*dhcp-range=.*10\.10\.99\.100/ s/10\.10\.99\.100,10\.10\.99\.[0-9]+/10.10.99.0,static/' || exit 1
if ! dnsmasq --test >/dev/null 2>&1; then restaurer_fichiers; exit 1; fi
systemctl restart dnsmasq || exit 1
journal "$f : plage DHCP du VLAN 99 en mode static"
EOF
}

panne_E19_v3() {
  _e19_gw01 >/dev/null <<'EOF'
nft_inserer inet filter forward 'ip saddr 10.10.99.0/24 ip daddr 10.10.20.10 meta l4proto { tcp, udp } th dport 53 drop' || exit 1
journal "règle à chaud : rejet DNS vsandbox → dns01"
EOF
}

panne_E19_v4() {
  if [[ ! -f "$_E19_PRESEED" ]] || ! grep -q 'qemu-guest-agent' "$_E19_PRESEED"; then
    wb_avert "$_E19_PRESEED absent ou sans qemu-guest-agent : variante 1 à la place"
    WB_VAR=1
    panne_E19_v1
    return
  fi
  _e19_local F="$_E19_PRESEED" >/dev/null <<'EOF'
casser_fichier "$F" 's/[[:space:]]*qemu-guest-agent//g' || exit 1
journal "$F : qemu-guest-agent retiré"
EOF
}

verifier_E19() {
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main avant l'appel
  case "${WB_VAR:-}" in
    1) remote gw01 "sudo -n nft list chain inet filter forward" 2>/dev/null \
         | grep -Eq '8000-8099|ip saddr 10\.10\.99\.0/24 tcp dport 8100-8199 drop' ;;
    2) remote dns01 "grep -hE '^[[:space:]]*dhcp-range=.*10\.10\.99\.0,static' /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf && systemctl is-active -q dnsmasq" >/dev/null 2>&1 ;;
    3) remote gw01 "sudo -n nft list chain inet filter forward" 2>/dev/null \
         | grep -Eq 'ip saddr 10\.10\.99\.0/24 ip daddr 10\.10\.20\.10 .*dport 53 drop' ;;
    4) [[ -f "$_E19_PRESEED" ]] && ! grep -q 'qemu-guest-agent' "$_E19_PRESEED" ;;
    *) return 1 ;;
  esac
}

annuler_E19() {
  _e19_gw01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur gw01"
nft_annuler
if reparer_si_casse; then
  nft -c -f /etc/nftables.conf && { systemctl reload nftables || nft -f /etc/nftables.conf; }
  journal "annulation : nftables.conf restauré et rechargé"
fi
exit 0
EOF
  _e19_dns01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur dns01"
if reparer_si_casse; then
  systemctl restart dnsmasq
  journal "annulation : configuration DHCP restaurée"
fi
exit 0
EOF
  _e19_local >/dev/null <<'EOF' || wb_avert "annulation incomplète sur adm01"
reparer_si_casse && journal "annulation : preseed restauré"
exit 0
EOF
}

resume_E19() {
  echo "le build de l'image de base Debian reste bloqué sur « Waiting for SSH » jusqu'au délai maximal."
}

symptome_E19() {
  wb_symptome "Ticket INC-3001 — De : Karim Benali" \
    "Debian a publié une version intermédiaire : j'ai relancé ce matin le build de l'image de base" \
    "(debian13-base) pour la mettre à jour. La VM démarre sur l'ISO, puis Packer affiche" \
    "« Waiting for SSH to become available... » et n'en sort plus jusqu'au délai maximal. Rien n'a" \
    "changé dans le dépôt depuis le dernier build réussi, à ma connaissance. Lucas a fait des essais" \
    "sur le lab hier soir. Reproduis-le en zone d'essai (VMID 9090, jamais sur 9001) et répare." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 03 19"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 03 E19 4 "$@"; }
fi
