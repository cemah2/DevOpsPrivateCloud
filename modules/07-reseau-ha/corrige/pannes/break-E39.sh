# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M07-E39 « Panne : 503 Service Unavailable »
#
# Cible : HAProxy de démonstration hap01 (VMID 2079, M07-E10) et ses serveurs srv01/srv02.
# Variantes (chacune fait échouer le contrôle de santé de TOUS les serveurs du backend → 503) :
#   1. hap01 : « check-ssl verify required ca-file … » ajouté aux lignes server (préparation du
#      ré-chiffrement) alors que les serveurs parlent HTTP en clair → échec de couche 6 ;
#   2. hap01 : l'URI du contrôle de santé devient /etat (inexistante) → 404, échec de couche 7 ;
#   3. srv01 et srv02 : Nginx n'écoute plus que sur 127.0.0.1:80 (« durcissement ») → connexion
#      refusée, échec de couche 4 ;
#   4. srv01 et srv02 : le fichier de maintenance du rôle nginx_web (RB-070) est présent sur les deux
#      → /sante répond 503, les deux serveurs sont retirés.
# Constat : par la socket d'administration de hap01, tous les serveurs d'un backend sont DOWN.
# Sauvegardes : /var/lib/workbook/M07-E39.* sur hap01, srv01, srv02.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m07-commun.sh
source "$WB_ROOT/modules/07-reseau-ha/corrige/pannes/_m07-commun.sh"

# _e39_etat — sur hap01 : « tous-up », « backend-down » (un backend sans aucun serveur UP) ou « autre ».
_e39_etat() {
  m07_exec hap01 2>/dev/null <<'EOF'
s="$(sed -nE 's/^[ \t]*stats[ \t]+socket[ \t]+([^ \t]+).*/\1/p' /etc/haproxy/haproxy.cfg | head -n 1)"
[ -S "$s" ] || { echo autre; exit 0; }
python3 - "$s" <<'PY'
import csv, io, socket, sys
c = socket.socket(socket.AF_UNIX)
c.settimeout(5)
c.connect(sys.argv[1])
c.sendall(b"show stat\n")
data = b""
while True:
    b = c.recv(65536)
    if not b:
        break
    data += b
rows = list(csv.DictReader(io.StringIO(data.decode().lstrip("# "))))
srv = {}
for r in rows:
    if r.get("svname") in ("FRONTEND", "BACKEND") or not r.get("check_status"):
        continue
    srv.setdefault(r["pxname"], []).append(r.get("status", ""))
if not srv:
    print("autre")
elif any(all(not s.startswith("UP") for s in v) for v in srv.values()):
    print("backend-down")
elif all(s.startswith("UP") for v in srv.values() for s in v):
    print("tous-up")
else:
    print("autre")
PY
EOF
}
_e39_casse() { [[ "$(_e39_etat)" == backend-down ]]; }
_e39_sain() { [[ "$(_e39_etat)" == tous-up ]]; }

_e39_precondition() {
  if ! _e39_sain; then
    wb_avert "hap01 : tous les serveurs ne sont pas UP (ou socket d'administration introuvable) : lab/bin/check 07 39"
    return 1
  fi
}

_mE39_une() {
  local n="$1" h rc=0
  case "$n" in
    1 | 2)
      m07_exec hap01 N="$n" >/dev/null <<'EOF' || rc=$?
f=/etc/haproxy/haproxy.cfg
k=0
if [ "$N" = 1 ]; then
  while subst "$f" '^(?![^\n]*check-ssl)([ \t]*server[ \t]+[^\n]*\bcheck\b[^\n]*?)[ \t]*$' '\1 check-ssl verify required ca-file /etc/ssl/certs/ca-certificates.crt'; do k=$((k + 1)); done
  journal "$f : check-ssl ajouté à $k serveur(s)"
else
  while subst "$f" '^([ \t]*http-check[ \t]+send\b[^\n]*\buri[ \t]+)(?!/etat\b)\S+' '\g<1>/etat'; do k=$((k + 1)); done
  while subst "$f" '^([ \t]*option[ \t]+httpchk[ \t]+[A-Z]+[ \t]+)(?!/etat\b)\S+' '\g<1>/etat'; do k=$((k + 1)); done
  journal "$f : URI de contrôle de santé -> /etat ($k ligne(s))"
fi
[ "$k" -gt 0 ] || exit 10
haproxy_recharger || exit 1
exit 0
EOF
      ;;
    3 | 4)
      for h in srv01 srv02; do
        m07_exec "$h" N="$n" >/dev/null <<'EOF' || rc=$?
k=0
if [ "$N" = 3 ]; then
  for f in $(grep -rlE '^[[:space:]]*listen[[:space:]]+80([[:space:];])' /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null); do
    while subst "$f" '^([ \t]*listen[ \t]+)80([ \t;])' '\g<1>127.0.0.1:80\2'; do k=$((k + 1)); done
  done
  [ "$k" -gt 0 ] || exit 10
  nginx_recharger || exit 1
  journal "nginx : écoute limitée à 127.0.0.1:80 ($k ligne(s))"
else
  m="$(nginx -T 2>/dev/null | sed -nE 's/.*if[ \t]*\([ \t]*-f[ \t]+([^ \t)]+)[ \t]*\).*/\1/p' | head -n 1)"
  [ -n "$m" ] || exit 10
  [ -e "$m" ] && exit 10
  sauver "$m"
  printf 'maintenance RB-070 — %s\n' "$(date -I)" >"$m"
  noter_injecte "$m"
  journal "fichier de maintenance $m créé"
fi
exit 0
EOF
      done
      ;;
  esac
  if ((rc != 0)); then
    _e39_defaire
    return "$rc"
  fi
  if ! m07_attendre 30 _e39_casse; then
    m07_journal E39 "variante $n posée mais aucun backend n'est entièrement DOWN"
    _e39_defaire
    return 10
  fi
}

_e39_defaire() {
  m07_annuler_hote hap01 haproxy
  m07_annuler_hote srv01 nginx
  m07_annuler_hote srv02 nginx
}

_e39_injecter() {
  _e39_precondition || return 1
  m07_essayer E39 4 "$1"
}

panne_E39_v1() { _e39_injecter 1; }
panne_E39_v2() { _e39_injecter 2; }
panne_E39_v3() { _e39_injecter 3; }
panne_E39_v4() { _e39_injecter 4; }

verifier_E39() { _e39_casse; }

annuler_E39() { _e39_defaire; }

resume_E39() {
  echo "Le service publié par hap01 répond « 503 Service Unavailable » à toutes les requêtes."
}

symptome_E39() {
  wb_symptome "Ticket INC-3405 — De : Julien Petit" \
    "La démo de répartition (hap01) répond « 503 Service Unavailable » à toutes les requêtes." \
    "Pourtant srv01 et srv02 sont allumés et je peux m'y connecter en SSH. Lucas dit qu'il a" \
    "« juste préparé un truc » sur la maquette, InfoGér a « durci » des serveurs : à toi de voir." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 07 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 07 E39 4 "$@"; }
fi
