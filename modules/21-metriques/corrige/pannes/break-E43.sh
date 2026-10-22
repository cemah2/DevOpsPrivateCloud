# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M21-E43 « Astreinte : une nuit agitée »
#
# Tire TROIS pannes distinctes parmi M21-E35 à M21-E42 (variante de chacune tirée au hasard) et les
# injecte ensemble. Réutilise panne_EXX_vN / verifier_EXX / annuler_EXX / resume_EXX des autres
# scripts, chargés en mode bibliothèque (WB_PANNES_LIB=1).
#
#   --variante N  (1 à 44) force le trio n° N (ordre lexicographique des trios admis) ; les
#                 sous-variantes restent aléatoires.
#   --annuler     annule les trois pannes (et toute panne M21-E35 à E42 encore marquée active).
#
# Règles :
#   - au plus UNE panne parmi E36 et E40 (elles touchent toutes deux la route de l'astreinte et l'état
#     des témoins) ; au plus UNE parmi E38 et E39 (elles chargent toutes deux Prometheus et Thanos) ;
#   - avant la première injection : supervision saine et témoins prêts (une seule fois, puis
#     _M21_ASTREINTE=1 dispense chaque panne de ces contrôles, que la précédente ferait échouer) ;
#   - ordre d'injection : mon01 (E42) d'abord, puis la collecte (E35), les règles (E41), les tableaux
#     (E37), le stockage long (E39, E38), et la chaîne d'alerte (E36, E40) en dernier ; annulation dans
#     l'ordre inverse. Les pannes qui passent par une MR attendent le pipeline et Argo CD : compte
#     15 à 45 minutes d'injection.

_WB_E43_DIR="$(dirname "${BASH_SOURCE[0]}")"
WB_PANNES_LIB=1
# shellcheck source=break-E35.sh
source "$_WB_E43_DIR/break-E35.sh"
# shellcheck source=break-E36.sh
source "$_WB_E43_DIR/break-E36.sh"
# shellcheck source=break-E37.sh
source "$_WB_E43_DIR/break-E37.sh"
# shellcheck source=break-E38.sh
source "$_WB_E43_DIR/break-E38.sh"
# shellcheck source=break-E39.sh
source "$_WB_E43_DIR/break-E39.sh"
# shellcheck source=break-E40.sh
source "$_WB_E43_DIR/break-E40.sh"
# shellcheck source=break-E41.sh
source "$_WB_E43_DIR/break-E41.sh"
# shellcheck source=break-E42.sh
source "$_WB_E43_DIR/break-E42.sh"
unset WB_PANNES_LIB

declare -A _E43_NB=([E35]=5 [E36]=4 [E37]=4 [E38]=3 [E39]=3 [E40]=3 [E41]=3 [E42]=4)
_E43_ORDRE=(E42 E35 E41 E37 E39 E38 E36 E40)
_E43_ORDRE_ANNULATION=(E40 E36 E38 E39 E37 E41 E35 E42)

# _E43_trios — trios admis, un par ligne.
_E43_trios() {
  local -a ex=(E35 E36 E37 E38 E39 E40 E41 E42)
  local i j k t
  for ((i = 0; i < ${#ex[@]}; i++)); do
    for ((j = i + 1; j < ${#ex[@]}; j++)); do
      for ((k = j + 1; k < ${#ex[@]}; k++)); do
        t=" ${ex[i]} ${ex[j]} ${ex[k]} "
        [[ "$t" == *" E36 "* && "$t" == *" E40 "* ]] && continue
        [[ "$t" == *" E38 "* && "$t" == *" E39 "* ]] && continue
        printf '%s %s %s\n' "${ex[i]}" "${ex[j]}" "${ex[k]}"
      done
    done
  done
}

_E43_annuler() {
  local liste ex var
  liste="$(wb_marqueur_lire M21-E43)"
  local -a actives=()
  for ex in "${_E43_ORDRE_ANNULATION[@]}"; do
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M21-$ex"; then
      actives+=("$ex")
    fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M21-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M21-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M21-$ex"
  done
  wb_marqueur_suppr M21-E43
  echo "Astreinte M21-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 21 43"
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
  for ex in E43 "${_E43_ORDRE[@]}"; do
    if wb_marqueur_existe "M21-$ex"; then
      echo "Une panne M21-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done

  local -a trios
  mapfile -t trios < <(_E43_trios)
  if [[ -z "$trio" ]]; then
    trio=$((RANDOM % ${#trios[@]} + 1))
  fi
  if ! [[ "$trio" =~ ^[0-9]+$ ]] || ((trio < 1 || trio > ${#trios[@]})); then
    echo "Variante invalide : $trio (1 à ${#trios[@]})" >&2
    return 2
  fi
  local a b c
  read -r a b c <<<"${trios[trio - 1]}"

  echo "Injection en cours (trois pannes, des MR et des synchronisations : compte 15 à 45 minutes)…"
  WB_EX=M21-E43
  WB_VAR=0
  m21_sain || { echo "Supervision pas saine avant l'astreinte : rien n'est cassé." >&2; return 1; }
  m21_temoins || { echo "Témoins du palier 4 impossibles à préparer : rien n'est cassé." >&2; return 1; }
  wb_marqueur_ecrire M21-E43 ""

  _M21_ASTREINTE=1
  local -a choisies=() lignes=()
  local liste="" v
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" || "$ex" == "$c" ]] || continue
    v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    WB_EX="M21-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible (lab pas sain ?) : remise en état." >&2
      wb_marqueur_ecrire "M21-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M21-E43 "$liste"
      unset _M21_ASTREINTE
      _E43_annuler >/dev/null
      return 1
    fi
    # La fonction de panne a pu basculer sur une autre variante (WB_VAR modifié, m21_essayer).
    wb_marqueur_ecrire "M21-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M21-E43 "$liste"
    if ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      unset _M21_ASTREINTE
      _E43_annuler >/dev/null
      return 1
    fi
    choisies+=("$ex")
  done
  unset _M21_ASTREINTE

  for ex in "${choisies[@]}"; do
    WB_EX="M21-$ex"
    WB_VAR="$(wb_marqueur_lire "M21-$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-4843 — De : Nadia Roussel (responsable astreinte) — priorité P2" \
    "Tu es d'astreinte. Mardi, 3 h 40 : plusieurs remontées sur la supervision :" \
    "${lignes[@]}" \
    "La supervision, c'est ce qui me réveille quand les centres de santé ne peuvent plus prendre" \
    "rendez-vous : à 8 h, elle doit être fiable de bout en bout (collecte, règles, tableaux," \
    "conservation, alertes, témoin). Tiens-moi informée toutes les 30 min, puis rédige le" \
    "post-mortem avec le modèle de l'équipe (modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Rappel : aucune donnée Thanos ne doit être supprimée ; les corrections passent par Git." \
    "Temps cible : 2 h (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 21 43"
}
