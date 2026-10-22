# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E36.sh — M21-E36 « Panne : l'alerte ne part plus » : une alerte critique de la plateforme est
# routée vers l'astreinte, les envois réussissent, ni silence géant ni inhibition à l'envers, l'essai
# de la chaîne (s'il est en cours) est arrivé dans la boîte astreinte@, RB-218, panne close.
# Lecture seule (amtool ne lit que la configuration récupérée par l'API).

# shellcheck source=_m21-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-expert.sh"

title "M21-E36 — Les alertes critiques arrivent à l'astreinte"
require_cmd jq yq amtool curl

_m21_e36_conf="$(_m21x_am_config_json)" || _m21_e36_conf=""
if [[ -z "$_m21_e36_conf" ]]; then
  skip "configuration d'Alertmanager" "API de 10.10.41.61 muette (lab/bin/check 21 06)"
else
  _m21_e36_route() {
    local t r
    t="$(mktemp)"
    am_api status | jq -r '.config.original' >"$t"
    r="$(amtool config routes test --config.file="$t" gravite=critique equipe=plateforme alertname=EssaiChaineAlerteCritique 2>/dev/null)"
    rm -f "$t"
    grep -qi astreinte <<<"$r"
  }
  check_cmd "une alerte critique de la plateforme est routée vers le récepteur de l'astreinte" _m21_e36_route
  check_cmd "le récepteur de l'astreinte écrit à astreinte@medisphere.internal" \
    jq -e '[.receivers[] | select(.name | test("astreinte"; "i")) | .email_configs[]?.to] | any(test("astreinte@medisphere\\.internal"))' <<<"$_m21_e36_conf"
  check_cmd "smarthost : smtp.par1.medisphere.internal:25 partout" \
    jq -e '[.global.smtp_smarthost // empty, (.receivers[].email_configs[]?.smarthost // empty)]
           | length > 0 and all(. == "smtp.par1.medisphere.internal:25")' <<<"$_m21_e36_conf"
  check_cmd "aucune inhibition où une alerte moins grave éteint une critique" \
    jq -e '[.inhibit_rules[]? | select((.target_matchers // [] | map(test("critique")) | any)
                                      and (.source_matchers // [] | map(test("avertissement|info")) | any))] | length == 0' <<<"$_m21_e36_conf"
fi

_m21_e36_silences() {
  am_api silences 2>/dev/null | jq -e '
    [.[] | select(.status.state == "active")
     | select(((.endsAt | sub("\\.[0-9]+"; "") | fromdateiso8601) - (.startsAt | sub("\\.[0-9]+"; "") | fromdateiso8601)) > 7 * 86400)
     | select((.matchers | length) == 1 and (.matchers[0].name | test("^(equipe|gravite)$")))] | length == 0' >/dev/null
}
check_cmd "aucun silence actif de plus de 7 jours sur toute une équipe ou toute une gravité" _m21_e36_silences
check_cmd "aucun envoi de courriel en échec depuis 15 min (alertmanager_notifications_failed_total)" \
  _m21x_vide 'sum(increase(alertmanager_notifications_failed_total{integration="email",namespace="supervision"}[15m])) > 0'

_m21_e36_depuis="$(kube -n "$_m21x_ns" get configmap temoin-etat -o json 2>/dev/null |
  jq -r 'if (.data["etat.json"] | fromjson | .essai) == 1 then .metadata.annotations["medisphere.internal/essai-depuis"] // empty else empty end' 2>/dev/null)" || _m21_e36_depuis=""
if [[ -n "$_m21_e36_depuis" ]]; then
  check_cmd "essai en cours : EssaiChaineAlerteCritique reçue par astreinte@ depuis le début de l'essai" \
    bash -c '[[ "$1" -ge 1 ]]' _ "$(_m21x_courriels 'to:astreinte@medisphere.internal EssaiChaineAlerteCritique' "$_m21_e36_depuis")"
else
  skip "essai de la chaîne d'alerte" "aucun essai en cours (il est déclenché par lab/bin/break 21 36)"
fi
check_cmd "RB-218 : section « l'alerte n'arrive pas »" \
  _m21x_doc_contient "$_m21x_rb/RB-218-*.md" '^#+ .*(n.arrive|muette|ne part)'
check_cmd "panne M21-E36 close (lab/bin/break 21 36 --annuler après réparation)" _m21x_aucune_panne_active E36
