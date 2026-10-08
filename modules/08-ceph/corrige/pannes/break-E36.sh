# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M08-E36 « Panne : des PG restent inactifs »
#
# Pool visé : rbd-test (il porte l'image témoin rbd-test/sonde montée sur cephcli01:/mnt/sonde).
# Variantes :
#   1. « quatre copies pour les données de santé » : size 4 et min_size 4 sur un cluster de trois
#      hôtes avec un domaine de panne « host » → au plus trois copies placées, moins que min_size
#      → PG undersized+peered, inactifs ;
#   2. « essai de classe nvme » : un OSD (un seul) reçoit la classe nvme, une règle regle-nvme
#      (réplication, domaine host, classe nvme) est créée et le pool y est basculé → une seule copie
#      possible, moins que min_size → PG inactifs ;
#   3. « préparation de PAR2 » : une racine CRUSH vide par2 et une règle regle-par2 sont créées, le
#      pool y est basculé → CRUSH ne trouve aucun OSD → PG sans OSD (unknown/stale), inactifs.
# Rien n'est effacé : les données restent sur les OSD d'origine tant que les PG ne sont pas actifs
# ailleurs. Valeurs d'origine (size, min_size, règle du pool, classe de l'OSD) sauvegardées dans
# ~/.local/state/workbook/M08-E36/ ; l'annulation ne rétablit que ce qui porte encore la panne.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m08-commun.sh
source "$WB_ROOT/modules/08-ceph/corrige/pannes/_m08-commun.sh"

# _e36_pool CHAMP — size, min_size ou crush_rule (nom) du pool rbd-test.
_e36_pool() {
  m08_ceph osd pool get "$_M08_POOL" "$1" -f json 2>/dev/null | jq -r --arg c "$1" '.[$c]' 2>/dev/null
}

# _e36_inactifs — 0 si au moins un PG du pool n'est pas actif (ou n'a plus d'état connu).
_e36_inactifs() {
  m08_ceph health detail -f json 2>/dev/null | jq -e '.checks | has("PG_AVAILABILITY")' >/dev/null 2>&1
}

_mE36_une() {
  local n="$1" osd classe
  m08_ecrire E36 size "$(_e36_pool size)"
  m08_ecrire E36 min_size "$(_e36_pool min_size)"
  m08_ecrire E36 regle "$(_e36_pool crush_rule)"
  [[ -n "$(m08_lire E36 regle)" && -n "$(m08_lire E36 size)" ]] || return 1
  case "$n" in
    1)
      m08_ceph osd pool set "$_M08_POOL" size 4 >/dev/null 2>&1 || return 10
      m08_ceph osd pool set "$_M08_POOL" min_size 4 >/dev/null 2>&1 || { _e36_defaire 1; return 10; }
      ;;
    2)
      # Un OSD de ceph03 (ou d'un autre nœud) passe en classe nvme.
      osd="$(m08_admin <<'EOF'
ceph_ osd metadata -f json | py_ '
import random
c = [m["id"] for m in d if m.get("hostname") in ("ceph01", "ceph02", "ceph03")]
print(random.choice(c) if c else "")'
EOF
      )"
      [[ -n "${osd:-}" ]] || return 10
      classe="$(m08_ceph osd crush get-device-class "osd.$osd" 2>/dev/null | tr -d '[:space:]')"
      [[ -n "$classe" && "$classe" != nvme ]] || return 10
      m08_ecrire E36 osd "$osd"
      m08_ecrire E36 classe "$classe"
      m08_ceph osd crush rm-device-class "osd.$osd" >/dev/null 2>&1 || return 1
      m08_ceph osd crush set-device-class nvme "osd.$osd" >/dev/null 2>&1 || { _e36_defaire 2; return 1; }
      if ! m08_ceph osd crush rule ls 2>/dev/null | grep -qx regle-nvme; then
        m08_ceph osd crush rule create-replicated regle-nvme default host nvme >/dev/null 2>&1 || { _e36_defaire 2; return 10; }
        m08_ecrire E36 regle_creee regle-nvme
      fi
      m08_ceph osd pool set "$_M08_POOL" crush_rule regle-nvme >/dev/null 2>&1 || { _e36_defaire 2; return 10; }
      ;;
    3)
      if ! m08_ceph osd crush ls par2 >/dev/null 2>&1; then
        m08_ceph osd crush add-bucket par2 root >/dev/null 2>&1 || return 10
        m08_ecrire E36 racine_creee par2
      fi
      if ! m08_ceph osd crush rule ls 2>/dev/null | grep -qx regle-par2; then
        m08_ceph osd crush rule create-replicated regle-par2 par2 host >/dev/null 2>&1 || { _e36_defaire 3; return 10; }
        m08_ecrire E36 regle_creee regle-par2
      fi
      m08_ceph osd pool set "$_M08_POOL" crush_rule regle-par2 >/dev/null 2>&1 || { _e36_defaire 3; return 10; }
      ;;
  esac
  if ! m08_attendre 90 _e36_inactifs; then
    _e36_defaire "$n"
    return 10
  fi
  m08_journal E36 "variante $n posée sur le pool $_M08_POOL"
}

