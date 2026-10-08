# shellcheck shell=bash
# _m07-commun.sh — fonctions partagées par les scripts de panne du module 07 (M07-E35 à M07-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, _wb_entete, _WB_PRELUDE, wb_avert…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Accès aux hôtes :
#   - VMs de la maquette (2070-2079, pool lab, étiquette env-m07) : TOUJOURS par l'agent QEMU, depuis
#     pve01 (qm guest exec --pass-stdin). Une panne réseau ne coupe donc jamais l'injection ni
#     l'annulation, et l'on ne dépend ni des alias SSH ni des adresses DHCP de la maquette. Avant
#     chaque premier accès, le nom et l'étiquette de la VM sont contrôlés (jamais d'action sur une
#     VM qui ne serait pas celle de la maquette).
#   - Hôtes du socle (gw01, gw02, lb01, lb02) : SSH (alias de ~/.ssh/config), admin + sudo -n.
#   Aucune action sur pve01 lui-même (seulement « qm config » et « qm guest exec » en lecture/agent),
#   ni sur pbs01, ni sur le réseau de pve01.
#
# Mécanismes d'injection réversibles (exécutés sur l'hôte, voir _M07_AIDE_DISTANTE) :
#   subst / defaire_subst       modification chirurgicale d'un fichier ; l'annulation ne remet le
#                               texte d'origine que là où le texte posé est ENCORE présent (une
#                               réparation de l'apprenant n'est jamais écrasée) ;
#   sauver + noter_injecte      fichier entier ajouté ou remplacé (restauré seulement s'il n'a pas
#                               changé depuis l'injection) ;
#   sysctl_poser / _restaurer   valeur d'origine mémorisée, rétablie si la valeur posée est encore là ;
#   mtu_poser / mtu_restaurer   idem pour le MTU d'une interface ;
#   nft_table_poser             table nftables dédiée, posée à chaud, supprimée à l'annulation ;
#   defaire_noter TEST ANNUL    action à chaud quelconque (route, règle, lien, port OVS, service) :
#                               ANNUL n'est exécuté que si TEST constate encore l'état cassé.

_M07_DEPOT="${WB_DEPOT:-$HOME/medisphere}"

# VMID de la maquette (PLAN.md §4.9) et adresses de boucle de la fabric (brief du module)
# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
declare -A _M07_VMID=([net01]=2070 [spine01]=2071 [spine02]=2072 [leaf01]=2073 [leaf02]=2074
  [srv01]=2075 [srv02]=2076 [lyo-gw01]=2077 [lyo-pc01]=2078 [hap01]=2079)
# shellcheck disable=SC2034
declare -A _M07_BOUCLE=([spine01]=10.10.255.1 [spine02]=10.10.255.2 [leaf01]=10.10.255.11
  [leaf02]=10.10.255.12 [srv01]=10.10.255.21 [srv02]=10.10.255.22)
# Cache des VMs déjà contrôlées (nom + étiquette env-m07)
declare -A _M07_VM_OK=()

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

# m07_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m07_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M07-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

