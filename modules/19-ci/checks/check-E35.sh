# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E35.sh — M19-E35 « Panne : les jobs restent en attente » : runner k8s-par1 en ligne, actif, avec
# ses étiquettes ; runner protégé réservé aux références protégées ; quota de ci-jobs cohérent ; plus de
# job en attente dans le témoin ; RB-190 complété ; panne close. Lecture seule.

# shellcheck source=_m19-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-expert.sh"

title "M19-E35 — Les jobs démarrent à nouveau"
require_cmd jq kubectl curl

_m19_e35_r="$(_m19x_runner_json 2>/dev/null)" || _m19_e35_r=""
if [[ -z "$_m19_e35_r" ]]; then
  skip "runner $_m19x_runner" "introuvable par l'API (M19-E04)"
else
  check_cmd "runner $_m19x_runner en ligne et non suspendu" \
    jq -e '.status == "online" and (.paused | not)' <<<"$_m19_e35_r"
  check_cmd "runner $_m19x_runner : étiquettes k8s et kubernetes, pas de jobs sans étiquette" \
    jq -e '(.tag_list | index("k8s")) and (.tag_list | index("kubernetes")) and (.run_untagged | not)' <<<"$_m19_e35_r"
  check_cmd "runner $_m19x_runner : aucune note de maintenance laissée par une intervention" \
    jq -e '(.maintenance_note // "") | test("M19-E35") | not' <<<"$_m19_e35_r"
fi
_m19_e35_p="$(_m19x_runner_json "${_m19x_runner}-protege" 2>/dev/null)" || _m19_e35_p=""
if [[ -n "$_m19_e35_p" ]]; then
  check_cmd "runner ${_m19x_runner}-protege : références protégées seulement, étiquette protege, en ligne" \
    jq -e '.access_level == "ref_protected" and (.tag_list | index("protege")) and .status == "online"' <<<"$_m19_e35_p"
else
  skip "runner ${_m19x_runner}-protege" "introuvable (M19-E24)"
fi

if _m19x_api_repond; then
  _m19_e35_quota_ok() {
    kube -n ci-jobs get resourcequota -o json 2>/dev/null | jq -e '
      def mio: if test("Gi$") then (sub("Gi$"; "") | tonumber * 1024) elif test("Mi$") then (sub("Mi$"; "") | tonumber)
               elif test("Ki$") then (sub("Ki$"; "") | tonumber / 1024) else (tonumber / 1048576) end;
      all(.items[]; (.spec.hard // {}) | to_entries | all(
        if (.key | test("^(requests\\.|limits\\.)?memory$")) then (.value | mio) >= 2048
        elif .key == "pods" or .key == "count/pods" then (.value | tonumber) >= 4
        else true end))' >/dev/null 2>&1
  }
  check_cmd "quota de ci-jobs : au moins 2 Gio de mémoire et 4 pods (pas de Mi à la place de Gi)" _m19_e35_quota_ok
else
  skip "quota de ci-jobs" "l'API de k8s-par1 ne répond pas au compte des checks"
fi

if _m19x_temoin_existe; then
  _m19_e35_pending() {
    gitlab_api "projects/$(_m19x_enc "$_m19x_temoin")/jobs?scope[]=pending&per_page=100" 2>/dev/null | jq -e --argjson t "$(date +%s)" '
      [.[] | select(((.created_at | sub("\\.[0-9]+"; "") | sub("(?<z>[+-][0-9]{2}):?[0-9]{2}$"; "Z") | fromdateiso8601)) < ($t - 600))] | length == 0' >/dev/null 2>&1
  }
  check_cmd "témoin $_m19x_temoin : aucun job en attente depuis plus de 10 min (branche de Lucas comprise)" _m19_e35_pending
  check_cmd "témoin $_m19x_temoin : dernier pipeline de main réussi" _m19x_canari_vert
else
  skip "témoin $_m19x_temoin" "absent : il est créé à la première injection (lab/bin/break 19 35)"
fi
_m19_e35_rb() {
  local m
  for m in 'étiquette' 'pause' 'quota' 'protég'; do _m19x_doc_contient 'RB-190*.md' "$m" || return 1; done
}
check_cmd "RB-190 : causes « étiquettes », « pause », « quota » et « runner protégé » traitées" _m19_e35_rb
check_cmd "panne M19-E35 close (lab/bin/break 19 35 --annuler après réparation)" _m19x_aucune_panne_active E35