# _e36_defaire N — retire la variante N (seulement ce qui porte encore la marque de la panne).
_e36_defaire() {
  local regle size min osd classe creee racine
  regle="$(m08_lire E36 regle)"
  size="$(m08_lire E36 size)"
  min="$(m08_lire E36 min_size)"
  case "$1" in
    1)
      # min_size d'abord (valeur d'origine ≤ 4, jamais en dessous), puis size.
      if [[ "$(_e36_pool min_size)" == 4 && -n "$min" ]]; then
        m08_ceph osd pool set "$_M08_POOL" min_size "$min" >/dev/null 2>&1 || wb_avert "annulation : min_size de $_M08_POOL non rétabli"
      fi
      if [[ "$(_e36_pool size)" == 4 && -n "$size" ]]; then
        m08_ceph osd pool set "$_M08_POOL" size "$size" >/dev/null 2>&1 || wb_avert "annulation : size de $_M08_POOL non rétabli"
        # Selon la version, changer size recalcule min_size : on le remet à sa valeur d'origine.
        if [[ -n "$min" && "$(_e36_pool min_size)" != "$min" ]]; then
          m08_ceph osd pool set "$_M08_POOL" min_size "$min" >/dev/null 2>&1 || true
        fi
      fi
      ;;
    2 | 3)
      creee="$(m08_lire E36 regle_creee)"
      local fautive="regle-nvme"
      if [[ "$1" == 3 ]]; then fautive="regle-par2"; fi
      if [[ "$(_e36_pool crush_rule)" == "$fautive" && -n "$regle" ]]; then
        m08_ceph osd pool set "$_M08_POOL" crush_rule "$regle" >/dev/null 2>&1 || wb_avert "annulation : règle de $_M08_POOL non rétablie"
      fi
      # Règle supprimée seulement si elle a été créée par la panne et que plus aucun pool ne l'utilise.
      if [[ "$creee" == "$fautive" ]] && ! m08_ceph osd pool ls detail 2>/dev/null | grep -q "crush_rule $(m08_ceph osd crush rule dump "$fautive" -f json 2>/dev/null | jq -r '.rule_id' 2>/dev/null) "; then
        m08_ceph osd crush rule rm "$fautive" >/dev/null 2>&1 || true
      fi
      if [[ "$1" == 2 ]]; then
        osd="$(m08_lire E36 osd)"
        classe="$(m08_lire E36 classe)"
        if [[ -n "$osd" && -n "$classe" && "$(m08_ceph osd crush get-device-class "osd.$osd" 2>/dev/null | tr -d '[:space:]')" == nvme ]]; then
          m08_ceph osd crush rm-device-class "osd.$osd" >/dev/null 2>&1 || true
          m08_ceph osd crush set-device-class "$classe" "osd.$osd" >/dev/null 2>&1 || wb_avert "annulation : classe de osd.$osd non rétablie ($classe)"
        fi
      else
        racine="$(m08_lire E36 racine_creee)"
        # Racine supprimée seulement si elle est vide (crush ls ne liste rien) et créée par la panne.
        if [[ "$racine" == par2 && -z "$(m08_ceph osd crush ls par2 2>/dev/null)" ]]; then
          m08_ceph osd crush rm par2 >/dev/null 2>&1 || true
        fi
      fi
      ;;
  esac
}

_e36_injecter() {
  m08_preparer || return 1
  m08_essayer E36 3 "$1"
}

panne_E36_v1() { _e36_injecter 1; }
panne_E36_v2() { _e36_injecter 2; }
panne_E36_v3() { _e36_injecter 3; }

verifier_E36() { _e36_inactifs; }

annuler_E36() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e36_defaire "$WB_VAR" ;;
    *) _e36_defaire 1; _e36_defaire 2; _e36_defaire 3 ;;
  esac
  m08_journal E36 "annulation"
  rm -rf -- "$(m08_etat E36)"
}

resume_E36() {
  echo "Les écritures sur /mnt/sonde (pool rbd-test) restent bloquées ; ceph -s parle de PG inactifs."
}

symptome_E36() {
  wb_symptome "Ticket INC-3542 — De : Julien Petit" \
    "Depuis ce matin, toute écriture sur le volume RBD de test de cephcli01 (/mnt/sonde, image" \
    "rbd-test/sonde) reste bloquée : pas d'erreur, rien ne bouge. « sudo wb-sonde-stockage » le" \
    "confirme. Lucas dit avoir « appliqué la nouvelle politique de stockage » sur ce pool hier soir." \
    "ceph -s parle de PG inactifs. Remets le pool en service sans perdre une seule donnée," \
    "puis dis-moi ce qu'il fallait faire pour appliquer proprement ce que Lucas voulait." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 08 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 08 E36 3 "$@"; }
fi
