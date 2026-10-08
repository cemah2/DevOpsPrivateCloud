# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes : évaluées par bash -c, en-têtes « $ANSIBLE_VAULT » littéraux
#
# check-E03.sh — M10-E03 : Préparer Kolla-Ansible
# À lancer depuis adm01. Lecture seule : copie de travail ~/src/openstack (git, uv, fichiers),
# environnement uv des deux projets (versions), API GitLab en GET. Ne déchiffre rien.

# shellcheck source=_m10-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-decouverte.sh"

title "M10-E03 — Préparer Kolla-Ansible"
require_cmd git uv jq

_m10d_e03_g="$_M10D_OS/etc/kolla/globals.yml"

# --- 1. Le projet et ses deux environnements --------------------------------------------------
check_output "Copie de travail src/openstack : clone de plateforme/openstack" 'plateforme/openstack(\.git)?$' \
  git -C "$_M10D_OS" remote get-url origin
check_cmd "pyproject.toml : kolla-ansible figé en 22.x" \
  grep -Eq '"kolla-ansible==22\.[0-9]+(\.[0-9]+|\.\*)?"' "$_M10D_OS/pyproject.toml"
check_cmd "uv.lock versionné" bash -c 'git -C "$1" ls-files --error-unmatch uv.lock >/dev/null 2>&1' _ "$_M10D_OS"
_m10d_e03_vk="$(cd "$_M10D_OS" 2>/dev/null && uv run --quiet --frozen python -c 'from importlib.metadata import version; print(version("kolla-ansible"))' 2>/dev/null || true)"
check_cmd "Environnement du projet : kolla-ansible 22.x installé" grep -Eq '^22\.' <<<"$_m10d_e03_vk"
check_output "Environnement du projet : ansible-core 2.20.x" 'core 2\.20\.' \
  bash -c 'cd "$1" && uv run --quiet --frozen ansible --version' _ "$_M10D_OS"
check_output "plateforme/ansible garde son propre ansible-core (2.21.x)" 'core 2\.21\.' \
  bash -c 'cd "$1" && uv run --quiet --frozen ansible --version' _ "$_M10D_ANSIBLE"

# --- 2. Collections dans le projet --------------------------------------------------------------
check_cmd "ansible.cfg du projet : collections dans ./collections" \
  grep -Eq '^[[:space:]]*collections_path[[:space:]]*=[[:space:]]*\.?/?collections[[:space:]]*$' "$_M10D_OS/ansible.cfg"
check_cmd "Collection openstack.kolla installée dans le projet" test -d "$_M10D_OS/collections/ansible_collections/openstack/kolla"
check_cmd "Collection openstack.cloud installée dans le projet" test -d "$_M10D_OS/collections/ansible_collections/openstack/cloud"
check_cmd "Aucune collection de Kolla dans ~/.ansible/collections (partagé avec plateforme/ansible)" \
  test ! -d "$HOME/.ansible/collections/ansible_collections/openstack/kolla"
check_cmd "ansible.cfg du projet : identité Vault « critique »" \
  grep -Eq '^[[:space:]]*vault_identity_list[[:space:]]*=.*critique@' "$_M10D_OS/ansible.cfg"

