# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M05-E39 « Panne : la VM est créée mais injoignable »
#
# Le ticket demande une VM d'environnement de plus (VMID libre, préférence 2059) dans envs/lab-m05.
# L'apply réussit (ou attend l'agent puis expire), la VM tourne, mais adm01 ne la joint pas en SSH.
# Variantes :
#   1. gw01 : règle en tête de la chaîne input qui jette le DHCP (UDP/67) reçu sur ens19.99 : le
#      relais ne reçoit plus les demandes du VLAN 99, la VM n'a pas d'adresse IPv4 ;
#   2. gw01 : règle en tête de la chaîne forward qui jette MGMT → 10.10.99.0/24 en TCP/22 : la VM
#      a une adresse et répond au ping, SSH expire ;
#   3. dns01 : /etc/dnsmasq.d/90-sec-650.conf « dhcp-ignore=tag:!known » (durcissement demandé
#      par Sophie, appliqué trop large) : dnsmasq ignore les machines non déclarées ;
#   4. copie de travail : dans envs/lab-m05/terraform.tfvars, la liste cles_ssh_admin est remplacée
#      par la seule clé publique de Lucas (« j'ai ajouté ma clé » — en remplaçant au lieu
#      d'ajouter) : la VM démarre, a une adresse, mais refuse la clé de adm01 (publickey).
# Sauvegardes : règles repérées par commentaire (gw01), /var/lib/workbook/M05-E39.* (dns01),
# ~/.local/state/workbook/M05-E39/ (copie de travail). Annulation : seulement ce qui est encore
# dans l'état posé par la panne.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m05-commun.sh
source "$WB_ROOT/modules/05-iac/corrige/pannes/_m05-commun.sh"

_E39_COMM_DHCP="SEC-650 test filtrage DHCP sandbox (LM)"
_E39_COMM_SSH="SEC-650 test isolement sandbox (LM)"

