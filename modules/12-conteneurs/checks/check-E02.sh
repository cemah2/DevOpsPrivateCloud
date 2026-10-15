# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E02.sh — M12-E02 : Préparer les hôtes de conteneurs
# À lancer depuis adm01. Lecture seule : qm config sur pve01, DNS, NetBox (jeton des checks),
# état des hôtes en SSH (admin, sudo -n pour lire ce qui appartient à app), API GitLab en GET.

# shellcheck source=_m12-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-decouverte.sh"

title "M12-E02 — Préparer les hôtes de conteneurs"
require_cmd jq dig curl

# _m12d_e02_netbox NOM — la VM existe dans NetBox, active, avec l'étiquette env-m12.
_m12d_e02_netbox() {
  netbox_api "virtualization/virtual-machines/?name=$1" 2>/dev/null \
    | jq -e '.count == 1 and .results[0].status.value == "active" and ([.results[0].tags[].slug] | index("env-m12") != null)' >/dev/null
}

# --- 1. Les VMs (Proxmox), le nom, NetBox ---------------------------------------------------------
for _m12d_e02_def in ctr01:1:debian13:docker ctr02:2:debian13:podman ctr03:3:rocky10:podman legacy01:4:debian13:legacy; do
  IFS=: read -r _m12d_e02_nom _m12d_e02_n _m12d_e02_famille _m12d_e02_role <<<"$_m12d_e02_def"
  _m12d_e02_vmid="212${_m12d_e02_n}"
  _m12d_e02_conf="$(_m12d_qm "$_m12d_e02_vmid")"

  check_cmd "VM $_m12d_e02_vmid nommée $_m12d_e02_nom" _m12d_correspond "$_m12d_e02_conf" "^name: ${_m12d_e02_nom}$"
  check_cmd "$_m12d_e02_nom : étiquettes env-m12 et role-$_m12d_e02_role" \
    _m12d_etiquettes "$_m12d_e02_conf" env-m12 "role-$_m12d_e02_role"
  check_cmd "$_m12d_e02_nom : membre du pool lab" _m12d_dans_pool "$_m12d_e02_vmid"
  check_cmd "$_m12d_e02_nom : créée par OpenTofu avec le module vm-noeud" _m12d_correspond "$_m12d_e02_conf" 'vm-noeud'
  check_cmd "$_m12d_e02_nom : 2 vCPU, 2048 Mo, disque système de 32 Gio" \
    bash -c 'grep -q "^cores: 2$" <<<"$1" && grep -q "^memory: 2048$" <<<"$1" && grep -Eq "^scsi0: .*size=32G" <<<"$1"' _ "$_m12d_e02_conf"
  check_cmd "$_m12d_e02_nom : une carte sur vsandbox, MAC bc:24:11:99:12:0$_m12d_e02_n" \
    bash -c 'grep -Eiq "^net0: virtio=BC:24:11:99:12:0$2,.*bridge=vsandbox" <<<"$1" && ! grep -q "^net1:" <<<"$1"' _ "$_m12d_e02_conf" "$_m12d_e02_n"
  check_cmd "$_m12d_e02_nom : adresse par DHCP (ipconfig0)" _m12d_correspond "$_m12d_e02_conf" '^ipconfig0: ip=dhcp'
  if [[ "$_m12d_e02_famille" == rocky10 ]]; then
    check_cmd "$_m12d_e02_nom : CPU x86-64-v3 ou host (exigé par Rocky Linux 10)" \
      _m12d_correspond "$_m12d_e02_conf" '^cpu: (x86-64-v3|host)'
  fi
  check_dns "DNS (DDNS de Kea) : $(_m12d_fqdn "$_m12d_e02_nom") dans la plage dynamique de vsandbox" \
    "$(_m12d_fqdn "$_m12d_e02_nom")" A '^10\.10\.99\.1[0-9][0-9]$' "$_M12D_DNS"
  check_cmd "NetBox : $_m12d_e02_nom active, étiquette env-m12" _m12d_e02_netbox "$_m12d_e02_nom"

  if [[ "$_m12d_e02_famille" == rocky10 ]]; then
    check_ssh_output "$_m12d_e02_nom : Rocky Linux 10" "$_m12d_e02_nom" '^rocky 10' '. /etc/os-release; echo "$ID ${VERSION_ID%%.*}"'
  else
    check_ssh_output "$_m12d_e02_nom : Debian 13" "$_m12d_e02_nom" '^debian 13$' '. /etc/os-release; echo "$ID $VERSION_ID"'
  fi