# m07_journal EXX "message" — journal local de la panne.
m07_journal() {
  local ex="$1" d
  shift
  d="$(m07_etat "$ex")"
  printf '%s %s [M07-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}

# m07_lire EXX CLÉ / m07_ecrire EXX CLÉ VALEUR — petites valeurs d'état (hôte ciblé, fichier…).
m07_lire() {
  local f
  f="$(m07_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m07_ecrire() {
  local d
  d="$(m07_etat "$1")"
  printf '%s\n' "$3" >"$d/$2"
}

# ---------------------------------------------------------------------------
# Aide envoyée aux hôtes (après le prélude de pannes-lib.sh)
# ---------------------------------------------------------------------------
read -r -d '' _M07_AIDE_DISTANTE <<'AIDE' || true
# empreinte CHEMIN — « lien:<cible> », « sha256:<somme>:<mode>:<propriétaire> » ou « absent »
empreinte() {
  if [ -L "$1" ]; then
    printf 'lien:%s\n' "$(readlink "$1")"
  elif [ -f "$1" ]; then
    printf 'sha256:%s:%s\n' "$(sha256sum <"$1" | cut -d' ' -f1)" "$(stat -c '%a:%U:%G' "$1")"
  else
    printf 'absent\n'
  fi
}
noter_injecte() { printf '%s\t%s\n' "$1" "$(empreinte "$1")" >>"$WB_DIR/$WB_EX.injecte"; }
# garder_reparations — avant restaurer_fichiers : un fichier qui n'est plus celui posé par la panne
# est une réparation ; il sort du manifeste et reste tel quel.
garder_reparations() {
  local m="$WB_DIR/$WB_EX.manifeste" e="$WB_DIR/$WB_EX.injecte" t src dst attendu
  [ -f "$e" ] || return 0
  if [ -f "$m" ]; then
    t="$(mktemp)"
    while IFS="$(printf '\t')" read -r src dst; do
      attendu="$(awk -F'\t' -v s="$src" '$1 == s { v = $2 } END { print v }' "$e")"
      if [ -n "$attendu" ] && [ "$(empreinte "$src")" != "$attendu" ]; then
        journal "annulation : $src modifié depuis l'injection (réparation), laissé tel quel"
        continue
      fi
      printf '%s\t%s\n' "$src" "$dst" >>"$t"
    done <"$m"
    cat "$t" >"$m"
    rm -f -- "$t"
  fi
  rm -f -- "$e"
}
# subst FICHIER REGEX REMPLACEMENT — première correspondance (Python, re.M), mémorisée.
# Code 10 si rien ne correspond (variante sans objet sur ce lab).
subst() {
  [ -f "$1" ] || return 10
  python3 - "$1" "$2" "$3" "$WB_DIR/$WB_EX.subst" <<'PY'
import base64, re, sys
f, rx, repl, m = sys.argv[1:5]
t = open(f, encoding="utf-8").read()
mo = re.search(rx, t, re.M)
if not mo:
    sys.exit(10)
avant, apres = mo.group(0), mo.expand(repl)
if avant == apres or not apres:
    sys.exit(10)
open(f, "w", encoding="utf-8").write(t[:mo.start()] + apres + t[mo.end():])
b = lambda s: base64.b64encode(s.encode()).decode()
with open(m, "a", encoding="utf-8") as h:
    h.write("%s\t%s\t%s\n" % (f, b(avant), b(apres)))
PY
}
# defaire_subst — dans l'ordre inverse : remet le texte d'origine là où le texte posé est encore là.
defaire_subst() {
  local m="$WB_DIR/$WB_EX.subst"
  [ -f "$m" ] || return 0
  python3 - "$m" <<'PY' | while IFS="$(printf '\t')" read -r etat fichier; do
import base64, sys
d = lambda s: base64.b64decode(s).decode()
lignes = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
for f, avant, apres in reversed(lignes):
    avant, apres = d(avant), d(apres)
    try:
        t = open(f, encoding="utf-8").read()
    except OSError:
        print("absent\t" + f)
        continue
    if apres in t:
        open(f, "w", encoding="utf-8").write(t.replace(apres, avant, 1))
        print("retabli\t" + f)
    else:
        print("repare\t" + f)
PY
    case "$etat" in
      retabli) journal "annulation : $fichier rétabli"; printf '%s\n' "$fichier" ;;
      repare) journal "annulation : $fichier modifié depuis l'injection (réparation), laissé tel quel" ;;
      *) journal "annulation : $fichier introuvable" ;;
    esac
  done
  rm -f -- "$m"
}
# sysctl_poser FICHIER CLÉ VALEUR — ajoute « CLÉ = VALEUR » au fichier (sauvegardé avant) et
# l'applique ; la valeur d'origine en mémoire est notée une seule fois par clé.
sysctl_poser() {
  local f="$1" k="$2" v="$3" orig
  orig="$(sysctl -n "$k" 2>/dev/null)" || return 1
  if ! grep -qs "^$k	" "$WB_DIR/$WB_EX.sysctl"; then
    printf '%s\t%s\t%s\n' "$k" "$orig" "$v" >>"$WB_DIR/$WB_EX.sysctl"
  fi
  sauver "$f"
  printf '%s = %s\n' "$k" "$v" >>"$f"
  sysctl -q -w "$k=$v" >/dev/null
}
# sysctl_restaurer — retire les fichiers posés (s'ils n'ont pas été modifiés depuis), puis remet la
# valeur d'origine des clés qui portent ENCORE la valeur posée.
sysctl_restaurer() {
  local k orig v
  garder_reparations
  restaurer_fichiers
  [ -f "$WB_DIR/$WB_EX.sysctl" ] || return 0
  while IFS="$(printf '\t')" read -r k orig v; do
    if [ "$(sysctl -n "$k" 2>/dev/null)" = "$v" ]; then
      sysctl -q -w "$k=$orig" >/dev/null 2>&1 && journal "annulation : $k = $orig"
    else
      journal "annulation : $k déjà modifié (réparation), laissé tel quel"
    fi
  done <"$WB_DIR/$WB_EX.sysctl"
  rm -f -- "$WB_DIR/$WB_EX.sysctl"
}
# mtu_poser INTERFACE MTU [NETNS] — MTU d'origine mémorisé.
mtu_poser() {
  local i="$1" v="$2" orig
  orig="$(cat "/sys/class/net/$i/mtu" 2>/dev/null)" || return 1
  [ "$orig" != "$v" ] || return 0
  printf '%s\t%s\t%s\n' "$i" "$orig" "$v" >>"$WB_DIR/$WB_EX.mtu"
  ip link set dev "$i" mtu "$v"
}
mtu_restaurer() {
  local i orig v
  [ -f "$WB_DIR/$WB_EX.mtu" ] || return 0
  while IFS="$(printf '\t')" read -r i orig v; do
    if [ "$(cat "/sys/class/net/$i/mtu" 2>/dev/null)" = "$v" ]; then
      ip link set dev "$i" mtu "$orig" 2>/dev/null && journal "annulation : MTU de $i = $orig"
    fi
  done <"$WB_DIR/$WB_EX.mtu"
  rm -f -- "$WB_DIR/$WB_EX.mtu"
}
# nft_table_poser NOM "corps de la table" — table « inet NOM » posée à chaud (et notée).
nft_table_poser() {
  command -v nft >/dev/null 2>&1 || return 10
  printf 'table inet %s {\n%s\n}\n' "$1" "$2" | nft -f - || return 1
  printf '%s\n' "$1" >>"$WB_DIR/$WB_EX.nft-tables"
}
nft_tables_retirer() {
  local t
  [ -f "$WB_DIR/$WB_EX.nft-tables" ] || return 0
  while read -r t; do
    if nft list table inet "$t" >/dev/null 2>&1; then
      nft delete table inet "$t" && journal "annulation : table nftables inet $t retirée"
    else
      journal "annulation : table nftables inet $t déjà absente (réparation)"
    fi
  done <"$WB_DIR/$WB_EX.nft-tables"
  rm -f -- "$WB_DIR/$WB_EX.nft-tables"
}
# defaire_noter "TEST" "ANNULATION" — à l'annulation, ANNULATION n'est exécutée que si TEST réussit
# (l'état cassé est encore là). Une ligne par action, rejouées dans l'ordre inverse.
defaire_noter() {
  printf '%s\t%s\n' "$1" "$2" >>"$WB_DIR/$WB_EX.defaire"
}
defaire_executer() {
  local f="$WB_DIR/$WB_EX.defaire" test annul
  [ -f "$f" ] || return 0
  tac "$f" | while IFS="$(printf '\t')" read -r test annul; do
    if eval "$test" >/dev/null 2>&1; then
      if eval "$annul" >/dev/null 2>&1; then journal "annulation : $annul"; else journal "annulation ÉCHOUÉE : $annul"; fi
    else
      journal "annulation : état déjà réparé ($test faux), rien à faire"
    fi
  done
  rm -f -- "$f"
}
# tout_defaire — annule tout ce que la panne a posé sur cet hôte (ordre inverse des mécanismes).
tout_defaire() {
  defaire_executer
  nft_tables_retirer
  sysctl_restaurer
  defaire_subst >/dev/null
  mtu_restaurer
}
# frr_recharger — valide /etc/frr/frr.conf puis recharge FRR (frr-reload.py par l'unité systemd).
frr_recharger() {
  vtysh --dryrun -f /etc/frr/frr.conf >/dev/null 2>&1 || return 1
  systemctl reload frr
}
# keepalived_recharger / haproxy_recharger / nginx_recharger — valident puis rechargent.
keepalived_recharger() {
  if keepalived --help 2>&1 | grep -q -- '--config-test'; then
    keepalived --config-test >/dev/null 2>&1 || return 1
  fi
  systemctl reload keepalived
}
haproxy_recharger() {
  haproxy -c -q -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1 || return 1
  systemctl reload haproxy
}
nginx_recharger() {
  nginx -t -q >/dev/null 2>&1 || return 1
  systemctl reload nginx
}
# if_admin — interface de la route par défaut (interface d'administration sur vsandbox).
if_admin() { ip -4 -o route show default | sed -nE 's/.* dev ([^ ]+).*/\1/p' | head -n 1; }
# ip_admin — adresse IPv4 (10.10.99.x) de l'interface d'administration.
ip_admin() { ip -4 -o addr show dev "$(if_admin)" | grep -oE '10\.10\.99\.[0-9]+' | grep -vx '10\.10\.99\.251' | head -n 1; }
# dev_vers ADRESSE [SOURCE] — interface de sortie vers ADRESSE (ip route get).
dev_vers() {
  if [ -n "${2:-}" ]; then
    ip -o route get "$1" from "$2" 2>/dev/null | sed -nE 's/.* dev ([^ ]+).*/\1/p' | head -n 1
  else
    ip -o route get "$1" 2>/dev/null | sed -nE 's/.* dev ([^ ]+).*/\1/p' | head -n 1
  fi
}
# devs_ecmp PRÉFIXE — interfaces de tous les sauts de la route (une par ligne).
devs_ecmp() { ip -4 route show "$1" 2>/dev/null | grep -oE 'dev [^ ]+' | awk '{ print $2 }' | sort -u; }
# nsip NETNS args… — « ip » dans l'espace de noms NETNS (vide : espace de noms initial).
nsip() {
  local n="$1"
  shift
  if [ -n "$n" ]; then ip -n "$n" "$@"; else ip "$@"; fi
}
# nsexec NETNS commande… — commande dans l'espace de noms NETNS (vide : espace de noms initial).
nsexec() {
  local n="$1"
  shift
  if [ -n "$n" ]; then ip netns exec "$n" "$@"; else "$@"; fi
}
# pairs_bgp [AS] — pairs BGP IPv4 (adresse ou interface), filtrés sur l'AS distant si donné ;
# format « pair<TAB>état<TAB>AS<TAB>nom d'hôte annoncé » (show bgp ipv4 unicast summary json).
pairs_bgp() {
  vtysh -c 'show bgp ipv4 unicast summary json' 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
p = d.get("peers") or d.get("ipv4Unicast", {}).get("peers", {})
a = sys.argv[1] if len(sys.argv) > 1 else ""
for k, v in p.items():
    if a and str(v.get("remoteAs")) != a:
        continue
    print("%s\t%s\t%s\t%s" % (k, v.get("state", "?"), v.get("remoteAs", "?"), v.get("hostname", "")))' "$@"
}
AIDE

