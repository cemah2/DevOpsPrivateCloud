# shellcheck shell=bash
# M00-E12 — Déployer adm01 et dns01 depuis le template.
# Lecture seule. Configuration lue sur pve01 (WB_PVE_HOST) ; contrôles internes via les
# alias SSH « adm01 » et « dns01 » (utilisateur admin, sudo -n).

title "M00-E12 — Déployer adm01 et dns01 depuis le template"

_m00_vm() {
  printf "pvesh get /cluster/resources --type vm --output-format json | perl -MJSON::PP -0777 -ne 'exit(!grep { \$_->{vmid} == %d && (\$_->{%s} // q{}) eq q{%s} } @{decode_json(\$_)})'" "$1" "$2" "$3"
}

# vmid nom vlan vnet(après E28) ip passerelle cœurs mémoire taille_min_racine(octets)
for spec in "1001 adm01 10 vmgmt 10.10.10.10 10.10.10.1 2 2048 15000000000" \
            "1002 dns01 20 vinfra 10.10.20.10 10.10.20.1 1 1024 6000000000"; do
  read -r id nom vlan vnet ip gw cores mem racine <<<"$spec"
  ipre="${ip//./\\.}"; gwre="${gw//./\\.}"

  check_ssh "la VM $id s'appelle $nom" "$WB_PVE_HOST" "$(_m00_vm "$id" name "$nom")"
  check_ssh "$nom est dans le pool lab" "$WB_PVE_HOST" "$(_m00_vm "$id" pool lab)"
  check_ssh "$nom est démarrée" "$WB_PVE_HOST" "$(_m00_vm "$id" status running)"
  check_ssh_output "$nom démarre avec pve01 (onboot)" "$WB_PVE_HOST" '^onboot: 1' "qm config $id"
  check_ssh "$nom est un clone complet (aucune dépendance au template)" "$WB_PVE_HOST" \
    "qm config $id | grep -E '^scsi0: ' | grep -vq 'base-9000'"
  check_ssh_output "$nom a l'étiquette socle" "$WB_PVE_HOST" '^tags: (.*;)?socle(;|$)' "qm config $id"
  check_ssh_output "$nom : $cores vCPU" "$WB_PVE_HOST" "^cores: $cores\$" "qm config $id"
  check_ssh_output "$nom : $mem Mo de RAM" "$WB_PVE_HOST" "^memory: $mem\$" "qm config $id"
  # Après M00-E28, la carte est sur le VNet correspondant, sans tag.
  check_ssh "$nom : net0 sur vmbr1 avec tag=$vlan (ou sur le VNet $vnet après E28)" "$WB_PVE_HOST" \
    "n=\$(qm config $id | grep -E '^net0: '); echo \"\$n\" | grep -Eq 'bridge=$vnet(,|\$)' || { echo \"\$n\" | grep -E 'bridge=vmbr1(,|\$)' | grep -Eq 'tag=$vlan(,|\$)'; }"
  check_ssh "$nom : ipconfig0 = $ip/24, passerelle $gw" "$WB_PVE_HOST" \
    "qm config $id | grep -E '^ipconfig0: ' | grep -E 'ip=$ipre/24(,|\$)' | grep -Eq 'gw=$gwre(,|\$)'"
  check_ssh_output "$nom : domaine de recherche par1.medisphere.internal" "$WB_PVE_HOST" \
    '^searchdomain: par1\.medisphere\.internal$' "qm config $id"
  check_ssh "$nom : l'agent QEMU répond" "$WB_PVE_HOST" "qm guest cmd $id ping"

  if remote "$nom" true >/dev/null 2>&1; then
    check_ssh "connexion SSH à $nom (alias $nom)" "$nom" true
    check_ssh "$nom : sudo sans mot de passe pour admin" "$nom" "sudo -n true"
    check_ssh_output "$nom : nom complet $nom.par1.medisphere.internal" "$nom" \
      "^$nom\.par1\.medisphere\.internal\$" "hostname -f"
    check_ssh_output "$nom : cloud-init a terminé" "$nom" 'status: done' "cloud-init status"
    check_ssh "$nom : service qemu-guest-agent actif" "$nom" "systemctl is-active --quiet qemu-guest-agent"
    check_ssh "$nom : système de fichiers racine agrandi" "$nom" \
      "test \"\$(findmnt -bno SIZE /)\" -gt $racine"
    check_ssh "$nom : passerelle $gw joignable" "$nom" "ping -c 2 -W 2 $gw"
    check_ssh "$nom : Internet joignable (deb.debian.org, TCP 443)" "$nom" \
      "timeout 5 bash -c '</dev/tcp/deb.debian.org/443'"
  else
    check_ssh "connexion SSH à $nom (alias $nom)" "$nom" true
    skip "contrôles internes à $nom" "connexion SSH impossible"
  fi
done

# --- Filtrage inter-VLAN par gw01 ---------------------------------------------------
if remote adm01 true >/dev/null 2>&1 && remote dns01 true >/dev/null 2>&1; then
  check_ssh "adm01 (MGMT) joint dns01 (INFRA)" adm01 "ping -c 2 -W 2 10.10.20.10"
  check_ssh "dns01 (INFRA) ne peut pas initier de connexion vers adm01 (MGMT)" dns01 \
    "! ping -c 2 -W 2 10.10.10.10"
else
  skip "filtrage inter-VLAN MGMT/INFRA" "adm01 ou dns01 injoignable en SSH"
fi
