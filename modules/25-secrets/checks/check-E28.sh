# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # requêtes LogQL, filtres jq et commandes distantes entre apostrophes
#
# check-E28.sh — M25-E28 « Durcir OpenBao » : aucune requête faite avec un jeton racine depuis 24 h et
# aucun jeton racine vivant ; une génération de jeton racine tracée depuis 30 jours ; secret_id des
# AppRole délivrés enveloppés (et aucun en clair depuis 7 jours) ; unité durcie ; TLS 1.2 refusé ;
# generate-root non authentifié désactivé explicitement ; durées maximales explicites des méthodes ;
# quota de débit sur la connexion AppRole ; procédure sur main.
# À lancer depuis adm01. Lecture seule : Loki (locataire audit), AppRole wb-checks (sys/auth, accessors,
# quotas), SSH en consultation (systemctl show, grep), openssl s_client, GitLab.

# shellcheck source=_m25-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-production.sh"

title "M25-E28 — Durcir OpenBao : jeton racine, enveloppement, systemd, TLS"
require_cmd curl jq openssl

# --- Jeton racine ---------------------------------------------------------------------------------------
_m25_e28_total="$(_m25p_loki_nb '{service="openbao"}' 24h)"
if [[ ! "$_m25_e28_total" =~ ^[0-9]+$ || "$_m25_e28_total" -eq 0 ]]; then
  check_cmd "audit d'OpenBao présent dans Loki (locataire audit, 24 h) — sans lui, rien ne se prouve" false
else
  check_output "aucune requête avec un jeton racine depuis 24 h (audit)" '^0$' \
    _m25p_loki_nb '{service="openbao"} |= `"token_policies":["root"]`' 24h
fi
_m25p_connexion
_m25_e28_racines() {
  local acc n=0 r
  [[ -n "$_WB_BAO_JETON" ]] || return 1
  while IFS= read -r acc; do
    [[ -n "$acc" ]] || continue
    n=$((n + 1))
    ((n <= 300)) || break
    r="$(jq -nc --arg a "$acc" '{accessor: $a}' | curl -sf --max-time "$WB_TIMEOUT" \
      -K <(printf 'header = "X-Vault-Token: %s"\n' "$_WB_BAO_JETON") --data @- \
      "${WB_OPENBAO_URL:-https://$_M25P_SERVICE:$_M25P_PORT}/v1/auth/token/lookup-accessor" 2>/dev/null)" || return 1
    jq -e '.data.policies | index("root")' >/dev/null 2>&1 <<<"$r" && return 1
  done < <(_m25p_bao 'auth/token/accessors?list=true' | jq -r '.data.keys[]? // empty' 2>/dev/null || true)
  ((n > 0))
}
check_cmd "aucun jeton racine vivant (accessors des jetons de service, 300 au plus)" _m25_e28_racines
check_cmd "une génération de jeton racine (sys/generate-root-token) tracée dans l'audit depuis 30 jours" \
  bash -c '[[ "${1:-0}" =~ ^[0-9]+$ && "$1" -ge 1 ]]' _ \
  "$(_m25p_loki_nb '{service="openbao"} |= `"type":"response"` |= `sys/generate-root-token/update`' 720h)"
check_cmd "procédure du jeton racine sur main (docs/securite/secrets/procedure-jeton-racine.md)" \
  _m25p_doc "$_M25P_DOC" docs/securite/secrets 'procedure-jeton-racine\.md$' 15 'generate-root' 'r[ée]voqu' 'audit'

# --- Enveloppement des secret_id ----------------------------------------------------------------------------
check_cmd "au moins un secret_id délivré enveloppé depuis 30 jours (wrap_info dans la réponse)" \
  bash -c '[[ "${1:-0}" =~ ^[0-9]+$ && "$1" -ge 1 ]]' _ \
  "$(_m25p_loki_nb '{service="openbao"} |= `"type":"response"` |~ `auth/approle/role/[^/"]+/secret-id"` |= `"wrap_info"`' 720h)"
check_output "aucun secret_id délivré en clair depuis 7 jours" '^0$' \
  _m25p_loki_nb '{service="openbao"} |= `"type":"response"` |~ `auth/approle/role/[^/"]+/secret-id"` |~ `"operation":"(update|create)"` != `"wrap_info"`' 168h

# --- Unité, TLS, écouteur ---------------------------------------------------------------------------------------
for _m25_e28_n in "${_M25P_NOEUDS[@]}" "$_M25P_KMS"; do
  check_ssh "$_m25_e28_n : unité en ProtectSystem=strict, noyau protégé, appels système filtrés" "$_m25_e28_n" \
    '[ "$(systemctl show openbao.service -p ProtectSystem --value)" = strict ] \
     && [ "$(systemctl show openbao.service -p ProtectKernelTunables --value)" = yes ] \
     && [ "$(systemctl show openbao.service -p ProtectKernelModules --value)" = yes ] \
     && [ -n "$(systemctl show openbao.service -p SystemCallFilter --value)" ] \
     && systemctl is-active --quiet openbao.service'
  check_ssh "$_m25_e28_n : generate-root non authentifié désactivé explicitement (openbao.hcl)" "$_m25_e28_n" \
    'sudo -n grep -Eq "^[[:space:]]*disable_unauthed_generate_root_endpoints[[:space:]]*=[[:space:]]*\"?true" /etc/openbao/openbao.hcl'
  _m25_e28_tls12() {
    ! openssl s_client -connect "$1.$_M25P_DOMAINE:$_M25P_PORT" -servername "$1.$_M25P_DOMAINE" -tls1_2 </dev/null >/dev/null 2>&1 \
      && openssl s_client -connect "$1.$_M25P_DOMAINE:$_M25P_PORT" -servername "$1.$_M25P_DOMAINE" -tls1_3 </dev/null 2>/dev/null \
        | grep -q 'TLSv1.3'
  }
  check_cmd "$_m25_e28_n : TLS 1.2 refusé, TLS 1.3 accepté" _m25_e28_tls12 "$_m25_e28_n"
done

# --- Durées de vie et quotas ----------------------------------------------------------------------------------------
_m25_e28_auth="$(_m25p_bao sys/auth)"
for _m25_e28_m in approle/:86400 gitlab/:86400 k8s-par1/:86400 oidc/:43200; do
  check_cmd "méthode ${_m25_e28_m%%:*} : TTL maximal explicite, ${_m25_e28_m##*:} s au plus" _m25p_jq "$_m25_e28_auth" \
    '(.data[$m] // .[$m]).config.max_lease_ttl as $t | ($t > 0 and $t <= ($max | tonumber))' \
    --arg m "${_m25_e28_m%%:*}" --arg max "${_m25_e28_m##*:}"
done
_m25_e28_quota() {
  local q
  while IFS= read -r q; do
    [[ -n "$q" ]] || continue
    _m25p_jq "$(_m25p_bao "sys/quotas/rate-limit/$q")" '.data.path | startswith("auth/approle")' && return 0
  done < <(_m25p_bao 'sys/quotas/rate-limit?list=true' | jq -r '.data.keys[]? // empty' 2>/dev/null || true)
  return 1
}
check_cmd "un quota de débit vise la connexion AppRole (auth/approle…)" _m25_e28_quota
