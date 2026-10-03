# shellcheck shell=bash
# Vérification M00-E36 — Chiffrer les sauvegardes côté client (lancé depuis adm01).

title "M00-E36 — Chiffrer les sauvegardes côté client"
require_cmd ssh

CLE=/etc/pve/priv/storage/pbs-par2.enc

# Extraction d'un paramètre du stockage pbs-par2 dans storage.cfg (exécuté sur pve01)
# shellcheck disable=SC2016  # variables développées sur l'hôte distant
PARAM='awk -v k="$1" '"'"'$0 == "pbs: pbs-par2" {f=1; next} /^[a-z]+: / {f=0} f && $1 == k {print $2; exit}'"'"' /etc/pve/storage.cfg'

# Sauvegarde de VM chiffrée de moins de 48 h
# shellcheck disable=SC2016
VM_CHIFFREE='pvesh get /nodes/$(hostname)/storage/pbs-par2/content --content backup --output-format json | perl -MJSON::PP -0777 -ne '"'"'my $d = decode_json($_); my $n = grep { $_->{encrypted} && $_->{ctime} > time() - 172800 } @$d; exit($n ? 0 : 1)'"'"

# Dernier instantané host/<nœud> chiffré (lecture via les identifiants du stockage pbs-par2)
# shellcheck disable=SC2016
HOTE_CHIFFRE='p() { '"$PARAM"'; }; export PBS_REPOSITORY="$(p username)@$(p server):$(p datastore)" PBS_FINGERPRINT="$(p fingerprint)" PBS_PASSWORD="$(head -n 1 /etc/pve/priv/storage/pbs-par2.pw)"; ns="$(p namespace)"; proxmox-backup-client snapshot list "host/$(hostname)" --ns "${ns:-par1}" --output-format json | perl -MJSON::PP -0777 -ne '"'"'my @s = sort { $b->{"backup-time"} <=> $a->{"backup-time"} } @{decode_json($_)}; exit 1 unless @s; my @f = grep { $_->{filename} =~ /\.pxar\.didx$/ } @{$s[0]{files}}; exit((@f && !grep { ($_->{"crypt-mode"} // "") ne "encrypt" } @f) ? 0 : 1)'"'"

check_ssh "le stockage pbs-par2 dispose d'une clé de chiffrement" "$WB_PVE_HOST" "test -s $CLE"
check_ssh "la clé de chiffrement n'est lisible que par root" "$WB_PVE_HOST" \
  "[ \"\$(stat -c %U $CLE)\" = root ] && ! stat -c %A $CLE | grep -q '^.......r'"
check_ssh "une sauvegarde de VM chiffrée de moins de 48 h existe sur pbs-par2" "$WB_PVE_HOST" "$VM_CHIFFREE"
check_ssh "le dernier instantané de configuration de l'hôte est chiffré" "$WB_PVE_HOST" "$HOTE_CHIFFRE"
check_ssh_output "une restauration vers le VMID 5092 a réussi" "$WB_PVE_HOST" '"status" *: *"OK"' \
  "pvesh get /nodes/\$(hostname)/tasks --typefilter qmrestore --vmid 5092 --source all --limit 1000 --output-format json"
check_ssh "la VM de test 5092 a été supprimée" "$WB_PVE_HOST" "! qm status 5092 >/dev/null 2>&1"
check_ssh "la clé de chiffrement n'est pas présente sur pbs01" "$WB_PBS_HOST" \
  "! find /etc /root -xdev -name 'pbs-par2.enc' 2>/dev/null | grep -q ."