done

# --- 2. ctr01 : Docker Engine ---------------------------------------------------------------------
check_ssh_output "ctr01 : démon Docker 29.8" ctr01 '^29\.8\.' 'docker version --format "{{.Server.Version}}"'
check_ssh_output "ctr01 : containerd.io 2.3 (LTS), Compose 5.6, Buildx 0.37 (paquets du dépôt Docker)" ctr01 \
  '^2\.3\.[^ ]+ 5\.6\.[^ ]+ 0\.37\.[^ ]+$' \
  'dpkg-query -W -f "\${Version} " containerd.io docker-compose-plugin docker-buildx-plugin | sed "s/ $//"'
check_ssh_output "ctr01 : stockage d'images containerd (snapshotter)" ctr01 'io\.containerd\.snapshotter\.v1' \
  'docker info --format "{{json .DriverStatus}}"'
check_ssh "ctr01 : paquet docker.io de Debian absent" ctr01 \
  '! dpkg-query -W -f "\${Status}" docker.io 2>/dev/null | grep -q "install ok installed"'
check_ssh "ctr01 : dépôt download.docker.com limité à une clé (Signed-By)" ctr01 \
  'f=$(grep -rlE "download\.docker\.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null); [ -n "$f" ] && for x in $f; do grep -Eq "(Signed-By:|signed-by=)" "$x" || exit 1; done'
check_ssh "ctr01 : clé du dépôt Docker = empreinte officielle" ctr01 \
  'f=$(grep -rlE "download\.docker\.com" /etc/apt/sources.list.d/ 2>/dev/null | head -1); [ -n "$f" ] && k=$(grep -oE "(Signed-By: *|signed-by=)[^] ]+" "$f" | head -1 | sed -E "s/(Signed-By: *|signed-by=)//") && [ -n "$k" ] && gpg --show-keys --with-colons "$k" 2>/dev/null | grep -q "^fpr:::::::::9DC858229FC7DD38854AE2D88D81803C0EBFCD88:"'
check_ssh "ctr01 : versions de Docker épinglées (préférence APT ou paquet retenu)" ctr01 \
  'LC_ALL=C apt-cache policy docker-ce | grep -Eq "^ +\*\*\* .* (99[0-9]|[1-9][0-9]{3,})$" || apt-mark showhold | grep -qx docker-ce'
check_ssh "ctr01 : daemon.json avec rotation des journaux et réseaux dans 172.20.0.0/14" ctr01 \
  'python3 -c "import json,sys; d=json.load(open(\"/etc/docker/daemon.json\")); o=d.get(\"log-opts\",{}); p=d.get(\"default-address-pools\",[]); sys.exit(0 if o.get(\"max-size\") and o.get(\"max-file\") and p and p[0].get(\"base\")==\"172.20.0.0/14\" else 1)"'
check_ssh "ctr01 : admin dans le groupe docker" ctr01 'id -nG admin | grep -qw docker'

# --- 3. ctr02 et ctr03 : Podman sans privilège -----------------------------------------------------
for _m12d_e02_def in ctr02:5.4 ctr03:5.8; do
  IFS=: read -r _m12d_e02_h _m12d_e02_v <<<"$_m12d_e02_def"
  check_ssh_output "$_m12d_e02_h : Podman $_m12d_e02_v" "$_m12d_e02_h" "^podman version ${_m12d_e02_v//./\\.}\." 'podman --version'
  check_ssh "$_m12d_e02_h : Buildah, Skopeo, pasta installés" "$_m12d_e02_h" 'command -v buildah && command -v skopeo && command -v pasta'
  check_ssh "$_m12d_e02_h : compte app d'UID $_M12D_APP_UID, sans sudo ni groupe privilégié" "$_m12d_e02_h" \
    "[ \"\$(id -u $_M12D_APP)\" = $_M12D_APP_UID ] && ! id -nG $_M12D_APP | grep -Eqw 'sudo|wheel|docker|adm' && LC_ALL=C sudo -n -l -U $_M12D_APP 2>&1 | grep -q 'not allowed to run sudo'"
  check_ssh "$_m12d_e02_h : plage subordonnée $_M12D_SUBID_DEBUT:$_M12D_SUBID_NOMBRE (subuid et subgid)" "$_m12d_e02_h" \
    "grep -qx '$_M12D_APP:$_M12D_SUBID_DEBUT:$_M12D_SUBID_NOMBRE' /etc/subuid && grep -qx '$_M12D_APP:$_M12D_SUBID_DEBUT:$_M12D_SUBID_NOMBRE' /etc/subgid"
  check_ssh_output "$_m12d_e02_h : linger actif pour app" "$_m12d_e02_h" '^Linger=yes$' "loginctl show-user $_M12D_APP -p Linger"
  check_ssh "$_m12d_e02_h : registres complétés (short-name-mode enforcing)" "$_m12d_e02_h" \
    'grep -hqsE "^ *short-name-mode *= *\"enforcing\"" /etc/containers/registries.conf.d/*.conf'
  check_output "$_m12d_e02_h : Podman de app sans privilège, réseau pasta, cgroup v2" '^true pasta v2$' \
    _m12d_podman "$_m12d_e02_h" "info --format '{{.Host.Security.Rootless}} {{.Host.RootlessNetworkCmd}} {{.Host.CgroupsVersion}}'"
