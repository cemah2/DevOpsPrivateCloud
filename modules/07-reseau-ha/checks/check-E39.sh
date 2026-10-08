# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E39.sh — M07-E39 « Panne : 503 Service Unavailable » : HAProxy de hap01 et ses serveurs
# sains, contrôles de santé au vert. Lecture seule (socket d'administration interrogée en « show stat »).

# shellcheck source=_m07-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-expert.sh"

title "M07-E39 — Répartiteur de démonstration hap01"
require_cmd ssh jq

check_cmd "hap01 : haproxy actif, configuration valide (haproxy -c)" _m07x_ok hap01 \
  'systemctl is-active -q haproxy && haproxy -c -q -f /etc/haproxy/haproxy.cfg'
check_output "hap01 : tous les serveurs des backends sont UP (socket d'administration)" '^tous-up$' \
  _m07x_sur hap01 '
s="$(sed -nE "s/^[ \t]*stats[ \t]+socket[ \t]+([^ \t]+).*/\1/p" /etc/haproxy/haproxy.cfg | head -n 1)"
python3 - "$s" <<"PY"
import csv, io, socket, sys
c = socket.socket(socket.AF_UNIX); c.settimeout(5); c.connect(sys.argv[1]); c.sendall(b"show stat\n")
d = b""
while True:
    b = c.recv(65536)
    if not b:
        break
    d += b
st = [r.get("status", "") for r in csv.DictReader(io.StringIO(d.decode().lstrip("# ")))
      if r.get("svname") not in ("FRONTEND", "BACKEND") and r.get("check_status")]
print("tous-up" if st and all(s.startswith("UP") for s in st) else "non")
PY'
if _m07x_ok hap01 "grep -Eq '^[[:space:]]*bind[[:space:]]+(\*|0\.0\.0\.0)?:80([[:space:]]|\$)' /etc/haproxy/haproxy.cfg"; then
  check_output "hap01 : le frontend HTTP répond 200" '^200$' \
    _m07x_sur hap01 "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1/"
else
  skip "frontend HTTP de hap01" "pas de bind :80 (version TLS de M07-E11)"
fi
for _m07_e39_h in srv01 srv02; do
  check_cmd "$_m07_e39_h : Nginx écoute sur le port 80 d'une adresse joignable (pas seulement 127.0.0.1)" \
    _m07x_ok "$_m07_e39_h" "ss -Htln 'sport = :80' | awk '{ print \$4 }' | grep -qvE '^(127\.|\[::1\])'"
  check_cmd "$_m07_e39_h : point de santé /sante en 200 (pas de fichier de maintenance oublié)" \
    _m07x_ok "$_m07_e39_h" '[ "$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1/sante)" = 200 ]'
done
check_cmd "panne M07-E39 close (lab/bin/break 07 39 --annuler après réparation)" _m07x_aucune_panne_active E39
