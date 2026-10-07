# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E28.sh — M04-E28 « Semaphore UI : exécuter Ansible avec traçabilité »
# VM sem01, DNS, TLS vérifié et redirection, service durci sur PostgreSQL, configuration
# protégée, clés d'hôte vérifiées, projet Semaphore (dépôt en lecture, inventaire fichier,
# modèles exécutés avec succès, rôles de l'équipe), flux et documentation.
# Jeton Semaphore en lecture : WB_SEMAPHORE_TOKEN_FILE (défaut ~/.config/workbook/semaphore-checks.token).

# shellcheck source=_m04-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-production.sh"

# _m04_e28_taches_ok PROJET — au moins deux modèles sur site.yml, chacun avec une tâche réussie.
_m04_e28_taches_ok() {
  local t k
  t="$(_m04_sem_api "project/$1/templates" 2>/dev/null)" || return 1
  k="$(_m04_sem_api "project/$1/tasks" 2>/dev/null)" || return 1
  jq -e --argjson k "$k" '[.[] | select(.playbook == "playbooks/site.yml") | .id] as $ids
    | ($ids | length) >= 2 and all($ids[]; . as $i | any($k[]; .template_id == $i and .status == "success"))' \
    >/dev/null 2>&1 <<<"$t"
}

# _m04_e28_acces_lecture — GitLab : jeton de déploiement read_repository actif, ou clés de
#   déploiement toutes sans droit d'écriture.
_m04_e28_acces_lecture() {
  _m04_api_ok "$_M04_PROJET/deploy_tokens" 'any(.[]; (.revoked | not) and (.expired | not) and .scopes == ["read_repository"])' \
    || _m04_api_ok "$_M04_PROJET/deploy_keys" 'length > 0 and all(.[]; .can_push == false)'
}

title "M04-E28 — Semaphore UI"
require_cmd jq ssh curl dig openssl
_m04_charger

# Fin de module (M04-E46) : sem01 est détruite (ADR-0040) et sa configuration documentée.
# Ce contrôle ne s'applique alors plus ; il vérifie seulement que la documentation existe.
# (Si pve01 ne répond pas, on ne conclut rien : les contrôles normaux le diront en rouge.)
if _m04_vms >/dev/null && ! _m04_existe 2041; then
  if _m04_doc_contient "$_M04_DOC/configuration.md" '[Ss]emaphore'; then
    skip "vérifications de sem01 et du projet Semaphore" \
      "sem01 détruite en fin de module (ADR-0040), recréation documentée dans configuration.md"
  else
    check_cmd "sem01 (2041) existe, ou sa destruction est documentée (configuration.md, ADR-0040)" false
  fi
  return 0
fi

title "VM sem01 (2041)"
check_cmd "VM 2041 nommée sem01, dans le pool lab" _m04_vm_filtre 2041 '.name == "sem01" and .pool == "lab"'
check_cmd "VM 2041 : étiquettes env-m04 et role-semaphore, sans gold ni current" \
  _m04_vm_filtre 2041 '(.tags // "" | split(";")) as $t | ($t | index("env-m04")) and ($t | index("role-semaphore")) and ($t | index("current") | not) and ($t | index("gold") | not)'
check_cmd "VM 2041 : interface sur le VNet vinfra" _m04_vm_conf 2041 '^net0:.*bridge=vinfra'
check_dns "DNS : sem01.par1.medisphere.internal → 10.10.20.41" sem01.par1.medisphere.internal A '^10\.10\.20\.41$' 10.10.20.10

title "Service web"
check_output "API : /api/ping répond pong en HTTPS, certificat vérifié" '^pong$' \
  curl -sS --max-time "$WB_TIMEOUT" "$_M04_SEM_URL/api/ping"
check_output "certificat émis par la CA provisoire MédiSphère" 'CA provisoire' \
  bash -c 'openssl s_client -connect 10.10.20.41:443 -servername sem01.par1.medisphere.internal </dev/null 2>/dev/null | openssl x509 -noout -issuer -nameopt oneline,-esc_msb'