# ---------------------------------------------------------------------------
# Exécution sur un hôte
# ---------------------------------------------------------------------------

# m07_maquette HÔTE — 0 si HÔTE est une VM de la maquette.
m07_maquette() { [[ -n "${_M07_VMID[$1]:-}" ]]; }

# m07_verifier_vm HÔTE — la VM VMID porte bien ce nom et l'étiquette env-m07 (une fois par exécution).
m07_verifier_vm() {
  local h="$1" vmid="${_M07_VMID[$1]}" conf
  [[ -n "${_M07_VM_OK[$h]:-}" ]] && return 0
  conf="$(remote "$WB_PVE_HOST" "qm config $vmid" 2>/dev/null)" || { wb_avert "VM $vmid ($h) introuvable sur $WB_PVE_HOST"; return 1; }
  if ! grep -qx "name: $h" <<<"$conf" || ! grep -Eq '^tags:.*env-m07' <<<"$conf"; then
    wb_avert "la VM $vmid ne s'appelle pas $h ou n'a pas l'étiquette env-m07 : aucune action"
    return 1
  fi
  _M07_VM_OK[$h]=1
}

# m07_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — exécute le script en root sur HÔTE (prélude de
# pannes-lib.sh + aide ci-dessus). Affiche sa sortie, renvoie son code (124 : délai dépassé).
m07_exec() {
  local h="$1" script sortie rc
  shift
  script="$(cat)"
  if m07_maquette "$h"; then
    m07_verifier_vm "$h" || return 1
    sortie="$({ printf '%s\n' "$_WB_PRELUDE"; _wb_entete "$@"; printf '%s\n%s\n' "$_M07_AIDE_DISTANTE" "$script"; } \
      | remote "$WB_PVE_HOST" "qm guest exec ${_M07_VMID[$h]} --pass-stdin 1 --timeout 110 -- bash -s" 2>/dev/null)" || return 1
    jq -r '."out-data" // empty' <<<"$sortie" 2>/dev/null || true
    jq -r '."err-data" // empty' <<<"$sortie" 2>/dev/null >&2 || true
    rc="$(jq -r 'if (.exited == 1 or .exited == true) then (.exitcode // 1) else 124 end' <<<"$sortie" 2>/dev/null)" || rc=1
    return "${rc:-1}"
  fi
  printf '%s\n%s\n' "$_M07_AIDE_DISTANTE" "$script" | wb_exec "$h" "$@"
}

