# shellcheck shell=bash
# M00-E08 — Pool, utilisateurs, groupes et rôles.
# Lecture seule. Les contrôles s'exécutent sur pve01 (WB_PVE_HOST).

title "M00-E08 — Pool, utilisateurs, groupes et rôles"

NVME="${WB_STORAGE_NVME:-local-nvme}"
SSD="${WB_STORAGE_SSD:-ssd-lab}"
BULK="${WB_STORAGE_BULK:-hdd-bulk}"

# Commande distante : code 0 si l'ACL (chemin, utilisateur/groupe, rôle) existe
_m00_acl() {
  printf "pvesh get /access/acl --output-format json | perl -MJSON::PP -0777 -ne 'exit(!grep { \$_->{path} eq q{%s} && \$_->{ugid} eq q{%s} && \$_->{roleid} eq q{%s} } @{decode_json(\$_)})'" "$1" "$2" "$3"
}

check_ssh "le pool lab existe" "$WB_PVE_HOST" \
  "pvesh get /pools --output-format json | perl -MJSON::PP -0777 -ne 'exit(!grep { \$_->{poolid} eq q{lab} } @{decode_json(\$_)})'"
check_ssh "le groupe wb-admins existe" "$WB_PVE_HOST" \
  "pvesh get /access/groups --output-format json | perl -MJSON::PP -0777 -ne 'exit(!grep { \$_->{groupid} eq q{wb-admins} } @{decode_json(\$_)})'"
check_ssh "l'utilisateur wb-admin@pve existe et est actif" "$WB_PVE_HOST" \
  "pvesh get /access/users --output-format json | perl -MJSON::PP -0777 -ne 'exit(!grep { \$_->{userid} eq q{wb-admin@pve} && (\$_->{enable} // 1) } @{decode_json(\$_)})'"
check_ssh "wb-admin@pve est membre de wb-admins" "$WB_PVE_HOST" \
  "pvesh get /access/groups/wb-admins --output-format json | perl -MJSON::PP -0777 -ne 'exit(!grep { \$_ eq q{wb-admin@pve} } @{decode_json(\$_)->{members} // []})'"

check_ssh "wb-admins a le rôle PVEAdmin sur /pool/lab" "$WB_PVE_HOST" "$(_m00_acl /pool/lab wb-admins PVEAdmin)"
for st in "$NVME" "$SSD" "$BULK"; do
  check_ssh "wb-admins a le rôle PVEDatastoreUser sur /storage/$st" "$WB_PVE_HOST" \
    "$(_m00_acl "/storage/$st" wb-admins PVEDatastoreUser)"
done

check_ssh "aucune ACL sur / pour wb-admins ou wb-admin@pve" "$WB_PVE_HOST" \
  "pvesh get /access/acl --output-format json | perl -MJSON::PP -0777 -ne 'exit(scalar grep { \$_->{path} eq q{/} && (\$_->{ugid} eq q{wb-admins} || \$_->{ugid} eq q{wb-admin@pve}) } @{decode_json(\$_)})'"
check_ssh_output "droit effectif VM.Allocate de wb-admin@pve sur /pool/lab" "$WB_PVE_HOST" \
  '"VM\.Allocate"' "pvesh get /access/permissions --userid wb-admin@pve --path /pool/lab --output-format json"
check_ssh "aucun privilège système (Sys.Modify, Permissions.Modify) pour wb-admin@pve sur /" "$WB_PVE_HOST" \
  "! pvesh get /access/permissions --userid wb-admin@pve --path / --output-format json | grep -Eq 'Sys\.Modify|Permissions\.Modify|Sys\.PowerMgmt'"
