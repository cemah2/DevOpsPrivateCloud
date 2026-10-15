# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M14-E39 « Panne : l'API ne répond plus »
#
# Un seul nœud de contrôle est touché à chaque fois (le quorum etcd n'est jamais en jeu). Variantes :
#   1. sur le nœud qui porte la VIP : HAProxy arrêté, et le suivi de keepalived (track_script)
#      retiré de keepalived.conf (« la VIP basculait sans raison ») : la VIP reste sur un nœud où plus
#      rien n'écoute en 8443 → connexion refusée ;
#   2. sur le nœud qui porte la VIP : table nftables « durcissement_infoger » qui jette le 8443 venu de
#      l'extérieur (la vérification locale de keepalived passe toujours) → délai dépassé ;
#   3. sur un nœud de contrôle tiré au hasard : --etcd-servers du manifeste kube-apiserver pointé sur le
#      port de métriques d'etcd (2381, en HTTP) : ce kube-apiserver redémarre en boucle ;
#   4. sur un nœud de contrôle tiré au hasard : certificat de service du kube-apiserver réémis sans le
#      nom ni l'adresse de la VIP : « x509: certificate is valid for … » une connexion sur trois.
# Si une variante n'a pas d'effet (par exemple keepalived suit HAProxy par track_process et fait
# basculer la VIP), la suivante est essayée. Toutes les modifications sont sauvegardées sur le nœud.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m14-commun.sh
source "$WB_ROOT/modules/14-kubernetes-admin/corrige/pannes/_m14-commun.sh"

# _e39_san_vip HÔTE — le certificat présenté par le kube-apiserver de HÔTE contient le nom de la VIP.
_e39_san_vip() {
  echo | timeout 10 openssl s_client -connect "${_M14_IP[$1]}:6443" -servername "$_M14_API_NOM" 2>/dev/null |
    openssl x509 -noout -ext subjectAltName 2>/dev/null | grep -q "$_M14_API_NOM"
}
_e39_san_sans_vip() { ! _e39_san_vip "$1"; }
_e39_apiserver_ko() { ! m14_apiserver_sain "$1"; }

# _e39_api_muette_stable — l'API ne répond pas par la VIP, trois fois de suite (15 s).
_e39_api_muette_stable() {
  m14_api_muette && sleep 5 && m14_api_muette && sleep 5 && m14_api_muette
}

_m14E39_une() {
  local n="$1" h rc=0
  case "$n" in
    1 | 2) h="$(m14_vip_porteur)" || return 1 ;;
    *) h="$(m14_hasard "${_M14_CP[@]}")" ;;
  esac
  case "$n" in
    1)
      m14_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
f=/etc/keepalived/keepalived.conf
[ -f "$f" ] || exit 10
systemctl is-active -q haproxy || exit 10
sauver "$f"
if grep -q 'track_script' "$f"; then
  awk 'BEGIN { s = 0 }
       s == 0 && /^[[:space:]]*track_script[[:space:]]*\{/ { s = 1; next }
       s == 1 && /^[[:space:]]*\}/ { s = 0; next }
       s == 1 { next }
       { print }' "$f" > "$f.wb-tmp"
  printf '\n# IG-2241 (InfoGér) : suivi retiré, la VIP basculait « sans raison »\n' >> "$f.wb-tmp"
  cat "$f.wb-tmp" > "$f" && rm -f "$f.wb-tmp"
  if ! keepalived -t -f "$f" >/dev/null 2>&1; then restaurer_fichiers; exit 1; fi
  systemctl reload keepalived
else
  printf '\n# IG-2241 (InfoGér) : relu, rien à changer\n' >> "$f"
fi
systemctl stop haproxy
journal "HAProxy arrêté, track_script retiré de keepalived.conf"
EOF
      ;;
    2)
      m14_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
command -v nft >/dev/null 2>&1 || exit 10
nft list table inet durcissement_infoger >/dev/null 2>&1 && exit 10
nft -f - <<'NFT'
table inet durcissement_infoger {
  chain entree {
    type filter hook input priority -5; policy accept;
    iifname != "lo" tcp dport 8443 drop comment "IG-2242 : API réservée au réseau d'administration"
  }
}
NFT
journal "table nftables durcissement_infoger ajoutée (8443 jeté hors lo)"
EOF
      ;;
    3)
      m14_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