# --- 3. globals.yml --------------------------------------------------------------------------------
# _m10d_e03_cle CLE VALEUR — « cle: "valeur" » (guillemets facultatifs), non commentée.
_m10d_e03_cle() {
  grep -Eq "^$1:[[:space:]]*\"?$2\"?[[:space:]]*(#.*)?$" "$_m10d_e03_g"
}
check_cmd "globals.yml : images debian" _m10d_e03_cle kolla_base_distro debian
check_cmd "globals.yml : Neutron avec OVN" _m10d_e03_cle neutron_plugin_agent ovn
# _m10d_e03_cles CLE VALEUR [CLE VALEUR…] — toutes les paires sont présentes.
_m10d_e03_cles() {
  while (($# >= 2)); do _m10d_e03_cle "$1" "$2" || return 1; shift 2; done
}
check_cmd "globals.yml : VIP interne 10.10.50.200 et son nom" \
  _m10d_e03_cles kolla_internal_vip_address '10\.10\.50\.200' kolla_internal_fqdn 'openstack-int\.par1\.medisphere\.internal'
check_cmd "globals.yml : VIP externe 10.10.50.201 et son nom" \
  _m10d_e03_cles kolla_external_vip_address '10\.10\.50\.201' kolla_external_fqdn 'openstack\.par1\.medisphere\.internal'
check_cmd "globals.yml : keepalived en VRID 150" _m10d_e03_cle keepalived_virtual_router_id 150
check_cmd "globals.yml : interfaces ens18 (API), ens19 (tunnels), ens20 (stockage)" \
  _m10d_e03_cles network_interface ens18 tunnel_interface ens19 storage_interface ens20
check_cmd "globals.yml : PAS d'interface externe (valeur propre à osctl01)" \
  bash -c '[[ -s "$1" ]] && ! grep -Eq "^neutron_external_interface:" "$1"' _ "$_m10d_e03_g"
check_cmd "Inventaire : interface externe ens21 pour osctl01" \
  bash -c 'grep -rqsE "neutron_external_interface[:=][[:space:]]*\"?ens21\"?" "$1/inventaire"' _ "$_M10D_OS"

# --- 4. Inventaire -------------------------------------------------------------------------------
# _m10d_e03_groupe GROUPE HÔTE… — la section [GROUPE] de inventaire/multinode contient ces hôtes.
_m10d_e03_groupe() {
  local g="$1" h contenu
  shift
  contenu="$(awk -v g="[$g]" '$0 == g {dedans=1; next} /^\[/ {dedans=0} dedans {print $1}' "$_M10D_OS/inventaire/multinode" 2>/dev/null)"
  for h in "$@"; do grep -qx "$h" <<<"$contenu" || return 1; done
}
for _m10d_e03_gr in control network monitoring storage; do
  check_cmd "Inventaire : osctl01 dans [$_m10d_e03_gr]" _m10d_e03_groupe "$_m10d_e03_gr" osctl01
done
check_cmd "Inventaire : oscmp01 et oscmp02 dans [compute]" _m10d_e03_groupe compute oscmp01 oscmp02
_m10d_e03_pas_ctl() {
  [[ -s "$_M10D_OS/inventaire/multinode" ]] || return 1
  ! awk '$0 == "[control]" {d=1; next} /^\[/ {d=0} d {print $1}' "$_M10D_OS/inventaire/multinode" 2>/dev/null | grep -q '^oscmp'
}
check_cmd "Inventaire : les calculs ne sont pas contrôleurs" _m10d_e03_pas_ctl

# --- 5. Secrets ----------------------------------------------------------------------------------
check_cmd "passwords.yml chiffré sous l'identité « critique » (copie de travail)" \
  _m10d_vault_critique "$_M10D_OS/etc/kolla/passwords.yml"
_m10d_e03_main="$(gitlab_api "projects/plateforme%2Fopenstack/repository/files/etc%2Fkolla%2Fpasswords.yml/raw?ref=main" 2>/dev/null | head -n 1 || true)"
check_cmd "passwords.yml chiffré sur main (GitLab)" grep -q '^\$ANSIBLE_VAULT;1\.2;AES256;critique' <<<"$_m10d_e03_main"
# Chaque version de passwords.yml de l'historique (toutes branches) commence par l'en-tête Vault.
_m10d_e03_historique() {
  local r n=0
  while read -r r; do
    git -C "$_M10D_OS" show "$r:etc/kolla/passwords.yml" 2>/dev/null | head -n 1 | grep -q '^\$ANSIBLE_VAULT;' || return 1
    n=$((n + 1))
  done < <(git -C "$_M10D_OS" rev-list --all -- etc/kolla/passwords.yml 2>/dev/null)
  ((n > 0))
}
check_cmd "Historique Git : passwords.yml n'a jamais été commité en clair" _m10d_e03_historique

# --- 6. Pipeline ---------------------------------------------------------------------------------
check_cmd "plateforme/openstack (main) : .gitlab-ci.yml" _m10d_fichier_main plateforme/openstack .gitlab-ci.yml
check_cmd "plateforme/openstack (main) : README.md" _m10d_fichier_main plateforme/openstack README.md
_m10d_e03_echec() {
  gitlab_api "projects/plateforme%2Fopenstack/pipelines?status=failed&per_page=1" | jq -e 'length >= 1' >/dev/null
}
check_cmd "Pipeline : au moins un échec enregistré (MR d'essai avec un passwords.yml en clair)" _m10d_e03_echec
_m10d_e03_adr() {
  gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?path=docs/cloud/adr&ref=main&per_page=100" \
    | jq -e 'map(select(.name | test("^ADR-0101"))) | length == 1' >/dev/null
}
check_cmd "plateforme/medisphere (main) : ADR-0101 dans docs/cloud/adr/" _m10d_e03_adr