# _e39_fichier_cles — fichier .tfvars de envs/lab-m05 qui affecte cles_ssh_admin.
_e39_fichier_cles() {
  grep -lE '^[[:space:]]*cles_ssh_admin[[:space:]]*=' "$_M05_ENVS"/*.tfvars 2>/dev/null | head -n 1
}

_m05E39_une() {
  local n="$1" rc=0 f
  case "$n" in
    1)
      m05_nft_poser E39 filter input 'iifname "ens19.99" udp dport 67 counter drop' "$_E39_COMM_DHCP" || return 1
      ;;
    2)
      m05_nft_poser E39 filter forward \
        'ip saddr 10.10.10.0/24 ip daddr 10.10.99.0/24 tcp dport 22 counter drop' "$_E39_COMM_SSH" || return 1
      ;;
    3)
      m05_wb_exec dns01 >/dev/null <<'EOF' || rc=$?
f=/etc/dnsmasq.d/90-sec-650.conf
[ -e "$f" ] && exit 10
grep -rqs '^[[:space:]]*dhcp-ignore' /etc/dnsmasq.conf /etc/dnsmasq.d/ && exit 10
sauver "$f"
cat > "$f" <<'CONF'
# SEC-650 (Sophie Laurent) : n'attribuer d'adresse qu'aux machines déclarées.
# Appliqué par Lucas le 06/10, en attente de revue.
dhcp-ignore=tag:!known
CONF
chmod 644 "$f"
noter_injecte "$f"
if ! dnsmasq --test >/dev/null 2>&1; then restaurer_fichiers; exit 1; fi
systemctl restart dnsmasq || { restaurer_fichiers; systemctl restart dnsmasq; exit 1; }
journal "$f posé (dhcp-ignore=tag:!known), dnsmasq redémarré"
EOF
      return "$rc"
      ;;
    4)
      local t cle
      f="$(_e39_fichier_cles)"
      [[ -n "$f" ]] || return 10
      t="$(mktemp -d)"
      ssh-keygen -q -t ed25519 -N '' -C 'lucas.martin@poste-lucas' -f "$t/cle" >/dev/null 2>&1 || { rm -rf -- "$t"; return 1; }
      cle="$(cat "$t/cle.pub")"
      rm -rf -- "$t"
      m05_sauver E39 "$f" || return 1
      python3 - "$f" "$cle" <<'PY2' || return 1
import re, sys
p, cle = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
m = re.search(r'(^[ \t]*cles_ssh_admin[ \t]*=[ \t]*\[)(.*?)(\])', s, re.S | re.M)
if not m:
    sys.exit(1)
neuf = '\n  # Lucas : ma clé pour les tests de charge\n  "' + cle + '",\n'
s = s[:m.start(2)] + neuf + s[m.end(2):]
open(p, "w", encoding="utf-8").write(s)
PY2
      m05_noter E39 "$f"
      m05_ecrire E39 fichier "$f"
      m05_journal E39 "$f : cles_ssh_admin remplacée par la clé de Lucas"
      ;;
  esac
}

_e39_injecter() {
  local vmid
  m05_prerequis envs || return 1
  vmid="$(m05_vmid_libre 2059)" || { wb_avert "aucun VMID libre dans 2050-2059"; return 1; }
  m05_ecrire E39 vmid "$vmid"
  m05_essayer E39 4 "$1"
}

panne_E39_v1() { _e39_injecter 1; }
panne_E39_v2() { _e39_injecter 2; }
panne_E39_v3() { _e39_injecter 3; }
panne_E39_v4() { _e39_injecter 4; }

verifier_E39() {
  local f
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  case "${WB_VAR:-}" in
    1) m05_nft_present "$_E39_COMM_DHCP" ;;
    2) m05_nft_present "$_E39_COMM_SSH" ;;
    3) remote dns01 'systemctl is-active -q dnsmasq && grep -qs "^dhcp-ignore=tag:!known" /etc/dnsmasq.d/90-sec-650.conf' ;;
    4) f="$(m05_lire E39 fichier)"; [[ -n "$f" ]] && grep -q 'lucas.martin@poste-lucas' "$f" && ! m05_fichier_modifie E39 "$f" ;;
    *) return 1 ;;
  esac
}

annuler_E39() {
  local f
  m05_nft_retirer E39 || true
  m05_wb_exec dns01 >/dev/null <<'EOF' || wb_avert "dns01 : /etc/dnsmasq.d à vérifier"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
garder_reparations
restaurer_fichiers
if dnsmasq --test >/dev/null 2>&1; then systemctl restart dnsmasq; else echo "dnsmasq --test échoue sur dns01" >&2; fi
journal "annulation : configuration dnsmasq rétablie (sauf réparation)"
EOF
  f="$(m05_lire E39 fichier)"
  if [[ -n "$f" ]]; then
    m05_restaurer E39 || true
  fi
  rm -f -- "$(m05_etat E39)/fichier" "$(m05_etat E39)/variante"
}

resume_E39() {
  echo "La VM d'environnement $(m05_lire E39 vmid) demandée par Julien est créée par OpenTofu mais injoignable en SSH depuis adm01."
}

symptome_E39() {
  local vmid
  vmid="$(m05_lire E39 vmid)"
  wb_symptome "Ticket DEV-681 — De : Julien Petit" \
    "J'ai besoin d'une VM d'environnement de plus dans envs/lab-m05 : VMID $vmid, construite comme" \
    "les autres (image dorée current, VNet vsandbox, DHCP, compte admin, ta clé)." \
    "Lucas l'a tentée hier : « l'apply passe (ou attend longtemps l'agent QEMU), la VM tourne dans" \
    "Proxmox, mais impossible de m'y connecter depuis adm01 »." \
    "Ajoute-la, et fais en sorte que je puisse m'y connecter en SSH. Je veux la cause, pas un contournement." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 05 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 05 E39 4 "$@"; }
fi
