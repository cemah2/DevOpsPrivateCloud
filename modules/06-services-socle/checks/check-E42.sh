# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E42.sh — M06-E42 « Panne : les baux n'apparaissent plus dans le DNS » : chaîne DDNS saine
# (kea-dhcp4 → kea-dhcp-ddns → PowerDNS), sans écrire dans la zone : on compare les réglages des deux
# côtés et on vérifie que les baux actifs nommés sont dans le DNS. Lecture seule.

# shellcheck source=_m06-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-expert.sh"

title "M06-E42 — Mise à jour dynamique du DNS par Kea"
require_cmd ssh

check_ssh "dns01 : kea-dhcp-ddns actif et activé" dns01 \
  "$_m06x_d2"'; [ -n "$d" ] && systemctl is-active -q "$d" && systemctl is-enabled -q "$d"'
check_ssh "dns01 : kea-dhcp4 transmet les demandes à kea-dhcp-ddns (enable-updates)" dns01 \
  'sudo -n grep -Eq "\"enable-updates\"[[:space:]]*:[[:space:]]*true" /etc/kea/kea-dhcp4.conf'
check_ssh "dns01 : PowerDNS accepte les mises à jour RFC 2136 (dnsupdate=yes effectif)" dns01 \
  'v=$(sudo -n sh -c "grep -hE \"^[[:space:]]*dnsupdate[[:space:]]*=\" /etc/powerdns/pdns.conf /etc/powerdns/pdns.d/*.conf 2>/dev/null" | tail -n 1 | cut -d= -f2 | tr -d " "); [ "$v" = yes ]'
# La clé (nom, secret) déclarée dans kea-dhcp-ddns existe dans PowerDNS avec le même secret, et la
# zone l'autorise. Les secrets ne sortent pas de dns01 : seul le résultat de la comparaison revient.
check_ssh "dns01 : même clé TSIG des deux côtés, autorisée sur la zone $_m06x_zone" dns01 '
  sudo -n python3 - '"$_m06x_zone"' <<'"'PY'"'
import json, re, subprocess, sys
t = open("/etc/kea/kea-dhcp-ddns.conf", encoding="utf-8").read()
t = re.sub(r"(\"(?:\\.|[^\"\\])*\")|//[^\n]*|#[^\n]*|/\*.*?\*/", lambda m: m.group(1) or "", t, flags=re.S)
k = json.loads(t)["DhcpDdns"]["tsig-keys"][0]
nom = k["name"].rstrip(".")
sec = k.get("secret") or open(k["secret-file"], encoding="utf-8").read().strip()
pdns = ["runuser", "-u", "pdns", "--", "pdnsutil"]  # comme le rôle : jamais pdnsutil en root sur la base
cles = subprocess.run(pdns + ["tsigkey", "list"], capture_output=True, text=True).stdout.splitlines()
ok = any(l.split()[0].rstrip(".") == nom and l.split()[-1] == sec for l in cles if len(l.split()) >= 3)
m = subprocess.run(pdns + ["metadata", "get", sys.argv[1], "TSIG-ALLOW-DNSUPDATE"], capture_output=True, text=True).stdout
autorise = (not re.search(r"=\s*\S", m)) or re.search(r"(^|[\s=,])%s\.?(\s|,|$)" % re.escape(nom), m)
sys.exit(0 if ok and autorise else 1)
PY'
# Dernière ligne de chaque adresse dans le fichier de baux (memfile ajoute les mises à jour en fin
# de fichier) : bail non expiré, état 0 (actif), fqdn_fwd à 1, nom présent → l'adresse est dans le DNS.
check_ssh "dns01 : chaque bail actif nommé (fqdn_fwd) est dans le DNS" dns01 '
  f=/var/lib/kea/kea-leases4.csv; sudo -n test -f "$f" || exit 0
  sudo -n awk -F, -v n="$(date +%s)" "NR > 1 { l[\$1] = \$0 } END { for (a in l) { split(l[a], c, \",\"); if (c[5] > n && c[7] == 1 && c[9] != \"\" && c[10] == 0) print c[1], c[9] } }" "$f" \
    | while read -r ip nom; do dig +short @127.0.0.1 -p 5300 "$nom" A | grep -qx "$ip" || exit 1; done'
check_cmd "panne M06-E42 close (lab/bin/break 06 42 --annuler après réparation)" _m06x_aucune_panne_active E42
