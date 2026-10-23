# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq, expressions sed et scripts distants entre apostrophes
# break-S11.sh — F3-S11 « Jeudi : la moitié des noms ne répond plus » (INC-5911)
#
# Variantes (une cause chacune, toutes réversibles, aucune donnée touchée) :
#   1. RÉSOLUTION — récurseur de dns02 : l'ancre DNSSEC positive de par1.medisphere.internal
#      (dnssec.trustanchors de /etc/powerdns/recursor.yml, M06-E26) reçoit une empreinte fausse
#      (dernier chiffre hexadécimal changé), puis pdns-recursor est redémarré. dns02 répond SERVFAIL à
#      tout nom de par1 (et de apps.par1, signée sous par1) ; dns01 va bien. Les VMs (glibc) et CoreDNS
#      (policy sequential, M15-E04) interrogent dns01 d'abord : presque rien de visible, sauf la sonde
#      « dns » du témoin de mon01 (SOA de par1 sur chaque récurseur, SondeEnEchec) ; redondance perdue
#      (panne latente). Le fichier est sauvegardé (sauver) avant ;
#   2. ROUTAGE — sur la passerelle ACTIVE (porteuse de 10.10.40.1), une règle nftables insérée en tête
#      de « inet filter input » jette le BGP (TCP 179) d'UN travailleur : la session tombe à
#      l'expiration du temps de maintien (puis du redémarrage gracieux), les /32 que ce nœud était seul
#      à annoncer (services en externalTrafficPolicy: Local) tombent sur la route de rejet de
#      10.10.41.0/24 (M15-E25) : injoignables depuis l'extérieur du cluster ; les autres adresses
#      restent servies par ECMP. Le travailleur choisi n'est jamais le seul annonceur de 10.10.41.65
#      (base de PRODUCTION jointe par OpenBao). Sans travailleur seul annonceur d'une adresse, la
#      variante 3 est tirée à la place ;
#   3. ROUTAGE — sur la passerelle ACTIVE, une route noyau « oubliée » pour 10.10.41.10/32 (Gateway
#      gw-par1 : tous les noms *.apps) en ECMP vers un nœud réel ET vers 10.10.40.249 (adresse sans
#      hôte), de métrique 10 (meilleure que celle de BGP, 20) : selon le hachage, les flux d'un client
#      partent vers le trou ; certains clients n'ont jamais le problème, d'autres toujours.
# La variante « MTU abaissée » de la fiche a été écartée : la négociation de MSS et la découverte du MTU
# du chemin la masquent dans ce lab (aucun symptôme garanti : CONVENTIONS §11.10).
#
# Annulation (idempotente) : fichier du récurseur restauré et pdns-recursor redémarré ; règles nftables
# ajoutées retirées (par handle) et route retirée, sur les DEUX passerelles (la VIP a pu basculer).
# Accès : SSH admin + sudo sur dns02, gw01, gw02 ; dig sur adm01.

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_f3-fin-pannes.sh
source "$WB_ROOT/finaux/F3-astreinte/corrige/pannes/_f3-fin-pannes.sh"

read -r -a _S11_GW <<<"${WB_F3_PASSERELLES:-gw01 gw02}"
_S11_DNS01=10.10.20.10
_S11_DNS02=10.10.20.16
_S11_HOTE_DNS02="${WB_F3_DNS02:-dns02}"
_S11_NOM_TEST="${WB_F3_S11_NOM:-git01.par1.medisphere.internal}"
_S11_GATEWAY_IP=10.10.41.10
_S11_SAUT_MORT="${WB_F3_S11_SAUT_MORT:-10.10.40.249}"
_S11_PROD_LB=10.10.41.65

# _s11_statut SERVEUR NOM — statut DNS (NOERROR, SERVFAIL…) de la réponse, vide si pas de réponse.
_s11_statut() {
  dig +time=3 +tries=1 "@$1" "$2" A 2>/dev/null | sed -n 's/.*status: \([A-Z]*\),.*/\1/p' | head -n 1
}
# _s11_valide SERVEUR NOM — réponse NOERROR avec le drapeau ad (validée DNSSEC).
_s11_valide() {
  dig +dnssec +time=3 +tries=1 "@$1" "$2" A 2>/dev/null | grep -Eq 'flags:[a-z ]* ad[ ;]'
}
# _s11_active — passerelle qui porte 10.10.40.1 (VIP du VLAN 40), vide sinon.
_s11_active() {
  local g
  for g in "${_S11_GW[@]}"; do
    if remote "$g" "ip -o -4 addr show" 2>/dev/null </dev/null | grep -q ' 10\.10\.40\.1/'; then
      printf '%s\n' "$g"
      return 0
    fi
  done
  return 1
}
# _s11_routes GW — routes BGP du noyau de la passerelle (JSON).
_s11_routes() { remote "$1" "ip -j -4 route show proto bgp" 2>/dev/null </dev/null || echo '[]'; }
# _s11_sauts JSON IP — prochains sauts de la /32 (un par ligne).
_s11_sauts() {
  jq -r --arg ip "$2" '.[] | select(.dst == $ip) | ((.nexthops // [])[].gateway, (.gateway // empty))' <<<"$1" 2>/dev/null || true
}