done
check_ssh_output "ctr02 : Buildah 1.39 et Skopeo 1.18 (Debian 13)" ctr02 '^buildah version 1\.39\..*skopeo version 1\.18\.' \
  'echo "$(buildah --version) $(skopeo --version)"'
check_ssh_output "ctr03 : SELinux en enforcing" ctr03 '^Enforcing$' 'getenforce'

# --- 4. legacy01 : Legacy-RDV à l'ancienne ---------------------------------------------------------
check_ssh "legacy01 : Apache et MariaDB actifs" legacy01 'systemctl is-active --quiet apache2 && systemctl is-active --quiet mariadb'
check_ssh_output "legacy01 : PHP 8.4 (mod_php)" legacy01 '^PHP 8\.4\.' 'php -v | head -1'
check_ssh "legacy01 : code dans /var/www/legacy-rdv, hôte virtuel et cron d'InfoGér en place" legacy01 \
  'test -s /var/www/legacy-rdv/config.php && test -e /etc/apache2/sites-enabled/legacy-rdv.conf && test -s /etc/cron.d/legacy-rdv && [ "$(stat -c %U /var/www/legacy-rdv/uploads)" = www-data ]'
check_output "legacy01 : Legacy-RDV répond depuis adm01 et lit sa base" 'MédiSphère RDV' \
  _m12d_http "http://$(_m12d_fqdn legacy01)/"
check_output "legacy01 : pas de page d'erreur de connexion à la base" '^ok$' \
  bash -c 'c=$(curl -s --max-time 5 "$1"); [[ -n "$c" ]] && ! grep -q "indisponible" <<<"$c" && echo ok' _ "http://$(_m12d_fqdn legacy01)/"

# --- 5. Le code ------------------------------------------------------------------------------------
check_output "plateforme/tofu-modules (main) : vm-noeud accepte une carte en DHCP" '"dhcp"' \
  _m12d_contenu_main plateforme/tofu-modules vm-noeud/variables.tf
check_output "plateforme/infra (main) : environnement envs/m12 (fichiers .tf)" '^envs/m12/[^/]+\.tf$' \
  _m12d_arbre_main plateforme/infra envs/m12
for _m12d_e02_f in roles/docker_engine/tasks/main.yml roles/podman_hote/tasks/main.yml roles/legacy_rdv/tasks/main.yml \
  inventories/lab/netbox-m12.yml playbooks/conteneurs.yml playbooks/legacy-rdv.yml \
  molecule/docker_engine/molecule.yml molecule/podman_hote/molecule.yml; do
  check_cmd "plateforme/ansible (main) : $_m12d_e02_f" _m12d_fichier_main plateforme/ansible "$_m12d_e02_f"
done
check_output "plateforme/ansible (main) : mot de passe de Legacy-RDV chiffré (Vault)" '^\$ANSIBLE_VAULT;1\.[12];AES256' \
  _m12d_contenu_main plateforme/ansible inventories/lab/group_vars/role_legacy/vault.yml
check_cmd "plateforme/medisphere (main) : docs/conteneurs/hotes.md" _m12d_fichier_main plateforme/medisphere docs/conteneurs/hotes.md
