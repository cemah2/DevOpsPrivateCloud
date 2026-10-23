# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants entre apostrophes
# break-S09.sh — F5-S09 « Le sinistre : perte de PAR1 » (CHRONO). Lancé depuis adm01 :
#     admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break F5 09
# Annulé (retour, F5-S12, APRÈS neutralisation de PAR1) depuis pve01, qui garde l'accès au LAN :
#     root@pve01:~/DevOpsPrivateCloud# lab/bin/break F5 09 --annuler
#
# Ce que fait l'injection (une seule « variante ») :
#   - contrôle préalable : aucune autre panne active ; PAR2 prêt (dns03, reg02, filer.sync, k8s-par2,
#     bao-par2 sans verrou, mediagenda-db-par2 réplique saine) ; temoin-rpo actif à PAR1 et suspendu à
#     PAR2 ; minuterie ms-sonde-pra active sur adm02 ; dépôt du workbook et lab/lab.env sur adm02 ;
#     wg1 (VPN de secours) présent sur hp01 ; pve01 joint gw01 ET gw02 en SSH (sinon l'annulation serait
#     impossible) et porte ce script dans /root/DevOpsPrivateCloud. Un seul KO → refus, rien n'est touché ;
#   - T0 (heure de référence du RTO et du RPO) écrit dans /var/lib/workbook/f5-t0 sur adm02 et sur gw01
#     (T0_EPOCH=…, T0_ISO=…) et ajouté à la main courante du clone de travail de adm02 s'il existe
#     (docs/pra/journal/<AAAA-MM-JJ>.md, NON commité : l'apprenant commite) ;
#   - table nftables « inet f5_sinistre » posée sur gw01 ET gw02 (fichier /etc/nftables.conf INCHANGÉ :
#     un rechargement du pare-feu, qui commence par « flush ruleset », l'effacerait) :
#       * tout ce qui entre ou sort par wg0 (liaison PAR1 ↔ PAR2) et wg1 (VPN d'administration de PAR1)
#         est jeté, ainsi que les poignées de main WireGuard (UDP 51820, 51821) : les tunnels tombent ;
#       * les connexions OUVERTES depuis le WAN vers 10.10.0.0/16 sont jetées, sauf celles de pve01
#         (accès LAN conservé pour l'annulation ; la redirection publique 443 vers lb01/lb02 est coupée) ;
#       * rien d'autre : VRRP (keepalived), conntrackd, BGP vers k8s-par1 et vers LYO1 (wg2), DHCP relayé,
#         NAT sortant du lab, NTP, tout continue. Aucune VM n'est arrêtée : PAR1 tourne, isolé.
#   - vérification sur place : table présente sur les deux passerelles ET adm02 injoignable depuis adm01 ;
#     sinon annulation et message.
#
# Annulation (idempotente) : refuse de lever l'isolement tant que PAR1 n'est pas neutralisé (Cluster
# mediagenda-db de mediagenda-prod clôturé, en réplique ou absent, lu par le compte des checks de adm01),
# sauf WB_F5_LEVER_SANS_NEUTRALISATION=1 (choix écrit dans la main courante) ; retire la table des deux
# passerelles, note LEVEE_EPOCH dans /var/lib/workbook/f5-levee sur gw01, efface le marqueur de adm01.
# Les fichiers f5-t0 restent (preuve et référence des checks de S12, S13).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=../../checks/_f5-exercice.sh
source "$WB_ROOT/finaux/F5-pra/checks/_f5-exercice.sh"

_S09_CHRONO_MIN="${WB_F5_CHRONO_S09_MIN:-240}"
_S09_DEPOT_ADM02="${WB_F5_DEPOT_PAR2_DISTANT:-}"   # vide : ~/medisphere de admin sur adm02
_S09_WB_ADM02="${WB_F5_WORKBOOK_ADM02:-DevOpsPrivateCloud}"   # relatif au $HOME de admin sur adm02
_S09_INJECTION=0
_S09_REFUS=0