_s11_sain() {
  local a
  f3fp_preparer S11 dig || return 1
  _s11_valide "$_S11_DNS01" "$_S11_NOM_TEST" || { f3fp_refus "dns01 ne valide pas $_S11_NOM_TEST"; return 1; }
  _s11_valide "$_S11_DNS02" "$_S11_NOM_TEST" || { f3fp_refus "dns02 ne valide pas $_S11_NOM_TEST"; return 1; }
  a="$(_s11_active)" || { f3fp_refus "aucune passerelle ne porte 10.10.40.1"; return 1; }
  [[ "$(_s11_sauts "$(_s11_routes "$a")" "$_S11_GATEWAY_IP" | grep -c .)" -ge 2 ]] ||
    { f3fp_refus "$a n'a pas au moins deux chemins BGP vers $_S11_GATEWAY_IP (ECMP, M15-E25)"; return 1; }
  f3fp_ecrire S11 passerelle "$a"
}

# --- Variante 1 : ancre DNSSEC de dns02 -------------------------------------------------------------------
_s11_v1() {
  wb_exec "$_S11_HOTE_DNS02" >/dev/null <<'EOF'
f=/etc/powerdns/recursor.yml
[ -f "$f" ] || exit 1
motif='^[[:space:]]*-[[:space:]]+["'"'"']?[0-9]+ [0-9]+ 2 [0-9A-Fa-f]{64}["'"'"']?[[:space:]]*$'
grep -Eq "$motif" "$f" || exit 10
sauver "$f"
# Dernier chiffre de chaque empreinte SHA-256 (type 2) changé : 0 → 1, tout autre → 0.
# Écriture par « cat > » : propriétaire et droits du fichier conservés.
sed -E "/$motif/{s/0([\"']?[[:space:]]*)\$/1\\1/;t;s/[0-9A-Fa-f]([\"']?[[:space:]]*)\$/0\\1/}" "$f" > "$f.f3"
cmp -s "$f" "$f.f3" && { rm -f "$f.f3"; exit 10; }
cat "$f.f3" > "$f" && rm -f "$f.f3"
# Empreinte du fichier injecté : l'annulation ne restaure que s'il n'a pas été réparé depuis.
sha256sum "$f" | cut -d' ' -f1 > "${WB_DIR:?}/${WB_EX:?}.injecte"
systemctl restart pdns-recursor || exit 1
journal "ancre(s) DNSSEC de recursor.yml modifiée(s), pdns-recursor redémarré"
EOF
}

