# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M10-E43 « Astreinte : le cloud en détresse »
#
# Tire deux pannes distinctes parmi M10-E35 à M10-E42 (variante de chacune tirée au hasard) et les
# injecte ensemble. Réutilise panne_EXX_vN / verifier_EXX / annuler_EXX / resume_EXX des autres
# scripts, chargés en mode bibliothèque (WB_PANNES_LIB=1).
#
#   --variante N  (1 à 27) force la paire n° N (ordre : 1 = E35+E36, 2 = E35+E37, … ; la paire
#                 E35+E40, deux pannes qui produisent le même « No valid host » et se masquent,
#                 est exclue) ; les sous-variantes restent aléatoires.
#   --annuler     annule les deux pannes (et toute panne M10-E35 à E42 encore marquée active).
#
# Ordre d'injection (dépendances) : celles qui ont besoin de l'API et des calculs pour se préparer
# ou se constater d'abord (E41 envoi d'image, E38 instance + volume, E37 et E36 piles sondes, E35
# instance sonde), puis E40 (calculs down), E39 (authentification) et E42 en dernier (peut couper
# les VIP : plus rien ne serait joignable ensuite). Chaque panne est constatée sur place juste
# après son injection ; en cas d'échec, les deux sont annulées. Annulation dans l'ordre inverse
# (E42 rend les VIP, E39 l'authentification, puis les autres peuvent utiliser l'API).

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

declare -A _E43_NB=([E35]=4 [E36]=4 [E37]=3 [E38]=3 [E39]=3 [E40]=3 [E41]=3 [E42]=4)
_E43_ORDRE=(E41 E38 E37 E36 E35 E40 E39 E42)

_E43_paires() {
  local -a ex=(E35 E36 E37 E38 E39 E40 E41 E42)
  local i j
  for ((i = 0; i < ${#ex[@]}; i++)); do
    for ((j = i + 1; j < ${#ex[@]}; j++)); do
      [[ "${ex[i]} ${ex[j]}" == "E35 E40" ]] && continue
      printf '%s %s\n' "${ex[i]}" "${ex[j]}"
    done
  done
}

_E43_annuler() {
  local liste e ex var
  liste="$(wb_marqueur_lire M10-E43)"
  local -a actives=()
  for ((e = ${#_E43_ORDRE[@]} - 1; e >= 0; e--)); do
    ex="${_E43_ORDRE[e]}"
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M10-$ex"; then
      actives+=("$ex")
    fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M10-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M10-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M10-$ex"
  done
  wb_marqueur_suppr M10-E43
  echo "Astreinte M10-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 10 43"
}

main() {
  local paire="" annuler=0
  while (($#)); do
    case "$1" in
      --variante)
        if (($# < 2)); then echo "--variante attend un numéro" >&2; return 2; fi
        paire="$2"; shift 2 ;;
      --variante=*) paire="${1#*=}"; shift ;;
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
    if wb_marqueur_existe "M10-$ex"; then
      echo "Une panne M10-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done
  WB_EX=M10-E43

  local -a paires
  mapfile -t paires < <(_E43_paires)
  if [[ -z "$paire" ]]; then
    paire=$((RANDOM % ${#paires[@]} + 1))
  fi
  if ! [[ "$paire" =~ ^[0-9]+$ ]] || ((paire < 1 || paire > ${#paires[@]})); then
    echo "Variante invalide : $paire (1 à ${#paires[@]})" >&2
    return 2
  fi
  local a b
  read -r a b <<<"${paires[paire - 1]}"

  echo "Injection en cours (deux pannes, cela peut prendre 10 à 15 minutes)…"
  local -a choisies=() lignes=()
  local liste="" v
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" ]] || continue
    v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    WB_EX="M10-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible (lab pas sain ?) : remise en état." >&2
      wb_marqueur_ecrire "M10-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M10-E43 "$liste"
      _E43_annuler >/dev/null
      return 1
    fi
    # La fonction de panne a pu basculer sur une autre variante (WB_VAR modifié, m10_essayer).
    wb_marqueur_ecrire "M10-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M10-E43 "$liste"
    if ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      _E43_annuler >/dev/null
      return 1
    fi
    choisies+=("$ex")
  done

  for ex in "${choisies[@]}"; do
    WB_EX="M10-$ex"
    WB_VAR="$(wb_marqueur_lire "M10-$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-3750 — De : Nadia Roussel (responsable astreinte) — priorité P2" \
    "Tu es d'astreinte. Mardi, 6 h 50 : plusieurs remontées sur le cloud OpenStack :" \
    "${lignes[@]}" \
    "L'équipe MédiAgenda lance sa campagne de recette à 9 h sur le cloud : elle a besoin de créer" \
    "des instances, des volumes et des IP flottantes. Tiens-moi informée toutes les 30 min" \
    "(#astreinte), puis rédige le post-mortem avec le modèle de l'équipe" \
    "(modules/00-lab/ressources/M00-E46/modele-post-mortem.md) et le runbook RB-103." \
    "" \
    "Temps cible : 2 h (rétablissement) + 1 h (post-mortem et runbook). Contrôle : lab/bin/check 10 43"
}
