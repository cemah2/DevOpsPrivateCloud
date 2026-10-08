# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes bash -c entre apostrophes
#
# check-E31.sh — M10-E31 « Le libre-service pour MédiAgenda »
# Lecture seule : ressources du projet mediagenda-dev (cloud des checks, admin), requêtes HTTP vers
# l'IP flottante du répartiteur depuis adm01, GitLab (projets mediagenda/recette-infra et
# plateforme/medisphere).

# shellcheck source=_m10-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-production.sh"

title "M10-E31 — Le libre-service pour MédiAgenda"
require_cmd openstack jq curl

_m10_pj="$(_m10p_os project show mediagenda-dev --domain medisphere 2>/dev/null | jq -r '.id // empty' || true)"
_m10_P=agenda-recette

title "Réseau"
_m10_existe() {   # _m10_existe TYPE NOM [FILTRE_JQ] — ressource unique du projet, filtre facultatif
  local l
  l="$(_m10p_os "$1" list --project "$_m10_pj")" || return 1
  jq -e --arg n "$2" "[.[] | select(.Name == \$n or .name == \$n)] | length == 1 and (.[0] | ${3:-true})" >/dev/null <<<"$l"
}
check_cmd "projet mediagenda-dev trouvé" test -n "$_m10_pj"
check_cmd "réseau $_m10_P-net" _m10_existe network "$_m10_P-net"
check_cmd "sous-réseau $_m10_P-sn hors des réseaux du lab" _m10_existe subnet "$_m10_P-sn" \
  '(.Subnet // .cidr) | test("^10\\.(10|20|255)\\.") | not'
check_cmd "routeur $_m10_P-rt" _m10_existe router "$_m10_P-rt"
_m10_passerelle() {
  local r e
  r="$(_m10p_os router show "$(_m10p_id router "$_m10_P-rt" "$_m10_pj")")" || return 1
  e="$(_m10p_os network show ext-net | jq -r .id)" || return 1
  jq -e --arg e "$e" '.external_gateway_info.network_id == $e' >/dev/null <<<"$r"
}
check_cmd "routeur $_m10_P-rt relié à ext-net" _m10_passerelle
_m10_groupes() {
  local l
  l="$(_m10p_os security group list --project "$_m10_pj")" || return 1
  jq -e --arg a "$_m10_P-app" --arg b "$_m10_P-admin" 'any(.[]; .Name == $a) and any(.[]; .Name == $b)' >/dev/null <<<"$l"
}
check_cmd "groupes de sécurité $_m10_P-app et $_m10_P-admin" _m10_groupes

title "Instances et volume"
_m10_srv=""
_m10_srv="$(_m10p_os server list --project "$_m10_pj" --long 2>/dev/null || echo '[]')"
for _m10_i in app01 app02; do
  check_cmd "instance $_m10_P-$_m10_i ACTIVE" \
    jq -e --arg n "$_m10_P-$_m10_i" 'any(.[]; .Name == $n and .Status == "ACTIVE")' <<<"$_m10_srv"
done
_m10_sans_fip() {
  # Aucune adresse de 10.10.52.0/24 (IP flottante) sur les instances agenda-recette-*.
  jq -e --arg p "$_m10_P-" '[.[] | select(.Name | startswith($p))] | length >= 2
    and all(.[]; (.Networks | tostring | test("10\\.10\\.52\\.") | not))' >/dev/null <<<"$_m10_srv"
}
check_cmd "aucune IP flottante sur les instances (accès d'administration retiré)" _m10_sans_fip
_m10_volume() {
  local v sid
  v="$(_m10p_os volume show "$(_m10p_id volume "$_m10_P-donnees" "$_m10_pj")")" || return 1
  sid="$(jq -r --arg n "$_m10_P-app01" '.[] | select(.Name == $n) | .ID' <<<"$_m10_srv")"
  [[ -n "$sid" ]] && jq -e --arg s "$sid" '.size == 5 and any(.attachments[]?; .server_id == $s)' >/dev/null <<<"$v"
}
check_cmd "volume $_m10_P-donnees (5 Go) attaché à $_m10_P-app01" _m10_volume

