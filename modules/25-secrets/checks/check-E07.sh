# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # variables jq entre apostrophes : voulu
#
# check-E07.sh — M25-E07 : Les machines : AppRole pour les checks et medictl
# À lancer depuis adm01. Lecture seule : rôles AppRole et politiques (réglages, jamais de role_id ni
# de secret_id), droits des fichiers d'accès sur adm01, absence du secret Proxmox dans pve-api.env,
# « medictl config » (qui lit le secret dans le coffre et l'affiche masqué), code de plateforme/outils.
# Contrôle négatif : l'identité des checks tente de LIRE une valeur et doit être refusée.

# shellcheck source=_m25-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-decouverte.sh"

title "M25-E07 — Les machines : AppRole pour les checks et medictl"
require_cmd jq curl

# --- 1. L'identité des vérifications -----------------------------------------------------------------
check_output "openbao-checks.env présent, en 600" '^600$' stat -c %a "$_M25D_FICHIER_CHECKS"
check_cmd "openbao-checks.env : BAO_ROLE_ID et BAO_SECRET_ID définis" _m25d_contient \
  "$(grep -cE '^(BAO_ROLE_ID|BAO_SECRET_ID)=.+' "$_M25D_FICHIER_CHECKS" 2>/dev/null || true)" '^2$'
_M25D_MODE=approle
check_cmd "Connexion AppRole des vérifications acceptée (bao_api sys/auth)" _m25d_json "$(_m25d_api sys/auth)" \
  '(.data // .)["approle/"].type == "approle"'
check_cmd "L'identité des vérifications ne lit AUCUNE valeur (kv/data/plateforme/medictl/pve refusé)" \
  test -z "$(bao_api kv/data/plateforme/medictl/pve 2>/dev/null || true)"

# --- 2. Les rôles ------------------------------------------------------------------------------------------
for _m25d_e07_r in wb-checks medictl; do
  _m25d_e07_role="$(_m25d_api "auth/approle/role/$_m25d_e07_r")"
  if [[ -z "$_m25d_e07_role" ]]; then
    _ko "Rôle AppRole $_m25d_e07_r introuvable (auth/approle/role/$_m25d_e07_r)"
    continue
  fi
  check_cmd "Rôle $_m25d_e07_r : politique $_m25d_e07_r seule, sans la politique default" _m25d_json "$_m25d_e07_role" \
    '.data.token_policies == [$r] and .data.token_no_default_policy == true' --arg r "$_m25d_e07_r"
  check_cmd "Rôle $_m25d_e07_r : secret_id exigé, lié à des adresses (secret_id_bound_cidrs)" _m25d_json "$_m25d_e07_role" \
    '.data.bind_secret_id == true and (.data.secret_id_bound_cidrs | length) >= 1
     and all(.data.secret_id_bound_cidrs[]; test("/32$"))'
  check_cmd "Rôle $_m25d_e07_r : jeton lié aux mêmes adresses, de 15 minutes au plus" _m25d_json "$_m25d_e07_role" \
    '(.data.token_bound_cidrs | length) >= 1 and .data.token_max_ttl > 0 and .data.token_max_ttl <= 900'
  check_cmd "Rôle $_m25d_e07_r : jetons « batch » (ni renouvelables ni stockés)" _m25d_json "$_m25d_e07_role" \
    '.data.token_type == "batch"'
done

# --- 3. Les politiques des machines -------------------------------------------------------------------------
check_cmd "Politique wb-checks : aucune lecture de valeur (kv/data), de secret-id ou de role-id" \
  _m25d_aucun '^kv/(data|\*|\+)|secret-id|role-id|^(\*|\+)' "$(_m25d_regles wb-checks)"
check_cmd "Politique medictl : lecture seule de kv/data/plateforme/medictl/*" _m25d_json \
  "$(_m25d_regles medictl | jq -Rn '[inputs | select(length > 0)]')" \
  'length >= 1 and all(.[]; test("^kv/data/plateforme/medictl/[^ ]* \"read\"$"))'

# --- 4. medictl lit son secret dans le coffre --------------------------------------------------------------------
check_cmd "kv/plateforme/medictl/pve existe (secret du jeton Proxmox de medictl)" _m25d_json \
  "$(_m25d_api kv/metadata/plateforme/medictl/pve)" '.data.current_version >= 1'
check_output "adm01 : medictl-openbao.env (accès AppRole de medictl) en 600" '^600$' \
  stat -c %a "$HOME/.config/workbook/medictl-openbao.env"
check_output "adm01 : plus de PVE_TOKEN_SECRET dans pve-api.env (le secret est sorti du disque)" '^0$' \
  grep -c '^[[:space:]]*\(export[[:space:]]\+\)\?PVE_TOKEN_SECRET=' "$HOME/.config/workbook/pve-api.env"
check_cmd "plateforme/outils : src/medictl/coffre.py sur main" _m25d_contient \
  "$(_m25d_contenu_main plateforme/outils src/medictl/coffre.py)" 'auth/approle/login'
if command -v medictl >/dev/null 2>&1; then
  check_output "medictl config : le secret Proxmox vient d'OpenBao (affiché masqué)" \
    'PVE_TOKEN_SECRET=\*\*\*\* +\[openbao \(kv/plateforme/medictl/pve\)\]' medictl config
else
  _ko "adm01 : medictl introuvable dans le PATH (uv tool install, M02-E25)"
fi
