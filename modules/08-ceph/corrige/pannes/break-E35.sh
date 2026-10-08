# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M08-E35 « Panne : un OSD a disparu »
#
# Cible : un OSD tiré au hasard sur ceph01-03 (mémorisé dans ~/.local/state/workbook/M08-E35/cible).
# Variantes :
#   1. démon de l'OSD arrêté et son unité systemd MASQUÉE (« ceph orch daemon start » échoue ensuite) ;
#   2. disque de l'OSD mis hors ligne côté invité (echo offline > /sys/block/sdX/device/state), puis
#      une petite écriture de test (ceph tell osd.N bench) fait tomber l'OSD sur erreur d'E/S ; le
#      disque n'est ni détaché de la VM ni effacé ;
#   3. OSD marqué « out » discrètement (il reste up, ses PG partent ailleurs, la santé redevient OK).
# Aucune donnée détruite : pas de purge, pas de zap, pas de destroy. Annulation : démasque et relance
# le démon, remet le disque en état « running », remet l'OSD « in » — seulement si c'est encore cassé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m08-commun.sh
source "$WB_ROOT/modules/08-ceph/corrige/pannes/_m08-commun.sh"

# _e35_champ ID CHAMP — up ou in d'un OSD (0/1), lu dans « ceph osd dump ».
_e35_champ() {
  m08_ceph osd dump -f json 2>/dev/null | jq -r --argjson i "$1" --arg c "$2" '.osds[] | select(.osd == $i) | .[$c]' 2>/dev/null
}
_e35_down() { [[ "$(_e35_champ "$1" up)" == 0 ]]; }
_e35_out() { [[ "$(_e35_champ "$1" in)" == 0 ]]; }

# _e35_choisir AVEC_DISQUE — choisit un OSD (« id hôte périphérique ») sur ceph01-03.
_e35_choisir() {
  local l
  l="$(m08_osd_infos 2>/dev/null | awk -v d="$1" '
    $2 ~ /^ceph0[123]$/ && (d == "" || $3 ~ /^sd[a-z]+$/)' | shuf -n 1)"
  [[ -n "$l" ]] || return 1
  printf '%s\n' "$l"
}

_mE35_une() {
  local n="$1" cible id h dev rc=0
  if [[ "$n" == 2 ]]; then cible="$(_e35_choisir disque)" || return 10; else cible="$(_e35_choisir "")" || return 10; fi
  read -r id h dev <<<"$cible"
  case "$n" in
    1)
      m08_arreter "$h" "osd.$id" masquer >/dev/null || return $?
      m08_attendre 90 _e35_down "$id" || { _e35_defaire 1 "$id" "$h" "$dev"; return 10; }
      ;;
    2)
      m08_wb_exec "$h" DEV="$dev" ID="$id" >/dev/null <<'EOF' || rc=$?
f="/sys/block/$DEV/device/state"
[ -w "$f" ] && [ "$(cat "$f")" = running ] || exit 10
# Le disque doit bien porter cet OSD (LVM de ceph-volume) : sinon, variante sans effet.
lsblk -nro NAME "/dev/$DEV" | grep -q 'ceph--' || exit 10
echo offline >"$f"
journal "disque /dev/$DEV (osd.$ID) mis hors ligne côté invité (sysfs), rien n'est détaché ni effacé"
EOF
      ((rc == 0)) || return "$rc"
      # Une petite écriture directe dans le magasin de l'OSD provoque l'erreur d'E/S.
      m08_ceph tell "osd.$id" bench 4194304 4096 >/dev/null 2>&1 || true
      m08_attendre 150 _e35_down "$id" || { _e35_defaire 2 "$id" "$h" "$dev"; return 10; }
      ;;
    3)
      m08_ceph osd out "$id" >/dev/null 2>&1 || return 1
      m08_attendre 30 _e35_out "$id" || { _e35_defaire 3 "$id" "$h" "$dev"; return 10; }
      ;;
  esac
  m08_ecrire E35 cible "$id $h $dev"
  m08_journal E35 "variante $n posée sur osd.$id ($h, $dev)"
}