_s09_pannes_actives() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives"
  [[ -d "$d" ]] || return 0
  find "$d" -maxdepth 1 -type f ! -name F5-S09 -printf '%f\n' 2>/dev/null | sort
}

# Adresse source de pve01 vers le lab (exemptée du blocage WAN).
_s09_ip_pve01() {
  remote "$WB_PVE_HOST" "ip -4 route get 10.10.10.10" 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n1
}

_s09_ko() { printf '  - %s\n' "$*" >&2; _S09_KO=1; }

_s09_prealable() {
  local a
  _S09_KO=0
  if [[ "$(hostname -s)" != adm01 ]]; then
    echo "Injection refusée : lance le sinistre depuis adm01 (l'annulation, elle, se lance depuis pve01)." >&2
    return 1
  fi
  for a in kubectl jq curl dig ssh; do
    command -v "$a" >/dev/null 2>&1 || _s09_ko "outil manquant sur adm01 : $a"
  done
  a="$(_s09_pannes_actives)"
  [[ -z "$a" ]] || _s09_ko "pannes encore actives : $(paste -sd' ' - <<<"$a") (une seule à la fois)"
  echo "Contrôle préalable : PAR2 prêt…"
  _f5e_par2_pret || _S09_KO=1
  _f5e_kq1 '(.spec.suspend // false) | not' cronjob temoin-rpo -n "$_F5E_NS_PROD" \
    || _s09_ko "CronJob temoin-rpo absent ou suspendu à PAR1 (le RPO ne pourrait pas être mesuré)"
  _f5e_kq2 '.spec.suspend == true' cronjob temoin-rpo -n "$_F5E_NS_PROD" \
    || _s09_ko "CronJob temoin-rpo absent de k8s-par2 ou non suspendu (site passif)"
  remote "$_f5e_adm02" "systemctl is-active --quiet ms-sonde-pra.timer" 2>/dev/null \
    || _s09_ko "adm02 : la minuterie ms-sonde-pra n'est pas active (pas de mesure du RTO)"
  remote "$_f5e_adm02" "test -f \"\$HOME/$_S09_WB_ADM02/lab/lab.env\" && test -x \"\$HOME/$_S09_WB_ADM02/lab/bin/check\"" 2>/dev/null \
    || _s09_ko "adm02 : dépôt du workbook ou lab/lab.env absent (~/$_S09_WB_ADM02) : les checks de S09 à S11 se lancent de là"
  remote "$_f5e_hp01" "wg show wg1 >/dev/null 2>&1" 2>/dev/null \
    || _s09_ko "hp01 : interface wg1 (VPN d'administration de secours) absente : tu n'aurais plus accès à PAR2"
  remote "$WB_PVE_HOST" "ssh -o BatchMode=yes -o ConnectTimeout=5 gw01 true && ssh -o BatchMode=yes -o ConnectTimeout=5 gw02 true" 2>/dev/null \
    || _s09_ko "pve01 ne joint pas gw01 ET gw02 en SSH (alias de /root/.ssh/config) : l'annulation serait impossible"
  remote "$WB_PVE_HOST" "test -f /root/DevOpsPrivateCloud/finaux/F5-pra/corrige/pannes/break-S09.sh" 2>/dev/null \
    || _s09_ko "pve01 : /root/DevOpsPrivateCloud n'a pas ce script (git pull sur pve01 d'abord)"
  [[ -n "$(_s09_ip_pve01)" ]] || _s09_ko "adresse de pve01 vers le lab introuvable (ip route get 10.10.10.10)"
  if ((_S09_KO)); then
    echo "Injection refusée : PAR2 ou le filet de retour ne sont pas prêts (voir ci-dessus). Rien n'a été touché." >&2
    return 1
  fi
}

