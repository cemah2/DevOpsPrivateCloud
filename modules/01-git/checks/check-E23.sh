# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E23.sh — M01-E23 « Installer GitLab Runner sur runner01 »
# Lancé depuis adm01. Lecture seule (Proxmox, DNS, runner01 en SSH, API GitLab).
# Les runners se lisent par l'API d'administration : après M01-E31 (Admin Mode), le jeton
# des checks doit porter la portée admin_mode en plus de read_api.

title "M01-E23 — Installer GitLab Runner sur runner01"
require_cmd ssh dig jq curl

_m01_get() { gitlab_api "$1" 2>/dev/null || true; }

# --- 1. VM runner01 ------------------------------------------------------------------
check_ssh_output "VM 1007 nommée runner01" "$WB_PVE_HOST" '^name: runner01$' "qm config 1007"
check_ssh "VM 1007 : étiquettes socle et role-runner" "$WB_PVE_HOST" \
  't=$(qm config 1007 | sed -n "s/^tags: //p"); echo ";$t;" | grep -q ";socle;" && echo ";$t;" | grep -q ";role-runner;"'
check_ssh "VM 1007 : 2 vCPU et 4096 Mo" "$WB_PVE_HOST" \
  'c=$(qm config 1007); echo "$c" | grep -qx "cores: 2" && echo "$c" | grep -qx "memory: 4096"'
check_ssh "VM 1007 : carte réseau sur le VNet vinfra" "$WB_PVE_HOST" \
  'qm config 1007 | grep -E "^net0:" | grep -q "bridge=vinfra"'
check_ssh "VM 1007 : démarrage automatique, après git01" "$WB_PVE_HOST" \
  'o() { qm config "$1" | sed -nE "s/^startup:.*order=([0-9]+).*/\1/p"; }; g=$(o 1004); r=$(o 1007); qm config 1007 | grep -qx "onboot: 1" && [ -n "$r" ] && [ "$r" -gt "${g:-0}" ]'
check_ssh "VM 1007 rangée dans le pool lab" "$WB_PVE_HOST" \
  'pvesh get /pools/lab --output-format json | grep -Eq "\"vmid\" *: *1007([^0-9]|$)"'

# --- 2. Nom et accès -------------------------------------------------------------------
check_dns "DNS : runner01.par1.medisphere.internal → 10.10.20.15" runner01.par1.medisphere.internal A '^10\.10\.20\.15$' 10.10.20.10
check_dns "DNS : inverse de 10.10.20.15" 15.20.10.10.in-addr.arpa PTR '^runner01\.par1\.medisphere\.internal\.$' 10.10.20.10
check_ssh "alias SSH runner01 (admin, sudo sans mot de passe)" runner01 'sudo -n true'

# --- 3. Système et paquets -------------------------------------------------------------
check_ssh "runner01 : racine de la PKI provisoire installée" runner01 \
  'test -s /usr/local/share/ca-certificates/medisphere-provisoire.crt'
check_ssh "runner01 : HTTPS vers git01 vérifié par le magasin du système (sans -k)" runner01 \
  'curl -fsS -o /dev/null --max-time 10 https://git01.par1.medisphere.internal/users/sign_in'
check_ssh_output "runner01 : GitLab Runner en version 19.4.x" runner01 '^Version: +19\.4\.' 'gitlab-runner --version'
check_ssh "runner01 : gitlab-runner-helper-images à la même version que gitlab-runner" runner01 \
  'v=$(dpkg-query -W -f="\${Version}" gitlab-runner 2>/dev/null); h=$(dpkg-query -W -f="\${Version}" gitlab-runner-helper-images 2>/dev/null); [ -n "$v" ] && [ "$v" = "$h" ]'
check_ssh "runner01 : versions du runner figées (pas de mise à jour surprise)" runner01 \
  'apt-mark showhold | grep -qx gitlab-runner'
check_ssh "runner01 : service gitlab-runner actif et activé" runner01 \
  'systemctl is-active --quiet gitlab-runner && systemctl is-enabled --quiet gitlab-runner'
check_ssh "runner01 : exécuteur shell, jeton d'authentification glrt- dans config.toml" runner01 \
  'f=/etc/gitlab-runner/config.toml; sudo -n grep -Eq "^[[:space:]]*executor[[:space:]]*=[[:space:]]*\"shell\"" $f && sudo -n grep -Eq "^[[:space:]]*token[[:space:]]*=[[:space:]]*\"glrt-" $f'
check_ssh "runner01 : config.toml lisible par root seulement" runner01 \
  '[ "$(sudo -n stat -c %U:%a /etc/gitlab-runner/config.toml)" = "root:600" ]'
check_ssh "runner01 : l'utilisateur des jobs n'a aucun droit d'administration" runner01 \
  '! id -nG gitlab-runner | grep -qwE "sudo|adm|docker|lxd" && ! sudo -n -l -U gitlab-runner 2>/dev/null | grep -q "may run"'

# --- 4. Outils des jobs, vus par l'utilisateur gitlab-runner -----------------------------
check_ssh "runner01 : uv installé pour tous (/usr/local/bin)" runner01 'test -x /usr/local/bin/uv'
check_ssh_output "runner01 : pre-commit 4.x utilisable par gitlab-runner" runner01 '^pre-commit 4\.' \
  'cd /tmp && sudo -n -u gitlab-runner -H pre-commit --version'
check_ssh_output "runner01 : gitleaks 8.30.x utilisable par gitlab-runner" runner01 '^8\.30\.' \
  'cd /tmp && sudo -n -u gitlab-runner -H gitleaks version'
check_ssh "runner01 : git utilisable par gitlab-runner" runner01 'cd /tmp && sudo -n -u gitlab-runner -H git --version'

# --- 5. Côté GitLab ----------------------------------------------------------------------
_m01_runners="$(_m01_get 'runners/all?type=instance_type&per_page=100')"
check_cmd "API : liste des runners d'instance lisible avec le jeton des checks" jq -e 'type == "array"' <<<"$_m01_runners"
_m01_rid=""
for _m01_id in $(jq -r '.[]?.id' <<<"$_m01_runners" 2>/dev/null); do
  if _m01_get "runners/$_m01_id" | jq -e '(.tag_list | index("shell")) and (.tag_list | index("socle"))' >/dev/null 2>&1; then
    _m01_rid="$_m01_id"
    break
  fi
done
check_cmd "un runner d'instance porte les étiquettes shell et socle" test -n "$_m01_rid"
_m01_detail="$(_m01_get "runners/${_m01_rid:-0}")"
check_cmd "ce runner est en ligne et n'est pas en pause" \
  jq -e '.status == "online" and (.paused | not)' <<<"$_m01_detail"
check_cmd "ce runner refuse les jobs sans étiquette" jq -e '.run_untagged == false' <<<"$_m01_detail"
check_cmd "le gestionnaire du runner (runner01) est en version 19.4.x" \
  jq -e 'any(.[]?; (.version // "") | startswith("19.4."))' <<<"$(_m01_get "runners/${_m01_rid:-0}/managers")"
check_cmd "ce runner a déjà exécuté un job avec succès" \
  jq -e 'length > 0' <<<"$(_m01_get "runners/${_m01_rid:-0}/jobs?status=success&per_page=1")"

# --- 6. Documentation --------------------------------------------------------------------
check_output "inventaire de plateforme/medisphere : runner01 et 10.10.20.15 (branche main)" \
  'runner01.*10\.10\.20\.15|10\.10\.20\.15.*runner01' \
  gitlab_api "projects/plateforme%2Fmedisphere/repository/files/docs%2Fsocle%2Finventaire.md/raw?ref=main"