check_http "HTTP (port 80) redirige vers HTTPS" "http://sem01.par1.medisphere.internal/" 307

title "Sur sem01"
check_ssh "service semaphore actif" sem01 'systemctl is-active --quiet semaphore'
check_ssh_output "le processus tourne sous le compte semaphore" sem01 '^semaphore$' 'ps -o user= -C semaphore | sort -u'
check_ssh "PostgreSQL actif" sem01 'systemctl is-active --quiet postgresql'
check_ssh_output "/etc/semaphore/config.json : aucun droit pour les autres" sem01 '^[0-7][0-7]0 ' \
  'stat -c "%a %U:%G" /etc/semaphore/config.json'
check_ssh "config.json : base PostgreSQL" sem01 \
  'sudo -n grep -Eq "\"dialect\"[[:space:]]*:[[:space:]]*\"postgres\"" /etc/semaphore/config.json'
check_ssh "config.json : vérification des clés d'hôte imposée aux tâches" sem01 \
  'sudo -n grep -Eq "\"ANSIBLE_HOST_KEY_CHECKING\"[[:space:]]*:[[:space:]]*\"(True|true|1|yes)\"" /etc/semaphore/config.json'
check_ssh "clés d'hôte du socle connues de sem01 (gw01, adm01)" sem01 \
  'for ip in 10.10.10.1 10.10.10.10; do ssh-keygen -F $ip -f /etc/ssh/ssh_known_hosts >/dev/null 2>&1 || sudo -n ssh-keygen -F $ip -f /var/lib/semaphore/.ssh/known_hosts >/dev/null 2>&1 || exit 1; done'

title "Projet Semaphore (API, compte workbook-checks)"
_m04_sp="$(_m04_sem_projet 2>/dev/null || true)"
if [[ -n "$_m04_sp" ]]; then
  check_cmd "dépôt plateforme/ansible déclaré" \
    _m04_sem_ok "project/$_m04_sp/repositories" 'any(.[]; .git_url | test("plateforme/ansible"))'
  check_cmd "inventaire de type fichier" _m04_sem_ok "project/$_m04_sp/inventory" 'any(.[]; .type == "file")'
  check_cmd "deux modèles sur playbooks/site.yml, dont un en --check" \
    _m04_sem_ok "project/$_m04_sp/templates" '([.[] | select(.playbook == "playbooks/site.yml")] | length >= 2) and any(.[]; (.arguments // "") | test("--check"))'
  check_cmd "chaque modèle de site.yml a au moins une tâche réussie" _m04_e28_taches_ok "$_m04_sp"
  check_cmd "nadia.roussel : rôle Task Runner" \
    _m04_sem_ok "project/$_m04_sp/users" 'any(.[]; .username == "nadia.roussel" and .role == "task_runner")'
  check_cmd "karim.benali : rôle Manager" \
    _m04_sem_ok "project/$_m04_sp/users" 'any(.[]; .username == "karim.benali" and .role == "manager")'
  check_cmd "workbook-checks : lecture seule (Guest)" \
    _m04_sem_ok "project/$_m04_sp/role" '.role == "guest"'
else
  check_cmd "projet Semaphore « Socle… » visible avec le jeton des checks" false
fi
check_cmd "GitLab : accès en lecture seule au dépôt (jeton de déploiement read_repository ou clé de déploiement sans écriture)" \
  _m04_e28_acces_lecture

title "Flux et documentation"
check_ssh_output "gw01 : chaîne input, SSH depuis sem01" gw01 '10\.10\.20\.41[^#]*dport 22' \
  "sudo -n nft list chain inet filter input"
check_cmd "matrice des flux : sem01" _m04_doc_contient "$_M04_DOC/matrice-flux.md" 'sem01|10\.10\.20\.41'
check_cmd "registre des secrets : clé de chiffrement de Semaphore et clé ansible-semaphore" \
  _m04_doc_contient "$_M04_DOC/registre-secrets.md" 'access_key_encryption' 'ansible-semaphore'