f=/etc/kubernetes/manifests/kube-apiserver.yaml
grep -q -- '--etcd-servers=https://127.0.0.1:2379' "$f" || exit 10
sauver "$f"
sed -i 's|--etcd-servers=https://127.0.0.1:2379|--etcd-servers=https://127.0.0.1:2381|' "$f"
journal "manifeste kube-apiserver : --etcd-servers vers 127.0.0.1:2381"
EOF
      ;;
    4)
      m14_wb_exec "$h" IP="${_M14_IP[$h]}" >/dev/null <<'EOF' || rc=$?
p=/etc/kubernetes/pki
[ -f "$p/ca.key" ] && [ -f "$p/apiserver.crt" ] || exit 10
[ -e "$WB_DIR/$WB_EX.empreinte" ] && exit 10
sauver "$p/apiserver.crt"
sauver "$p/apiserver.key"
d="$(mktemp -d)"
cat > "$d/ext" <<X
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$(hostname -s),DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc,DNS:kubernetes.default.svc.cluster.local,IP:10.96.0.1,IP:$IP
X
openssl req -new -newkey rsa:2048 -nodes -keyout "$d/k" -out "$d/r" -subj /CN=kube-apiserver >/dev/null 2>&1 &&
  openssl x509 -req -in "$d/r" -CA "$p/ca.crt" -CAkey "$p/ca.key" -CAcreateserial -CAserial "$d/srl" \
    -days 365 -sha256 -extfile "$d/ext" -out "$d/c" >/dev/null 2>&1 || { rm -rf "$d"; restaurer_fichiers; exit 1; }
install -m 644 "$d/c" "$p/apiserver.crt" && install -m 600 "$d/k" "$p/apiserver.key"
printf '%s\n' "$(sha256sum "$p/apiserver.crt" | cut -d' ' -f1)" > "$WB_DIR/$WB_EX.empreinte"
rm -rf "$d"
id="$(crictl_ ps -q --name '^kube-apiserver$' 2>/dev/null | head -n 1)"
[ -n "$id" ] && crictl_ stop "$id" >/dev/null 2>&1
journal "certificat apiserver réémis sans le nom ni l'adresse de la VIP (renouvellement « manuel »)"
EOF
      ;;
  esac
  ((rc == 0)) || return "$rc"
  m14_ecrire E39 cible "$h"
  m14_journal E39 "variante $n posée sur $h"
  local ok=0
  case "$n" in
    1 | 2) m14_attendre 40 _e39_api_muette_stable && ok=1 ;;
    3) m14_attendre 180 _e39_apiserver_ko "$h" && sleep 20 && _e39_apiserver_ko "$h" && ok=1 ;;
    4) m14_attendre 120 _e39_san_sans_vip "$h" && ok=1 ;;
  esac
  if ((ok == 0)); then
    _e39_defaire "$n" "$h"
    m14_oublier E39 cible
    return 10
  fi
}

_e39_defaire() {
  local n="$1" h="$2"
  m14_wb_exec "$h" N="$n" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h"
case "$N" in
  1)
    if grep -qs 'IG-2241' /etc/keepalived/keepalived.conf; then
      restaurer_fichiers; systemctl reload keepalived || systemctl restart keepalived
      journal "annulation : keepalived.conf rétabli"
    else
      oublier_fichiers
    fi
    if ! systemctl is-active -q haproxy; then systemctl start haproxy; journal "annulation : HAProxy relancé"; fi
    ;;
  2)
    if nft list table inet durcissement_infoger >/dev/null 2>&1; then
      nft delete table inet durcissement_infoger; journal "annulation : table nftables retirée"
    fi
    ;;
  3)
    if grep -qs -- '--etcd-servers=https://127.0.0.1:2381' /etc/kubernetes/manifests/kube-apiserver.yaml; then
      restaurer_fichiers; journal "annulation : manifeste kube-apiserver rétabli"
    else
      oublier_fichiers
    fi
    ;;
  4)
    p=/etc/kubernetes/pki
    if [ -f "$WB_DIR/$WB_EX.empreinte" ] && [ "$(sha256sum "$p/apiserver.crt" | cut -d' ' -f1)" = "$(cat "$WB_DIR/$WB_EX.empreinte")" ]; then
      restaurer_fichiers
      id="$(crictl_ ps -q --name '^kube-apiserver$' 2>/dev/null | head -n 1)"
      [ -n "$id" ] && crictl_ stop "$id" >/dev/null 2>&1
      journal "annulation : certificat apiserver d'origine rétabli"
    else
      oublier_fichiers
    fi
    rm -f "$WB_DIR/$WB_EX.empreinte"
    ;;
