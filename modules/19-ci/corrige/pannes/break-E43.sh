# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M19-E43 « Astreinte : la chaîne de livraison en détresse »
#
# Tire TROIS pannes distinctes parmi M19-E35 à M19-E42 (variante de chacune tirée au hasard) et les
# injecte ensemble. Réutilise panne_EXX_vN / verifier_EXX / annuler_EXX / resume_EXX des autres
# scripts, chargés en mode bibliothèque (WB_PANNES_LIB=1).
#
#   --variante N  (1 à 16) force le trio n° N (ordre lexicographique des trios admis) ; les
#                 sous-variantes restent aléatoires.
#   --annuler     annule les trois pannes (et toute panne M19-E35 à E42 encore marquée active).
#
# Règles :
#   - au plus UNE panne parmi E36, E38, E40, E41, E42 : elles modifient toutes soit le gabarit TOML du
#     runner, soit le dépôt témoin, et l'annulation de l'une ne doit pas buter sur l'autre ; E35, E37
#     et E39 se combinent librement (16 trios) ;
#   - avant la première injection : chaîne saine et témoin vert (une seule fois, puis _M19_ASTREINTE=1
#     dispense chaque panne de ces contrôles, que la précédente ferait échouer) ;
#   - ordre d'injection (chaque panne est constatée par un pipeline du témoin ou un job de
#     déploiement, qui ont besoin d'un runner en état : celles qui empêchent les jobs de tourner
#     viennent en dernier) : E39, E37, E40, E38, E42, E36, E35, E41 (E41 variante 4 bloque le compte
#     de Lucas, dont les autres ont besoin) ; annulation dans l'ordre inverse.

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

declare -A _E43_NB=([E35]=4 [E36]=4 [E37]=4 [E38]=4 [E39]=4 [E40]=3 [E41]=4 [E42]=4)
_E43_ORDRE=(E39 E37 E40 E38 E42 E36 E35 E41)
_E43_ORDRE_ANNULATION=(E41 E35 E36 E42 E38 E40 E37 E39)

# _E43_trios — trios admis (au plus un de E36, E38, E40, E41, E42), un par ligne.
_E43_trios() {
  local -a ex=(E35 E36 E37 E38 E39 E40 E41 E42)
  local i j k p e
  for ((i = 0; i < ${#ex[@]}; i++)); do
    for ((j = i + 1; j < ${#ex[@]}; j++)); do
      for ((k = j + 1; k < ${#ex[@]}; k++)); do
        p=0
        for e in "${ex[i]}" "${ex[j]}" "${ex[k]}"; do [[ "$e" =~ ^E(36|38|40|41|42)$ ]] && p=$((p + 1)); done
        ((p <= 1)) && printf '%s %s %s\n' "${ex[i]}" "${ex[j]}" "${ex[k]}"
      done
    done
  done
}

_E43_annuler() {
  local liste ex var
  liste="$(wb_marqueur_lire M19-E43)"
  local -a actives=()
  for ex in "${_E43_ORDRE_ANNULATION[@]}"; do
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M19-$ex"; then
      actives+=("$ex")
    fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M19-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M19-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M19-$ex"
  done
  wb_marqueur_suppr M19-E43
  echo "Astreinte M19-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 19 43"
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
    if wb_marqueur_existe "M19-$ex"; then
      echo "Une panne M19-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
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

  echo "Injection en cours (trois pannes, chacune constatée par un pipeline : compte 15 à 30 minutes)…"
  WB_EX=M19-E43
  WB_VAR=0
  m19_sain || { echo "Chaîne de CI pas saine avant l'astreinte : rien n'est cassé." >&2; return 1; }
  m19_temoin || { echo "Témoin $_M19_TEMOIN impossible à préparer : rien n'est cassé." >&2; return 1; }
  m19_temoin_sain || { echo "Le canari n'est pas vert : rien n'est cassé." >&2; return 1; }
  if [[ " $a $b $c " == *" E39 "* ]]; then
    _e39_prealable || return 1
  fi
  wb_marqueur_ecrire M19-E43 ""

  _M19_ASTREINTE=1
  local -a choisies=() lignes=()
  local liste="" v
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" || "$ex" == "$c" ]] || continue
    v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    WB_EX="M19-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible (lab pas sain ?) : remise en état." >&2
      wb_marqueur_ecrire "M19-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M19-E43 "$liste"
      unset _M19_ASTREINTE
      _E43_annuler >/dev/null
      return 1
    fi
    wb_marqueur_ecrire "M19-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M19-E43 "$liste"
    if ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      unset _M19_ASTREINTE
      _E43_annuler >/dev/null
      return 1
    fi
    choisies+=("$ex")
  done
  unset _M19_ASTREINTE

  for ex in "${choisies[@]}"; do
    WB_EX="M19-$ex"
    WB_VAR="$(wb_marqueur_lire "M19-$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-4643 — De : Nadia Roussel (responsable astreinte) — priorité P1" \
    "Tu es d'astreinte. Mardi, 7 h 40 : la mise en production de MédiAgenda est prévue à 14 h et" \
    "plusieurs remontées arrivent sur la chaîne de livraison :" \
    "${lignes[@]}" \
    "Julien doit pouvoir construire, analyser, signer et promouvoir sa version avant midi." \
    "Tiens-moi informée toutes les 30 min, puis rédige le post-mortem avec le modèle de l'équipe" \
    "(modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Témoin : formation/ci-pannes (canari). Aucune donnée n'a été supprimée." \
    "Temps cible : 2 h (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 19 43"
}