title "Répartiteur (Octavia, fournisseur OVN)"
_m10_lb="$(_m10p_os loadbalancer list --project "$_m10_pj" 2>/dev/null | jq -c --arg n "$_m10_P-lb" '[.[] | select(.name == $n)] | if length == 1 then .[0] else null end' 2>/dev/null || echo null)"
check_cmd "répartiteur $_m10_P-lb : fournisseur ovn, ACTIVE, ONLINE" \
  jq -e '.provider == "ovn" and .provisioning_status == "ACTIVE" and .operating_status == "ONLINE"' <<<"$_m10_lb"
_m10_membres() {
  local st
  st="$(timeout 60 openstack --os-cloud "$_M10P_CLOUD" loadbalancer status show "$(jq -r '.id // "aucun"' <<<"$_m10_lb")" 2>/dev/null)" || return 1
  jq -e '[.loadbalancer.listeners[]?.pools[]?.members[]? | select(.operating_status == "ONLINE")] | length >= 2' >/dev/null <<<"$st" \
    && jq -e '[.loadbalancer.listeners[]? | select(.protocol_port == 80)] | length == 1' >/dev/null <<<"$st"
}
check_cmd "écoute TCP 80, au moins deux membres ONLINE" _m10_membres
_m10_fip="$(_m10p_os floating ip list --port "$(jq -r '.vip_port_id // "aucun"' <<<"$_m10_lb")" 2>/dev/null \
  | jq -r '.[0]["Floating IP Address"] // empty' || true)"
check_output "IP flottante associée à la VIP du répartiteur (${_m10_fip:-aucune})" '^10\.10\.52\.(2[0-4][0-9])$' printf '%s\n' "${_m10_fip:-}"
_m10_deux_instances() {
  local _ noms=""
  [[ -n "$_m10_fip" ]] || return 1
  for _ in $(seq 1 30); do
    noms+="$(curl -s --max-time 3 "http://$_m10_fip/" | grep -oE "$_m10_P-app0[0-9]" | head -n 1)"$'\n'
  done
  [[ "$(grep -c . <<<"$(sort -u <<<"$noms")")" -ge 2 ]]
}
check_cmd "http://<IP flottante>/ : HTTP 200 et réponses des deux instances (30 requêtes)" _m10_deux_instances
check_cmd "le port 22 n'est pas joignable par l'IP flottante du répartiteur" \
  bash -c '[ -n "$1" ] && ! timeout 4 bash -c "exec 3<>/dev/tcp/$1/22" 2>/dev/null' _ "${_m10_fip:-}"

title "Dépôt de l'équipe et documentation"
check_cmd "mediagenda/recette-infra : dernier pipeline de main réussi" _m10p_pipeline_ok mediagenda/recette-infra
check_cmd "mediagenda/recette-infra : module openstack-env-app référencé par une étiquette" \
  _m10p_fichier_contient mediagenda/recette-infra main.tf 'openstack-env-app\?ref=v[0-9]+\.[0-9]+\.[0-9]+'
_m10_pas_detat() {
  gitlab_api "projects/mediagenda%2Frecette-infra/repository/tree?ref=main&recursive=true&per_page=100" 2>/dev/null \
    | jq -e 'type == "array" and length > 0 and (any(.[]; .name | test("\\.tfstate|secure\\.yaml|clouds\\.yaml|\\.tfvars\\.secret")) | not)' >/dev/null
}
check_cmd "mediagenda/recette-infra : aucun fichier d'état ni d'identifiants dans le dépôt" _m10_pas_detat
_m10_pas_admin() {
  # Rôles attribués dans mediagenda-dev : aucune application credential ne peut porter plus
  # que les rôles de son utilisateur ; on vérifie qu'aucun compte de service de l'équipe n'est admin.
  local r
  r="$(_m10p_os role assignment list --project "$_m10_pj" --names)" || return 1
  jq -e '(any(.[]; .Role == "admin")) | not' >/dev/null <<<"$r"
}
check_cmd "projet mediagenda-dev : personne n'y a le rôle admin" _m10_pas_admin
check_cmd "plateforme/tofu-modules : module openstack-env-app sur main (README)" \
  _m10p_fichier_existe plateforme/tofu-modules openstack-env-app/README.md
check_cmd "plateforme/medisphere : docs/cloud/libre-service.md (limites du répartiteur OVN)" \
  _m10p_fichier_contient plateforme/medisphere docs/cloud/libre-service.md 'ovn' 'tls'