# --- Variante 2 : BGP d'un travailleur jeté sur la passerelle active ----------------------------------------
# _s11_choisir_noeud ROUTES_JSON — travailleur seul annonceur du plus grand nombre de /32 (hors base de
#   prod), sur la sortie ; code 1 s'il n'y en a pas.
_s11_choisir_noeud() {
  jq -r --arg prod "$_S11_PROD_LB" '
    [ .[] | select(.dst | startswith("10.10.41.")) | {dst, sauts: ([(.nexthops // [])[].gateway] + [(.gateway // empty)])} ]
    | (map(select((.sauts | length) == 1 and .dst == $prod) | .sauts[0])) as $interdits
    | map(select((.sauts | length) == 1)) | group_by(.sauts[0])
    | map({noeud: .[0].sauts[0], n: length}) | map(select(.noeud as $x | $interdits | index($x) | not))
    | sort_by(-.n) | .[0].noeud // empty' <<<"$1" 2>/dev/null | grep -E '^10\.10\.40\.[0-9]+$'
}

_s11_v2() {
  local gw r w ips
  gw="$(f3fp_lire S11 passerelle)"
  r="$(_s11_routes "$gw")"
  w="$(_s11_choisir_noeud "$r")" || return 10
  ips="$(jq -r --arg w "$w" '.[] | select((.gateway // "") == $w and ((.nexthops // []) | length) == 0) | .dst' <<<"$r" | paste -sd' ')"
  f3fp_ecrire S11 noeud "$w"
  f3fp_ecrire S11 adresses "$ips"
  wb_exec "$gw" NOEUD="$w" >/dev/null <<'EOF'
nft_inserer inet filter input "ip saddr $NOEUD tcp dport 179 drop" || exit 1
journal "BGP de $NOEUD jeté en entrée (inet filter input)"
EOF
}

# --- Variante 3 : route ECMP vers un trou ------------------------------------------------------------------
_s11_v3() {
  local gw r vivant
  gw="$(f3fp_lire S11 passerelle)"
  r="$(_s11_routes "$gw")"
  vivant="$(_s11_sauts "$r" "$_S11_GATEWAY_IP" | head -n 1)"
  [[ -n "$vivant" ]] || return 1
  wb_exec "$gw" VIVANT="$vivant" MORT="$_S11_SAUT_MORT" CIBLE="$_S11_GATEWAY_IP" >/dev/null <<'EOF'
# Le saut « mort » ne doit répondre à rien (aucun hôte, aucune entrée de voisinage valide).
if ping -c 1 -W 1 "$MORT" >/dev/null 2>&1; then exit 10; fi
ip route add "$CIBLE/32" metric 10 nexthop via "$VIVANT" nexthop via "$MORT" || exit 1
printf '%s/32 metric 10\n' "$CIBLE" > "$WB_DIR/$WB_EX.route"
journal "route $CIBLE/32 metric 10 en ECMP via $VIVANT et $MORT"
EOF
}

panne_S11_v1() {
  local rc=0
  _s11_sain || return 1
  _s11_v1 || rc=$?
  if ((rc == 10)); then
    wb_avert "aucune ancre DNSSEC de type 2 dans recursor.yml de dns02 : variante 3 tirée à la place"
    WB_VAR=3
    _s11_v3
    return
  fi
  ((rc == 0)) && f3fp_journal S11 "ancre DNSSEC de dns02 faussée"
  return "$rc"
}

panne_S11_v2() {
  local rc=0
  _s11_sain || return 1
  _s11_v2 || rc=$?
  if ((rc == 10)); then
    wb_avert "aucun travailleur n'est seul à annoncer une adresse : variante 3 tirée à la place"
    WB_VAR=3
    _s11_v3
    return
  fi
  ((rc == 0)) && f3fp_journal S11 "BGP de $(f3fp_lire S11 noeud) jeté sur $(f3fp_lire S11 passerelle) (adresses : $(f3fp_lire S11 adresses))"
  return "$rc"
}

panne_S11_v3() {
  _s11_sain || return 1
  _s11_v3 || return 1
  f3fp_journal S11 "route ECMP vers $_S11_SAUT_MORT posée sur $(f3fp_lire S11 passerelle)"
}

# _s11_sans_saut GW NOEUD IP — la /32 n'a plus le nœud comme prochain saut (retirée ou rejetée).
_s11_sans_saut() { ! _s11_sauts "$(_s11_routes "$1")" "$3" | grep -qxF "$2"; }

verifier_S11() {
  local gw ip
  gw="$(f3fp_lire S11 passerelle)"
  case "$WB_VAR" in
    1)
      f3fp_attendre 30 eval '[[ "$(_s11_statut "$_S11_DNS02" "$_S11_NOM_TEST")" == SERVFAIL ]]' || return 1
      [[ "$(_s11_statut "$_S11_DNS01" "$_S11_NOM_TEST")" == NOERROR ]]
      ;;
    2)
      # Temps de maintien de Cilium (90 s par défaut) puis redémarrage gracieux (120 s) : 6 min au plus.
      ip="$(f3fp_lire S11 adresses)"
      ip="${ip%% *}"
      [[ -n "$ip" ]] || return 1
      echo "Attente de la chute de la session BGP (jusqu'à 6 min)…"
      f3fp_attendre 360 _s11_sans_saut "$gw" "$(f3fp_lire S11 noeud)" "$ip"
      ;;
    3)
      remote "$gw" "ip -4 route show $_S11_GATEWAY_IP/32" 2>/dev/null </dev/null | grep -qF "$_S11_SAUT_MORT"
      ;;
    *) return 1 ;;
  esac
}

annuler_S11() {
  local g
  # Récurseur de dns02 (sans effet si rien n'a été sauvegardé). Le fichier n'est remis que s'il est
  # encore exactement dans l'état injecté : une réparation par le playbook n'est jamais défaite, et le
  # récurseur n'est pas redémarré pour rien (son cache serait vidé).
  wb_exec "$_S11_HOTE_DNS02" >/dev/null 2>&1 <<'EOF' || wb_avert "dns02 injoignable : restaure /etc/powerdns/recursor.yml par le playbook DNS (dns01.yml --limit dns02)"
f=/etc/powerdns/recursor.yml
m="${WB_DIR:?}/${WB_EX:?}.manifeste"
inj="${WB_DIR:?}/${WB_EX:?}.injecte"
if [ -f "$m" ]; then
  if [ -f "$inj" ] && [ "$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)" = "$(cat "$inj")" ]; then
    restaurer_fichiers
    systemctl restart pdns-recursor
    journal "annulation : recursor.yml restauré, pdns-recursor redémarré"
  else
    # Déjà réparé : on jette seulement la sauvegarde.
    while IFS="$(printf '\t')" read -r _src dst; do
      if [ "$dst" != ABSENT ] && [ -n "$dst" ]; then rm -f -- "$dst"; fi
    done < "$m"
    rm -f -- "$m"
    journal "annulation : recursor.yml déjà réparé, laissé tel quel"
  fi
  rm -f -- "$inj"
fi
EOF
  # Passerelles : les deux (la VIP a pu basculer depuis l'injection). La règle n'est retirée que si le
  # handle noté désigne ENCORE la règle injectée : après un rechargement par le rôle pare_feu (« flush
  # ruleset »), les handles sont renumérotés et le même numéro peut désigner une règle légitime.
  for g in "${_S11_GW[@]}"; do
    wb_exec "$g" NOEUD="$(f3fp_lire S11 noeud)" >/dev/null 2>&1 <<'EOF' || wb_avert "$g injoignable : vérifie à la main la règle nftables (179) et la route de 10.10.41.10"
f="${WB_DIR:?}/${WB_EX:?}.nft-ajouts"
if [ -f "$f" ]; then
  while read -r fam tab ch h; do
    if [ -n "$NOEUD" ] && nft -a list chain "$fam" "$tab" "$ch" 2>/dev/null | grep -E "# handle $h\$" |
      grep -qF "ip saddr $NOEUD tcp dport 179 drop"; then
      nft delete rule "$fam" "$tab" "$ch" handle "$h" 2>/dev/null || true
      journal "annulation : règle $fam $tab $ch handle $h retirée"
    fi
  done < "$f"
  rm -f -- "$f"
fi
f="$WB_DIR/$WB_EX.route"
if [ -f "$f" ]; then
  r="$(cat "$f")"
  # shellcheck disable=SC2086
  ip route del $r 2>/dev/null || true
  rm -f "$f"
  journal "annulation : route $r retirée"
fi
EOF
  done
  f3fp_attendre 30 _s11_valide "$_S11_DNS02" "$_S11_NOM_TEST" || wb_avert "dns02 ne valide pas encore $_S11_NOM_TEST"
  f3fp_oublier S11 passerelle
  f3fp_oublier S11 noeud
  f3fp_oublier S11 adresses
  f3fp_journal S11 "annulation"
}

symptome_S11() {
  local l
  case "$WB_VAR" in
    1) l="Nadia : « la supervision témoin de mon01 voit une sonde DNS en échec (l'alerte va tomber dans quelques minutes), et un collègue dit qu'un nom en par1 \"ne répondait pas\" tout à l'heure ; depuis mon poste, tout répond. Je ne voudrais pas qu'on découvre le problème le jour où l'autre serveur tombe. »" ;;
    2) l="La supervision témoin de mon01 signale des points d'entrée injoignables ; Nadia : « certaines adresses en 10.10.41.x ne répondent plus du tout depuis le bureau, d'autres oui » (adresses touchées selon mon01 : $(f3fp_lire S11 adresses))." ;;
    *) l="Nadia : « des cabinets et des collègues n'arrivent plus à ouvrir les pages *.apps : chez certains ça n'aboutit jamais, chez d'autres tout va bien ; deux postes côte à côte n'ont pas le même résultat »." ;;
  esac
  _f3p_symptome S11 INC-5911 "INC-5911 — Jeudi 14 h 05 — De : Nadia Roussel (support)" \
    "« La moitié des noms ne répond plus, et pas toujours les mêmes. »" \
    "$l" \
    "Temps cible : 60 min."
}

resume_S11() { echo "Une partie des noms ou des adresses de services ne répond plus, de façon intermittente"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F3 S11 3 "$@"; }
fi
