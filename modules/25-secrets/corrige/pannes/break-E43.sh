# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M25-E43 « Astreinte : la nuit où le coffre s'est fermé »
#
# Tire TROIS pannes distinctes : UNE qui touche le coffre lui-même (parmi M25-E35, E39, E42) et DEUX qui
# touchent ses consommateurs (parmi M25-E36, E37, E38, E40, E41), variante de chacune au hasard. Réutilise
# panne_EXX_vN / verifier_EXX / annuler_EXX / resume_EXX des autres scripts, chargés en mode
# bibliothèque (WB_PANNES_LIB=1). Un script de panne absent est simplement écarté du tirage.
#
#   --variante N  force le trio n° N (ordre de _E43_trios) ; les sous-variantes restent aléatoires.
#   --annuler     annule les trois pannes (et toute panne M25-E35 à E42 encore marquée active).
#
# Règles :
#   - jamais deux pannes de coffre ensemble (E35, E39 et E42 arrêtent ou scellent chacune un nœud ;
#     ensemble, elles feraient perdre le quorum ou laisseraient la grappe sans marge) ;
#   - grappe saine avant tout (un actif, deux en attente, kms01 descellé), vérifiée une fois ;
#   - ordre d'injection : consommateurs d'abord (ils exigent un coffre sain pour se poser), coffre en
#     dernier ; annulation dans l'ordre inverse (coffre d'abord) ;
#   - E42 sans BAO_KMS_TOKEN : variantes 1 et 4 seulement (e42_variantes).

_WB_E43_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m25-commun.sh
source "$WB_ROOT/modules/25-secrets/corrige/pannes/_m25-commun.sh"

# shellcheck disable=SC2034  # lu par les scripts break-EXX.sh sourcés (ils ne définissent pas main)
WB_PANNES_LIB=1
_E43_PRESENTS=()
for _e in E35 E36 E37 E38 E39 E40 E41 E42; do
  if [[ -f "$_WB_E43_DIR/break-$_e.sh" ]]; then
    # shellcheck disable=SC1090
    source "$_WB_E43_DIR/break-$_e.sh"
    _E43_PRESENTS+=("$_e")
  fi
done
unset WB_PANNES_LIB _e

_E43_COFFRE=(E35 E39 E42)
_E43_CONSO=(E36 E37 E38 E40 E41)

_e43_present() { [[ " ${_E43_PRESENTS[*]} " == *" $1 "* ]] && declare -F "panne_$1_v1" >/dev/null; }

# _e43_variantes EXX — numéros de variantes utilisables pour EXX.
_e43_variantes() {
  if [[ "$1" == E42 ]] && declare -F e42_variantes >/dev/null; then e42_variantes; return; fi
  compgen -A function | sed -n "s/^panne_$1_v\([0-9][0-9]*\)$/\1/p" | sort -n | tr '\n' ' '
}