# m07_annuler_hote HÔTE SERVICE… — tout_defaire sur l'hôte, puis rechargement des services cités
# (frr, keepalived, haproxy, nginx). Ne fait jamais échouer l'annulation.
m07_annuler_hote() {
  local h="$1"
  shift
  m07_exec "$h" SERVICES="$*" >/dev/null 2>&1 <<'EOF' || wb_avert "annulation incomplète sur $h (voir /var/lib/workbook/pannes.log)"
tout_defaire
for s in $SERVICES; do
  case "$s" in
    frr) systemctl is-active -q frr && frr_recharger ;;
    keepalived) systemctl is-active -q keepalived && keepalived_recharger ;;
    haproxy) systemctl is-active -q haproxy && haproxy_recharger ;;
    nginx) systemctl is-active -q nginx && nginx_recharger ;;
  esac
done
exit 0
EOF
}

# m07_attendre DÉLAI COMMANDE [args…] — relance COMMANDE toutes les 3 s jusqu'à succès (0) ou délai.
m07_attendre() {
  local delai="$1" t=0
  shift
  until "$@" >/dev/null 2>&1; do
    t=$((t + 3))
    ((t <= delai)) || return 1
    sleep 3
  done
}

# m07_existe HÔTE — l'hôte du socle répond en SSH (gw02 et lb02 sont facultatifs selon l'avancement).
m07_existe() { remote "$1" true >/dev/null 2>&1; }

# m07_vip_sur HÔTE ADRESSE — l'hôte porte l'adresse (VIP VRRP) sur une de ses interfaces.
m07_vip_sur() {
  m07_exec "$1" A="$2" >/dev/null 2>&1 <<'EOF'
ip -4 -o addr show | grep -q " $A/"
EOF
}

# m07_essayer EXX NB DÉPART — appelle _mEXX_une N (0 : panne posée et constatée ; 10 : variante sans
# effet sur ce lab, déjà défaite ; autre : erreur) pour N = DÉPART, DÉPART+1… jusqu'à un succès.
m07_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
    m07_journal "$ex" "variante $n sans effet sur ce lab : on passe à la suivante"
  done
  wb_avert "aucune variante de M07-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}