esac
EOF
}

# E39 ne crée pas de témoins (l'API peut ne plus répondre) mais exige un cluster sain avant.
_e39_preparer() {
  if [[ -n "${_M14_ASTREINTE:-}" ]]; then return 0; fi
  m14_sain
}

panne_E39_v1() { _e39_preparer && m14_essayer E39 4 1; }
panne_E39_v2() { _e39_preparer && m14_essayer E39 4 2; }
panne_E39_v3() { _e39_preparer && m14_essayer E39 4 3; }
panne_E39_v4() { _e39_preparer && m14_essayer E39 4 4; }

verifier_E39() {
  local h
  h="$(m14_lire E39 cible)"
  [[ -n "$h" ]] || return 1
  case "$WB_VAR" in
    1 | 2) m14_api_muette ;;
    3) _e39_apiserver_ko "$h" ;;
    4) _e39_san_sans_vip "$h" ;;
  esac
}

annuler_E39() {
  local h v
  h="$(m14_lire E39 cible)"
  if [[ -n "$h" ]]; then
    case "${WB_VAR:-}" in
      [1-4]) _e39_defaire "$WB_VAR" "$h" ;;
      *) for v in 1 2 3 4; do _e39_defaire "$v" "$h"; done ;;
    esac
    m14_journal E39 "annulation ($h)"
  fi
  m14_oublier E39 cible
}

resume_E39() {
  local h
  h="$(m14_lire E39 cible)"
  case "${WB_VAR:-}" in
    1 | 2) echo "kubectl ne joint plus l'API : « k8s-api.par1.medisphere.internal:8443 » ne répond pas." ;;
    3) echo "Le kube-apiserver de ${h:-?} redémarre en boucle depuis une intervention." ;;
    4) echo "kubectl échoue par intermittence avec une erreur de certificat x509." ;;
  esac
}

symptome_E39() {
  local h
  h="$(m14_lire E39 cible)"
  case "${WB_VAR:-}" in
    1 | 2)
      wb_symptome "Ticket INC-4139 — De : Nadia Roussel — priorité P1" \
        "Plus personne ne joint le cluster : kubectl s'arrête sur « Unable to connect to the server »" \
        "vers k8s-api.par1.medisphere.internal:8443, et la CI de déploiement est rouge. Les" \
        "applications déjà en place ont l'air de tourner. InfoGér a travaillé sur les nœuds de" \
        "contrôle cette nuit (« durcissement » et « fiabilisation de la VIP »)." \
        "Rétablis l'accès, puis dis-moi pourquoi la haute disponibilité ne nous a pas protégés." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 14 39"
      ;;
    3)
      wb_symptome "Ticket INC-4139 — De : Karim Benali" \
        "Le cluster répond, mais « kubectl -n kube-system get pods » montre le pod" \
        "kube-apiserver-$h qui redémarre en boucle depuis le passage d'InfoGér sur ce nœud" \
        "(« alignement des ports sur la supervision »). On tourne sur deux serveurs d'API sur trois :" \
        "la prochaine panne sera la bonne. Remets le troisième en service." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 14 39"
      ;;
    4)
      wb_symptome "Ticket INC-4139 — De : Nadia Roussel" \
        "kubectl et la CI échouent « une fois sur trois » avec une erreur du genre" \
        "« tls: failed to verify certificate: x509: certificate is valid for … not" \
        "k8s-api.par1.medisphere.internal ». En relançant, ça passe. InfoGér a « renouvelé" \
        "un certificat à la main » sur un nœud de contrôle cette semaine. Corrige proprement." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 14 39"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 14 E39 4 "$@"; }
fi
