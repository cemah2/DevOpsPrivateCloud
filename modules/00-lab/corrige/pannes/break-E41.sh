# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M00-E41 « Panne : les petits échanges passent, les gros bloquent »
#
# Trou noir PMTU sur gw01 : une interface voit sa MTU réduite ET les messages ICMP
# « fragmentation needed » (type 3 code 4) sont filtrés (output + forward). Pas de MSS
# clamping applicable sur le sens bloqué.
#   1. ens19.20 (INFRA) en MTU 1400 → téléchargements vers dns01 et envois adm01 → dns01 ;
#   2. wg0 en MTU 1200 → flux pve01 → pbs01 (sauvegardes) ;
#   3. ens19.10 (MGMT) en MTU 1400 → téléchargements vers adm01.
# Sauvegardes : /var/lib/workbook/E41.* sur gw01.

# shellcheck source=_commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_commun.sh"

# _E41_injecter INTERFACE MTU
_E41_injecter() {
  wb_exec gw01 IFC="$1" MTU="$2" >/dev/null <<'EOF'
ip link show "$IFC" >/dev/null 2>&1 || { echo "interface $IFC absente" >&2; exit 1; }
[ -f "$WB_DIR/E41.mtu" ] || printf '%s %s\n' "$IFC" "$(cat "/sys/class/net/$IFC/mtu")" > "$WB_DIR/E41.mtu"
ip link set dev "$IFC" mtu "$MTU"
nft_inserer inet filter output 'icmp type destination-unreachable icmp code frag-needed counter drop' || exit 1
nft_inserer inet filter forward 'icmp type destination-unreachable icmp code frag-needed counter drop' || exit 1
journal "MTU de $IFC passée à $MTU ; ICMP frag-needed filtré (output + forward)"
EOF
}

panne_E41_v1() { _E41_injecter ens19.20 1400; }
panne_E41_v2() { _E41_injecter wg0 1200; }
panne_E41_v3() { _E41_injecter ens19.10 1400; }

annuler_E41() {
  wb_exec gw01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur gw01"
if [ -f "$WB_DIR/E41.mtu" ]; then
  read -r ifc mtu < "$WB_DIR/E41.mtu"
  ip link set dev "$ifc" mtu "$mtu" && rm -f "$WB_DIR/E41.mtu"
fi
nft_annuler
journal "annulation : MTU d'origine et filtrage ICMP rétablis"
EOF
}

resume_E41() {
  case "${WB_VAR:-1}" in
    2) echo "Les sauvegardes vers pbs01 restent bloquées à quelques pour cent, alors que « ssh pbs01 » fonctionne." ;;
    3) echo "Sur adm01, « apt update » se fige à 0 %, alors que les sessions SSH répondent." ;;
    *) echo "Sur dns01, « apt update » se fige, et un scp de adm01 vers dns01 stagne après quelques Ko." ;;
  esac
}

symptome_E41() {
  local details
  case "${WB_VAR:-1}" in
    2) details=("La sauvegarde de dns01 vers pbs-par2 démarre puis n'avance plus : elle reste" \
                "bloquée à quelques pour cent jusqu'à l'expiration. « ssh pbs01 » fonctionne, l'interface" \
                "web de PBS s'affiche, « ping 10.20.10.10 » répond.") ;;
    3) details=("Sur adm01, « apt update » reste figé à 0 % sur deb.debian.org, et un scp de pve01" \
                "vers adm01 démarre puis stagne. Les sessions SSH vers adm01 répondent normalement" \
                "et le ping passe.") ;;
    *) details=("Sur dns01, « apt update » reste figé à 0 %, et un « scp » d'un fichier de 5 Mo" \
                "de adm01 vers dns01 démarre puis stagne à quelques Ko. Les sessions SSH sur dns01" \
                "répondent, le ping passe, le DNS fonctionne.") ;;
  esac
  wb_symptome "Ticket INC-2611 — De : Karim Benali" \
    "Comportement bizarre depuis l'intervention réseau d'hier soir sur gw01 :" \
    "${details[@]}" \
    "Les petits échanges passent, les gros bloquent." \
    "" \
    "Temps cible : 60 min. Contrôle : lab/bin/check 00 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main E41 3 "$@"; }
fi