panne_S09_v1() {
  local t0 iso pve gw
  _S09_INJECTION=1
  _s09_prealable || { _S09_REFUS=1; return 1; }
  pve="$(_s09_ip_pve01)"
  t0="$(date +%s)"
  iso="$(date -Is -d "@$t0")"
  # 1. T0 sur adm02 (avant la coupure : adm02 n'est plus joignable ensuite).
  wb_exec "$_f5e_adm02" T0_EPOCH="$t0" T0_ISO="$iso" <<'EOF' || return 1
printf 'T0_EPOCH=%s\nT0_ISO=%s\n' "$T0_EPOCH" "$T0_ISO" > "$WB_DIR/f5-t0"
chmod 644 "$WB_DIR/f5-t0"
journal "T0 noté ($T0_ISO)"
EOF
  # Main courante du clone de travail (compte admin, sans commit).
  {
    printf 'DEPOT=%q\nJOUR=%q\nLIGNE=%q\n' "$_S09_DEPOT_ADM02" "$(date -d "@$t0" +%F)" \
      "- $(date -d "@$t0" +%H:%M) INC-6109 [état] T0 — perte de PAR1 (sinistre simulé, heure de référence du RTO et du RPO)"
    cat <<'EOF'
d="${DEPOT:-$HOME/medisphere}"
[ -d "$d/.git" ] || exit 3
mkdir -p "$d/docs/pra/journal" && printf '%s\n' "$LIGNE" >> "$d/docs/pra/journal/$JOUR.md"
EOF
  } | remote "$_f5e_adm02" "bash -s" 2>/dev/null \
    || wb_avert "main courante de adm02 non complétée (clone ~/medisphere absent ?) : note T0 à la main"
  # 2. Isolement : gw02 puis gw01.
  for gw in gw02 gw01; do
    wb_exec "$gw" PVE="$pve" T0_EPOCH="$t0" T0_ISO="$iso" <<'EOF' || return 1
nft list table inet f5_sinistre >/dev/null 2>&1 && nft delete table inet f5_sinistre
nft -f - <<NFT || exit 1
table inet f5_sinistre {
	chain entree {
		type filter hook input priority -150; policy accept;
		iifname { "wg0", "wg1" } counter drop
		udp dport { 51820, 51821 } counter drop
	}
	chain transit {
		type filter hook forward priority -150; policy accept;
		iifname { "wg0", "wg1" } counter drop
		oifname { "wg0", "wg1" } counter drop
		iifname "ens18" ip daddr 10.10.0.0/16 ip saddr != $PVE ct direction original counter drop
	}
	chain sortie {
		type filter hook output priority -150; policy accept;
		oifname { "wg0", "wg1" } counter drop
		udp sport { 51820, 51821 } counter drop
	}
}
NFT
if [ "$(hostname -s)" = gw01 ]; then
  printf 'T0_EPOCH=%s\nT0_ISO=%s\n' "$T0_EPOCH" "$T0_ISO" > "$WB_DIR/f5-t0"
  rm -f -- "${WB_DIR:?}/f5-levee"   # nouvel exercice : l'heure de levée précédente ne vaut plus
fi
journal "table inet f5_sinistre posée (pve01 exempté : $PVE)"
EOF
  done
  sleep 5
}

verifier_S09() {
  local gw
  for gw in gw01 gw02; do
    remote "$gw" "sudo -n nft list table inet f5_sinistre" >/dev/null 2>&1 || return 1
  done
  # Isolement constaté : adm02 (PAR2) n'est plus joignable depuis adm01.
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlMaster=no -o ControlPath=none "$_f5e_adm02" true >/dev/null 2>&1; then
    return 1
  fi
}

