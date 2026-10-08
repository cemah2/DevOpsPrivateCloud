# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c (valeurs en paramètres)
#
# check-E24.sh — M08-E24 « Superviser Ceph »
# À lancer depuis adm01 (où vivent la sonde et son timer). Lecture seule : état du cluster (hôte
# _admin), métriques HTTP des mgr, certificats du tableau de bord, unités systemd, une exécution de
# la sonde (qui ne fait que lire), fichiers de plateforme/outils (API GitLab).

# shellcheck source=_m08-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-production.sh"

title "M08-E24 — Superviser Ceph"
require_cmd curl jq openssl systemctl
_m08p_charger
check_cmd "le cluster répond depuis $_M08P_ADMIN (ceph status)" _m08p_joignable

title "Module prometheus des mgr"
check_cmd "le module prometheus est activé" \
  bash -c 'jq -e "(.enabled_modules // []) | index(\"prometheus\") != null" >/dev/null <<<"$1"' _ "$(_m08p_json 'mgr module ls')"
check_cmd "un mgr en attente répond par une erreur HTTP (standby_behaviour = error)" \
  _m08p_config_valeur mgr mgr/prometheus/standby_behaviour error
# Un seul hôte doit servir des métriques ; les autres hôtes à mgr répondent en erreur (ou rien).
_m08_e24_actifs=0
_m08_e24_attente_ok=1
_m08_e24_hotes_mgr="$(_m08p_hotes_type mgr 2>/dev/null || true)"
for _m08_e24_h in "${_M08P_NOEUDS[@]}"; do
  _m08_e24_url="http://$_m08_e24_h.$_M08P_ZONE:9283/metrics"
  _m08_e24_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "$_m08_e24_url" 2>/dev/null || true)"
  if [[ "$_m08_e24_code" == 200 ]] \
      && curl -s --max-time "$WB_TIMEOUT" "$_m08_e24_url" 2>/dev/null | grep -q '^ceph_health_status'; then
    _m08_e24_actifs=$((_m08_e24_actifs + 1))
  elif grep -qx "$_m08_e24_h" <<<"$_m08_e24_hotes_mgr" && [[ ! "$_m08_e24_code" =~ ^[45][0-9][0-9]$ ]]; then
    _m08_e24_attente_ok=0
  fi
done
check_output "exactement un hôte sert les métriques du cluster sur 9283" '^1$' echo "$_m08_e24_actifs"
check_output "les mgr en attente répondent 4xx/5xx (pas de 200 vide)" '^1$' echo "$_m08_e24_attente_ok"

title "Unités systemd de la sonde (adm01)"
_m08_e24_svc=ms-verif-ceph.service
_m08_e24_tim=ms-verif-ceph.timer
check_output "le service est de type oneshot" '^Type=oneshot$' systemctl show -p Type "$_m08_e24_svc"
check_output "le service tourne en admin" '^User=admin$' systemctl show -p User "$_m08_e24_svc"
check_output "le service déclenche ms-alerte@… en cas d'échec" '^OnFailure=.*ms-alerte@' \
  systemctl show -p OnFailure "$_m08_e24_svc"
check_output "le service exécute la copie installée sous /usr/local" 'path=/usr/local/' \
  systemctl show -p ExecStart "$_m08_e24_svc"
check_cmd "le timer est activé" systemctl is-enabled --quiet "$_m08_e24_tim"
check_cmd "le timer est actif" systemctl is-active --quiet "$_m08_e24_tim"
check_output "le timer passe toutes les 5 minutes" 'OnCalendar=\*-\*-\* \*:(00|0)/5(:00)?' \
  systemctl show -p TimersCalendar "$_m08_e24_tim"
check_output "le timer rattrape une échéance manquée (Persistent)" '^Persistent=yes$' \
  systemctl show -p Persistent "$_m08_e24_tim"
check_output "la chaîne d'alerte a été testée (alerte ms-alerte sur ce service, 30 jours)" \
  "(ÉCHEC|ECHEC) $_m08_e24_svc" sudo -n journalctl -q --no-pager --since -30d -t ms-alerte -o cat

title "La sonde, maintenant"
check_cmd "la configuration de la sonde est installée" test -r /usr/local/etc/ms-verif-ceph.conf
check_cmd "la sonde conclut que le cluster va bien (code 0)" timeout 180 /usr/local/bin/ms-verif-ceph --quiet
check_output "un seuil de remplissage de 0 % la fait échouer (code 1)" '^1$' \
  bash -c 'timeout 180 /usr/local/bin/ms-verif-ceph --quiet --seuil-pool 0 >/dev/null 2>&1; echo $?'
check_output "une option inconnue donne le code 2" '^2$' \
  bash -c 'timeout 30 /usr/local/bin/ms-verif-ceph --nimporte-quoi >/dev/null 2>&1; echo $?'
_m08_e24_bats() { [[ -n "$(_m08p_fichier_main plateforme/outils tests/bats/ms-verif-ceph.bats 2>/dev/null)" ]]; }
check_cmd "plateforme/outils : tests bats de ms-verif-ceph sur main" _m08_e24_bats
check_cmd "plateforme/outils : un job bats a réussi sur main" _m08p_job_reussi plateforme/outils bats

title "Tableau de bord"
if [[ -z "$_m08_e24_hotes_mgr" ]]; then
  check_cmd "hôtes portant un mgr (orchestrateur)" false
fi
while read -r _m08_e24_h; do
  [[ -n "$_m08_e24_h" ]] || continue
  check_cmd "$_m08_e24_h:8443 : certificat de la PKI MédiSphère, au nom de l'hôte, ≤ 31 jours, > 10 jours restants" \
    _m08p_cert "$_m08_e24_h.$_M08P_ZONE" 8443 10
done <<<"$_m08_e24_hotes_mgr"
if [[ -n "${WB_MOI:-}" ]]; then
  check_cmd "compte $WB_MOI du tableau de bord : seul rôle read-only" bash -c \
    'jq -e "(.roles // []) == [\"read-only\"]" >/dev/null <<<"$1"' _ "$(_m08p_json "dashboard ac-user-show $WB_MOI")"
else
  check_cmd "WB_MOI renseigné dans lab/lab.env (compte personnel du tableau de bord)" false
fi

title "Hygiène de la santé"
check_cmd "aucun plantage non acquitté (ceph crash ls-new)" \
  bash -c 'jq -e "length == 0" >/dev/null <<<"$1"' _ "$(_m08p_json 'crash ls-new')"
check_cmd "aucune mise en sourdine permanente ou sans durée" _m08p_sourdines_temporaires
