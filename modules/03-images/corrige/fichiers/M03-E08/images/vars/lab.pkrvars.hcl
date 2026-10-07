# vars/lab.pkrvars.hcl — valeurs NON SECRÈTES de l'environnement « lab » (M03-E05, M03-E08).
# Versionné. Le nœud (proxmox_node), l'URL et le jeton viennent de l'environnement
# (PKR_VAR_*, ~/.config/workbook/pve-packer.env ou variables CI) : le nœud dépend de
# l'installation (<NOEUD>), le jeton est un secret.
# Attention à la précédence : une valeur posée ici l'emporte sur PKR_VAR_<nom>.
pool          = "lab"
storage_vm    = "local-nvme"
storage_iso   = "hdd-bulk"
build_bridge  = "vsandbox"
http_port_min = 8100
http_port_max = 8199
