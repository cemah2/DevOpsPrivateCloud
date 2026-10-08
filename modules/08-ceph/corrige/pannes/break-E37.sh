# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M08-E37 « Panne : plus aucune écriture »
#
# Variantes :
#   1. seuils de remplissage abaissés (nearfull, backfillfull, full) sous l'occupation réelle du
#      moins rempli des OSD → tous les OSD « full », le cluster refuse les écritures ;
#   2. quota du pool rbd-test (max_bytes) fixé à la moitié de ce qu'il contient déjà → POOL_FULL ;
#   3. drapeaux de maintenance oubliés : noout et pause (pauserd + pausewr) → plus aucune E/S client.
# Aucune donnée n'est effacée ; valeurs d'origine (ratios, quota, drapeaux déjà posés) sauvegardées
# dans ~/.local/state/workbook/M08-E37/. L'annulation ne rétablit que ce qui porte encore la panne.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m08-commun.sh
source "$WB_ROOT/modules/08-ceph/corrige/pannes/_m08-commun.sh"

_e37_dump() { m08_ceph osd dump -f json 2>/dev/null; }

# _e37_sante CODE — 0 si le contrôle de santé CODE (OSD_FULL, POOL_FULL, OSDMAP_FLAGS…) est présent.
_e37_sante() {
  m08_ceph health detail -f json 2>/dev/null | jq -e --arg c "$1" '.checks | has($c)' >/dev/null 2>&1
}

_mE37_une() {
  local n="$1" d u full q
  d="$(_e37_dump)"
  [[ -n "$d" ]] || return 1
  case "$n" in
    1)
      m08_ecrire E37 ratios "$(jq -r '"\(.nearfull_ratio) \(.backfillfull_ratio) \(.full_ratio)"' <<<"$d")"
      # Occupation (en %) du moins rempli des OSD up et in.
      u="$(m08_ceph osd df -f json 2>/dev/null | jq -r '[.nodes[] | select(.kb > 0) | .utilization] | min // empty')"
      [[ -n "$u" ]] || return 10
      # Il faut une occupation mesurable (> 0,2 %) pour poser un seuil strictement en dessous.
      full="$(awk -v u="$u" 'BEGIN { if (u < 0.2) exit 1; printf "%.4f", u / 100 * 0.6 }')" || return 10
      m08_ceph osd set-nearfull-ratio "$(awk -v f="$full" 'BEGIN { printf "%.4f", f * 0.8 }')" >/dev/null 2>&1 || return 1
      m08_ceph osd set-backfillfull-ratio "$(awk -v f="$full" 'BEGIN { printf "%.4f", f * 0.9 }')" >/dev/null 2>&1 || { _e37_defaire 1; return 1; }
      m08_ceph osd set-full-ratio "$full" >/dev/null 2>&1 || { _e37_defaire 1; return 1; }
      m08_attendre 90 _e37_sante OSD_FULL || { _e37_defaire 1; return 10; }
      ;;
    2)
      q="$(m08_ceph osd pool get-quota "$_M08_POOL" -f json 2>/dev/null)"
      [[ -n "$q" ]] || return 1
      m08_ecrire E37 quota "$(jq -r '"\(.quota_max_bytes) \(.quota_max_objects)"' <<<"$q")"
      u="$(m08_ceph df detail -f json 2>/dev/null | jq -r --arg p "$_M08_POOL" '.pools[] | select(.name == $p) | .stats.stored')"
      [[ "${u:-0}" =~ ^[0-9]+$ ]] && ((u > 2097152)) || return 10
      m08_ceph osd pool set-quota "$_M08_POOL" max_bytes "$((u / 2))" >/dev/null 2>&1 || return 1
      m08_ecrire E37 quota_pose "$((u / 2))"
      m08_attendre 90 _e37_sante POOL_FULL || { _e37_defaire 2; return 10; }
      ;;
    3)
      m08_ecrire E37 drapeaux "$(jq -r '.flags' <<<"$d")"
      m08_ceph osd set noout >/dev/null 2>&1 || return 1
      m08_ceph osd set pause >/dev/null 2>&1 || { _e37_defaire 3; return 1; }
      m08_attendre 30 _e37_pause || { _e37_defaire 3; return 10; }
      ;;
  esac
  m08_journal E37 "variante $n posée"
}

