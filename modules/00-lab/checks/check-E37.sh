# shellcheck shell=bash
# Vérification M00-E37 — Exercice de restauration chronométré (lancé depuis adm01).

title "M00-E37 — Exercice de restauration chronométré"
require_cmd ssh dig

# VM active parmi 1002 et 5091 (exécuté sur pve01) : affiche son VMID, ou rien
# shellcheck disable=SC2016  # variables développées sur l'hôte distant
ACTIVE='for v in 1002 5091; do qm status $v 2>/dev/null | grep -q "status: running" && echo $v; done'
# shellcheck disable=SC2016
COHERENT='a=$('"$ACTIVE"'); [ "$(echo "$a" | grep -c .)" -eq 1 ] || exit 1; qm config $a --current | grep -q "^onboot: 1" || exit 1; for v in 1002 5091; do [ "$v" = "$a" ] && continue; qm status $v >/dev/null 2>&1 || continue; qm config $v --current | grep -q "^onboot: 1" && exit 1; done; exit 0'
# shellcheck disable=SC2016
POOL='a=$('"$ACTIVE"'); [ -n "$a" ] && pvesh get /cluster/resources --type vm --output-format json | VMID="$a" perl -MJSON::PP -0777 -ne '"'"'my $id = $ENV{VMID}; exit((grep { $_->{vmid} == $id && ($_->{pool} // "") eq "lab" } @{decode_json($_)}) ? 0 : 1)'"'"''

check_ssh_output "une restauration vers le VMID 5091 a réussi" "$WB_PVE_HOST" '"status" *: *"OK"' \
  "pvesh get /nodes/\$(hostname)/tasks --typefilter qmrestore --vmid 5091 --source all --limit 1000 --output-format json"
check_ssh "exactement une VM dns01 (1002 ou 5091) est en marche, seule à démarrer automatiquement" \
  "$WB_PVE_HOST" "$COHERENT"
check_ssh "la VM dns01 active appartient au pool lab" "$WB_PVE_HOST" "$POOL"

check_ping "10.10.20.10 répond au ping" 10.10.20.10
check_dns "dns01 résout la zone interne" adm01.par1.medisphere.internal A '^10\.10\.10\.10$' 10.10.20.10
check_dns "dns01 résout la zone inverse" 10.10.10.10.in-addr.arpa PTR 'adm01\.par1\.medisphere\.internal\.?$' 10.10.20.10
check_dns "dns01 résout un nom Internet" debian.org A '^[0-9.]+$' 10.10.20.10
check_ssh_output "le dnsmasq de la VM active écoute sur le port 53" dns01 ':53 ' "sudo -n ss -lnup"