# _e35_defaire N ID HÔTE PÉRIPHÉRIQUE — retire la variante N si elle est encore en place.
_e35_defaire() {
  local n="$1" id="$2" h="$3" dev="$4"
  case "$n" in
    1)
      m08_relancer "$h" "osd.$id" >/dev/null
      ;;
    2)
      m08_wb_exec "$h" DEV="$dev" ID="$id" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (disque $dev)"
f="/sys/block/$DEV/device/state"
if [ -w "$f" ] && [ "$(cat "$f")" = offline ]; then
  echo running >"$f"
  journal "annulation : /dev/$DEV remis en état running"
fi
u="$(unite_ "osd.$ID")"
if ! systemctl is-active -q "$u"; then
  systemctl reset-failed "$u" >/dev/null 2>&1 || true
  systemctl restart "$u" && journal "annulation : $u relancée"
fi
EOF
      ;;
    3)
      if _e35_out "$id"; then
        m08_ceph osd in "$id" >/dev/null 2>&1 || wb_avert "annulation : osd.$id non remis « in »"
      fi
      ;;
  esac
}

_e35_injecter() {
  m08_preparer || return 1
  m08_essayer E35 3 "$1"
}

panne_E35_v1() { _e35_injecter 1; }
panne_E35_v2() { _e35_injecter 2; }
panne_E35_v3() { _e35_injecter 3; }

verifier_E35() {
  local id h dev
  read -r id h dev <<<"$(m08_lire E35 cible)"
  [[ -n "${id:-}" ]] || return 1
  case "$WB_VAR" in
    3) _e35_out "$id" ;;
    *) _e35_down "$id" ;;
  esac
}

annuler_E35() {
  local id h dev
  read -r id h dev <<<"$(m08_lire E35 cible)"
  if [[ -n "${id:-}" ]]; then
    case "${WB_VAR:-}" in
      1 | 2 | 3) _e35_defaire "$WB_VAR" "$id" "$h" "$dev" ;;
      *) _e35_defaire 2 "$id" "$h" "$dev"; _e35_defaire 1 "$id" "$h" "$dev"; _e35_defaire 3 "$id" "$h" "$dev" ;;
    esac
    m08_journal E35 "annulation (osd.$id)"
  fi
  m08_oublier E35 cible
}

resume_E35() {
  case "${WB_VAR:-}" in
    3) echo "La capacité utile du cluster a baissé et un OSD n'a plus aucun PG, sans alerte rouge." ;;
    *) echo "ceph-par1 est en HEALTH_WARN : un OSD est « down » (un disque a disparu)." ;;
  esac
}

symptome_E35() {
  case "${WB_VAR:-}" in
    3)
      wb_symptome "Ticket INC-3541 — De : Nadia Roussel" \
        "Le rapport de capacité de ce matin montre une baisse de la capacité utile de ceph-par1," \
        "et sur le tableau de bord un des OSD n'a plus aucun PG. Pourtant aucune alerte rouge :" \
        "la santé est revenue à HEALTH_OK après un moment de récupération dans la nuit. Personne" \
        "n'a remplacé de disque. Explique-moi ce qui s'est passé avant qu'on commande du matériel." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 08 35"
      ;;
    *)
      wb_symptome "Ticket INC-3541 — De : Nadia Roussel" \
        "Alerte de 3 h 12 : ceph-par1 en HEALTH_WARN, « 1 osds down ». Les applications répondent" \
        "encore, mais le cluster est en mode dégradé. Lucas propose de « purger l'OSD et de le" \
        "recréer » : n'en fais rien avant d'avoir compris ce qui est arrivé à ce disque. Si l'OSD" \
        "peut revenir sans perte, fais-le revenir ; sinon, dis-moi ce qu'il faut remplacer." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 08 35"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 08 E35 3 "$@"; }
fi