# _E43_trios — trios admis (un coffre, deux consommateurs), un par ligne.
_E43_trios() {
  local c i j
  for c in "${_E43_COFFRE[@]}"; do
    _e43_present "$c" || continue
    for ((i = 0; i < ${#_E43_CONSO[@]}; i++)); do
      _e43_present "${_E43_CONSO[i]}" || continue
      for ((j = i + 1; j < ${#_E43_CONSO[@]}; j++)); do
        _e43_present "${_E43_CONSO[j]}" || continue
        printf '%s %s %s\n' "${_E43_CONSO[i]}" "${_E43_CONSO[j]}" "$c"
      done
    done
  done
}

_E43_annuler() {
  local liste ex var i
  liste="$(wb_marqueur_lire M25-E43)"
  local -a ordre=(E35 E39 E42 E41 E40 E38 E37 E36) actives=()
  for ex in "${ordre[@]}"; do
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M25-$ex"; then actives+=("$ex"); fi
  done
  for ((i = 0; i < ${#actives[@]}; i++)); do
    ex="${actives[i]}"
    declare -F "annuler_$ex" >/dev/null || continue
    var="$(wb_marqueur_lire "M25-$ex")"
    [[ -n "$var" ]] || var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    WB_EX="M25-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M25-$ex"
  done
  wb_marqueur_suppr M25-E43
  echo "Astreinte M25-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 25 43"
}

main() {
  local trio="" annuler=0
  while (($#)); do
    case "$1" in
      --variante)
        if (($# < 2)); then echo "--variante attend un numéro" >&2; return 2; fi
        trio="$2"; shift 2 ;;
      --variante=*) trio="${1#*=}"; shift ;;
      --annuler) annuler=1; shift ;;
      *) echo "Option inconnue : $1 (attendu : --variante N, --annuler)" >&2; return 2 ;;
    esac
  done

  if ((annuler)); then
    _E43_annuler
    return 0
  fi

  local ex
  for ex in E43 E35 E36 E37 E38 E39 E40 E41 E42; do
    if wb_marqueur_existe "M25-$ex"; then
      echo "Une panne M25-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done

  local -a trios
  mapfile -t trios < <(_E43_trios)
  if ((${#trios[@]} == 0)); then
    echo "Aucun trio de pannes disponible (scripts de M25-E35 à E42 absents ?)." >&2
    return 1
  fi
  if [[ -z "$trio" ]]; then trio=$((RANDOM % ${#trios[@]} + 1)); fi
  if ! [[ "$trio" =~ ^[0-9]+$ ]] || ((trio < 1 || trio > ${#trios[@]})); then
    echo "Variante invalide : $trio (1 à ${#trios[@]})" >&2
    return 2
  fi

  echo "Injection en cours (trois pannes ; compte 5 à 15 minutes)…"
  WB_EX=M25-E43
  WB_VAR=0
  m25_grappe_saine || { echo "Coffre pas sain avant l'astreinte (un actif, deux en attente, kms01 descellé) : rien n'est cassé." >&2; return 1; }
  m25_jeton_charger || { echo "Jeton plateforme-admin requis (bao login -method=oidc) : rien n'est cassé." >&2; return 1; }
  wb_marqueur_ecrire M25-E43 ""

  local -a choisies=() lignes=() vs
  local liste="" v
  # Ordre du trio : consommateurs puis coffre.
  for ex in ${trios[trio - 1]}; do
    read -r -a vs <<<"$(_e43_variantes "$ex")"
    ((${#vs[@]} > 0)) || { echo "Aucune variante utilisable pour $ex : remise en état." >&2; _E43_annuler >/dev/null; return 1; }
    v="${vs[RANDOM % ${#vs[@]}]}"
    WB_EX="M25-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible (lab pas sain ?) : remise en état, rien n'est cassé." >&2
      wb_marqueur_ecrire "M25-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M25-E43 "$liste"
      _E43_annuler >/dev/null
      return 1
    fi
    wb_marqueur_ecrire "M25-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M25-E43 "$liste"
    if declare -F "verifier_$ex" >/dev/null && ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      _E43_annuler >/dev/null
      return 1
    fi
    choisies+=("$ex")
  done

  for ex in "${choisies[@]}"; do
    WB_EX="M25-$ex"
    WB_VAR="$(wb_marqueur_lire "M25-$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-5243 — De : Nadia Roussel (responsable astreinte) — priorité P1" \
    "Nuit de vendredi à samedi, 2 h 10. Plusieurs alertes et tickets autour du coffre en quelques minutes :" \
    "${lignes[@]}" \
    "À 7 h les centres de santé ouvrent les rendez-vous : coffre complet et consommateurs rétablis d'ici là," \
    "sans réveiller trois dépositaires si on peut l'éviter, sans rien ouvrir qu'on regrettera lundi." \
    "Tiens-moi informée toutes les 30 min, puis post-mortem (modules/00-lab/ressources/M00-E46/" \
    "modele-post-mortem.md) et RB-255 « coffre fermé »." \
    "" \
    "Rappel : un nœud à la fois, kms01 jamais scellé ni redémarré, aucune politique élargie pour débloquer." \
    "Temps cible : 2 h (rétablissement) + 45 min (post-mortem et runbook). Contrôle : lab/bin/check 25 43"
}