# Neutralisation de PAR1 constatée (compte des checks de adm01) : Cluster clôturé, en réplique, ou absent.
_s09_par1_neutralise() {
  local cfg='$HOME/.config/workbook/k8s-checks.kubeconfig' j
  j="$(remote adm01 "kubectl --kubeconfig $cfg --request-timeout=10s -n $_F5E_NS_PROD get cluster $_F5E_CNPG_PAR1 -o json 2>&1 || true")" || return 2
  if grep -q 'NotFound' <<<"$j"; then return 0; fi
  jq -e . >/dev/null 2>&1 <<<"$j" || return 2
  jq -e "(($_F5E_JQ_NON_CLOTURE) | not) or (($_F5E_JQ_PRIMAIRE) | not)" >/dev/null 2>&1 <<<"$j"
}

annuler_S09() {
  local gw rc=0
  # Injection refusée par le contrôle préalable : rien n'a été touché, rien à défaire.
  if ((_S09_REFUS)); then return 0; fi
  if ((_S09_INJECTION == 0)) && [[ "${WB_F5_LEVER_SANS_NEUTRALISATION:-0}" != 1 ]]; then
    _s09_par1_neutralise || rc=$?
    if ((rc != 0)); then
      {
        if ((rc == 2)); then
          echo "Levée refusée : impossible de lire l'état de mediagenda-db à PAR1 (adm01 et son compte des checks)."
        else
          echo "Levée refusée : le Cluster mediagenda-db de PAR1 est encore un primaire non clôturé."
        fi
        echo "Neutralise PAR1 d'abord (F5-S12, RB-351 : clôture CNPG, miroirs, réplications côté PAR2)."
        echo "Pour lever quand même (abandon de l'exercice, choix écrit dans la main courante) :"
        echo "  WB_F5_LEVER_SANS_NEUTRALISATION=1 lab/bin/break F5 09 --annuler"
      } >&2
      exit 1
    fi
  fi
  for gw in gw01 gw02; do
    wb_exec "$gw" LEVEE="$(date +%s)" <<'EOF' || wb_avert "$gw : table f5_sinistre à vérifier (nft list tables)"
if nft list table inet f5_sinistre >/dev/null 2>&1; then
  nft delete table inet f5_sinistre && journal "table inet f5_sinistre retirée"
fi
if [ "$(hostname -s)" = gw01 ] && [ -f "$WB_DIR/f5-t0" ] && [ ! -f "$WB_DIR/f5-levee" ]; then
  printf 'LEVEE_EPOCH=%s\n' "$LEVEE" > "$WB_DIR/f5-levee"
  chmod 644 "$WB_DIR/f5-t0" "$WB_DIR/f5-levee"
fi
EOF
  done
  if [[ "$(hostname -s)" != adm01 ]]; then
    remote adm01 'rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives/F5-S09"' 2>/dev/null \
      || wb_avert "marqueur F5-S09 de adm01 non effacé : rm ~/.local/state/workbook/pannes-actives/F5-S09 sur adm01"
  fi
}

symptome_S09() {
  local fin
  fin="$(date -d "+$_S09_CHRONO_MIN min" +%H:%M)"
  wb_symptome "INC-6109 — $(date +%H:%M) — Appel de Nadia Roussel" \
    "« Plus rien ne répond à PAR1. Les cabinets appellent : MédiAgenda ne charge plus, les comptes" \
    "rendus de MédiDoc non plus, Legacy-RDV pareil. Le VPN ne monte plus, le tunnel vers PAR2 est" \
    "tombé. Le prestataire de la salle parle d'un départ de feu dans la baie électrique, on n'aura" \
    "pas d'information avant plusieurs heures. Claire est en ligne et attend la cellule de crise. »" \
    "" \
    "PAR1 est perdu. Tu n'y as plus accès (ni VPN de PAR1, ni pve01 : il est « dans la salle »)." \
    "Ton seul accès : le VPN de secours de hp01 (wg1, 10.255.3.0/24), puis adm02." \
    "" \
    "Chronomètre : $_S09_CHRONO_MIN min, fin à $fin. Mesures : ms-sonde-pra (adm02), témoin temoin-rpo." \
    "Contrôle (depuis adm02) : lab/bin/check F5 9"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F5 S09 1 "$@"; }
fi