_e37_pause() { _e37_dump | jq -e '.flags | split(",") | index("pausewr")' >/dev/null 2>&1; }

# _e37_defaire N — retire la variante N si elle est encore en place.
_e37_defaire() {
  local d near bf full mb pose avant
  d="$(_e37_dump)"
  case "$1" in
    1)
      read -r near bf full <<<"$(m08_lire E37 ratios)"
      [[ -n "${full:-}" ]] || return 0
      # Seuil encore anormalement bas (< 50 %) : c'est celui de la panne.
      if awk -v f="$(jq -r '.full_ratio' <<<"$d")" 'BEGIN { exit !(f < 0.5) }'; then
        m08_ceph osd set-full-ratio "$full" >/dev/null 2>&1 || wb_avert "annulation : full_ratio non rétabli"
      fi
      if awk -v f="$(jq -r '.backfillfull_ratio' <<<"$d")" 'BEGIN { exit !(f < 0.5) }'; then
        m08_ceph osd set-backfillfull-ratio "$bf" >/dev/null 2>&1 || true
      fi
      if awk -v f="$(jq -r '.nearfull_ratio' <<<"$d")" 'BEGIN { exit !(f < 0.5) }'; then
        m08_ceph osd set-nearfull-ratio "$near" >/dev/null 2>&1 || true
      fi
      ;;
    2)
      read -r mb _ <<<"$(m08_lire E37 quota)"
      pose="$(m08_lire E37 quota_pose)"
      [[ -n "${pose:-}" ]] || return 0
      if [[ "$(m08_ceph osd pool get-quota "$_M08_POOL" -f json 2>/dev/null | jq -r '.quota_max_bytes')" == "$pose" ]]; then
        m08_ceph osd pool set-quota "$_M08_POOL" max_bytes "${mb:-0}" >/dev/null 2>&1 || wb_avert "annulation : quota de $_M08_POOL non rétabli"
      fi
      ;;
    3)
      avant="$(m08_lire E37 drapeaux)"
      # Drapeau retiré seulement s'il n'était pas déjà posé avant la panne.
      if [[ ",$avant," != *",pausewr,"* ]] && jq -e '.flags | split(",") | index("pausewr")' >/dev/null 2>&1 <<<"$d"; then
        m08_ceph osd unset pause >/dev/null 2>&1 || wb_avert "annulation : drapeau pause non retiré"
      fi
      if [[ ",$avant," != *",noout,"* ]] && jq -e '.flags | split(",") | index("noout")' >/dev/null 2>&1 <<<"$d"; then
        m08_ceph osd unset noout >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

_e37_injecter() {
  m08_preparer || return 1
  m08_essayer E37 3 "$1"
}

panne_E37_v1() { _e37_injecter 1; }
panne_E37_v2() { _e37_injecter 2; }
panne_E37_v3() { _e37_injecter 3; }

verifier_E37() {
  case "$WB_VAR" in
    1) _e37_sante OSD_FULL ;;
    2) _e37_sante POOL_FULL ;;
    *) _e37_pause ;;
  esac
}

annuler_E37() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e37_defaire "$WB_VAR" ;;
    *) _e37_defaire 3; _e37_defaire 2; _e37_defaire 1 ;;
  esac
  m08_journal E37 "annulation"
  rm -rf -- "$(m08_etat E37)"
}

resume_E37() {
  echo "Plus aucune écriture ne passe sur le stockage de test (la sonde de cephcli01 reste bloquée)."
}

symptome_E37() {
  wb_symptome "Ticket INC-3543 — De : Nadia Roussel" \
    "Les écritures sur le stockage de test sont bloquées depuis 20 minutes : la sonde de cephcli01" \
    "(« sudo wb-sonde-stockage ») reste sans réponse, sans message d'erreur côté client. Karim a" \
    "fait une intervention de maintenance cette nuit et dit avoir « tout remis comme avant »." \
    "Rétablis les écritures, et dis-moi si on risque que ça recommence demain." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 08 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 08 E37 3 "$@"; }
fi
