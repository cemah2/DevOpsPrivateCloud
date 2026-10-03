# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E17.sh — M00-E17 : API Proxmox et jeton à privilèges minimaux
# À lancer depuis adm01. Uniquement des lectures (GET) sur l'API. Lecture seule.

title "M00-E17 — API Proxmox et jeton à privilèges minimaux"

env_file="$HOME/.config/workbook/pve-api.env"

# --- Secret sur adm01 ---
check_cmd "fichier d'accès API présent (~/.config/workbook/pve-api.env)" test -s "$env_file"
check_output "fichier d'accès API lisible par son seul propriétaire (600)" '^600$' stat -c %a "$env_file"

PVE_API_URL="" PVE_NODE="" PVE_TOKEN_ID="" PVE_TOKEN_SECRET="" PVE_CACERT=""
# shellcheck disable=SC1090
if [[ -r "$env_file" ]] && source "$env_file"; then :; fi
check_cmd "variables PVE_API_URL, PVE_NODE, PVE_TOKEN_ID et PVE_TOKEN_SECRET définies" \
  test -n "$PVE_API_URL" -a -n "$PVE_NODE" -a -n "$PVE_TOKEN_ID" -a -n "$PVE_TOKEN_SECRET"
check_output "le jeton utilisé est wb-automation@pve!lab" '^wb-automation@pve!lab$' printf '%s\n' "$PVE_TOKEN_ID"

auth=(-H "Authorization: PVEAPIToken=${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}")
if [[ -n "$PVE_CACERT" && -r "$PVE_CACERT" ]]; then
  tls=(--cacert "$PVE_CACERT")
  check_http "API joignable avec le jeton, certificat vérifié (GET /version)" \
    "${PVE_API_URL:-https://invalide}/version" 200 "${tls[@]}" "${auth[@]}"
else
  tls=(-k)
  skip "certificat de pve01 vérifié par le client" "PVE_CACERT absent ou illisible"
  check_http "API joignable avec le jeton (GET /version)" \
    "${PVE_API_URL:-https://invalide}/version" 200 "${tls[@]}" "${auth[@]}"
fi

# --- Ce que le jeton peut faire, et ce qu'il ne doit pas pouvoir faire ---
check_http "jeton : lecture du pool lab autorisée" \
  "${PVE_API_URL:-https://invalide}/pools/lab" 200 "${tls[@]}" "${auth[@]}"
check_http "jeton : état du nœud refusé (pas de droits sur le nœud)" \
  "${PVE_API_URL:-https://invalide}/nodes/${PVE_NODE:-x}/status" 403 "${tls[@]}" "${auth[@]}"
check_http "jeton : journal système du nœud refusé" \
  "${PVE_API_URL:-https://invalide}/nodes/${PVE_NODE:-x}/syslog" 403 "${tls[@]}" "${auth[@]}"

# --- Configuration côté pve01 ---
check_ssh "pve01 : rôle WBAutomation existant" "$WB_PVE_HOST" \
  'pvesh get /access/roles/WBAutomation --output-format json >/dev/null'
check_ssh "pve01 : WBAutomation ne contient aucun privilège d'administration" "$WB_PVE_HOST" \
  '! pvesh get /access/roles/WBAutomation --output-format json | grep -Eq "\"(Sys\.[A-Za-z]+|Permissions\.Modify|User\.Modify|Realm\.[A-Za-z]+|Group\.Allocate|Pool\.Allocate|Datastore\.Allocate|SDN\.Allocate|VM\.Console|VM\.GuestAgent\.Unrestricted)\""'
check_ssh "pve01 : jeton « lab » de wb-automation@pve à privilèges séparés" "$WB_PVE_HOST" \
  'pveum user token list wb-automation@pve --output-format json | tr "}" "\n" | grep -E "\"tokenid\" *: *\"lab\"" | grep -Eq "\"privsep\" *: *(1|true)"'
check_ssh "pve01 : le jeton a une date d'expiration" "$WB_PVE_HOST" \
  'pveum user token list wb-automation@pve --output-format json | tr "}" "\n" | grep -E "\"tokenid\" *: *\"lab\"" | grep -Eq "\"expire\" *: *[1-9]"'
check_ssh "pve01 : ACL WBAutomation sur /pool/lab pour l'utilisateur" "$WB_PVE_HOST" \
  'pveum acl list --output-format json | tr "}" "\n" | grep -F "\"/pool/lab\"" | grep -F "\"wb-automation@pve\"" | grep -qF "WBAutomation"'
check_ssh "pve01 : ACL WBAutomation sur /pool/lab pour le jeton" "$WB_PVE_HOST" \
  'pveum acl list --output-format json | tr "}" "\n" | grep -F "\"/pool/lab\"" | grep -F "wb-automation@pve!lab" | grep -qF "WBAutomation"'
check_ssh "pve01 : aucune ACL du compte d'automatisation sur / ou /vms" "$WB_PVE_HOST" \
  '! pveum acl list --output-format json | tr "}" "\n" | grep -F "wb-automation@pve" | grep -Eq "\"path\" *: *\"/(vms)?\""'
