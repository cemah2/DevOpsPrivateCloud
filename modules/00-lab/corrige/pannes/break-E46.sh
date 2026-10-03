# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E46.sh — M00-E46 « Astreinte : pannes multiples »
#
# Tire deux pannes distinctes parmi E38 à E45 (variante de chacune tirée au hasard) et les
# injecte simultanément. Réutilise les fonctions panne_EXX_vN / annuler_EXX des autres scripts,
# chargés en « mode bibliothèque » (WB_PANNES_LIB=1 : leur main n'est pas défini).
#
#   --variante N  (1 à 28) force la paire n° N (ordre lexicographique : 1 = E38+E39,
#                 2 = E38+E40, … 28 = E44+E45) ; les sous-variantes restent aléatoires.
#   --annuler     annule les deux pannes (et toute panne E38-E45 encore marquée active).
#
# Ordre d'injection : les pannes qui coupent l'accès SSH à un hôte passent en dernier, pour
# ne pas empêcher l'injection de l'autre (et l'annulation se fait dans l'ordre inverse).

_WB_E46_DIR="$(dirname "${BASH_SOURCE[0]}")"
WB_PANNES_LIB=1
# shellcheck source=break-E38.sh
source "$_WB_E46_DIR/break-E38.sh"
# shellcheck source=break-E39.sh
source "$_WB_E46_DIR/break-E39.sh"
# shellcheck source=break-E40.sh
source "$_WB_E46_DIR/break-E40.sh"
# shellcheck source=break-E41.sh
source "$_WB_E46_DIR/break-E41.sh"
# shellcheck source=break-E42.sh
source "$_WB_E46_DIR/break-E42.sh"
# shellcheck source=break-E43.sh
source "$_WB_E46_DIR/break-E43.sh"
# shellcheck source=break-E44.sh
source "$_WB_E46_DIR/break-E44.sh"
# shellcheck source=break-E45.sh
source "$_WB_E46_DIR/break-E45.sh"
unset WB_PANNES_LIB

# Nombre de variantes de chaque panne élémentaire
declare -A _E46_NB=([E38]=3 [E39]=3 [E40]=4 [E41]=3 [E42]=4 [E43]=3 [E44]=4 [E45]=3)
# Ordre d'injection (l'annulation suit l'ordre inverse)
_E46_ORDRE=(E44 E42 E45 E40 E39 E41 E43 E38)

_E46_paires() {
  local -a ex=(E38 E39 E40 E41 E42 E43 E44 E45)
  local i j
  for ((i = 0; i < ${#ex[@]}; i++)); do
    for ((j = i + 1; j < ${#ex[@]}; j++)); do
      printf '%s %s\n' "${ex[i]}" "${ex[j]}"
    done
  done
}

_E46_annuler() {
  local liste="" e ex var
  liste="$(wb_marqueur_lire E46)"
  local -a actives=()
  for ((e = ${#_E46_ORDRE[@]} - 1; e >= 0; e--)); do
    ex="${_E46_ORDRE[e]}"
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "$ex"; then
      actives+=("$ex")
    fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "$ex")"
    WB_EX="$ex"; WB_VAR="${var:-annulation}"
    "annuler_$ex"
    wb_marqueur_suppr "$ex"
  done
  wb_marqueur_suppr E46
  echo "Astreinte E46 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 00 46"
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
    _E46_annuler
    return 0
  fi

  local ex
  for ex in E46 "${_E46_ORDRE[@]}"; do
    if wb_marqueur_existe "$ex"; then
      echo "Une panne $ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done

  local -a paires
  mapfile -t paires < <(_E46_paires)
  if [[ -z "$paire" ]]; then
    paire=$((RANDOM % ${#paires[@]} + 1))
  fi
  if ! [[ "$paire" =~ ^[0-9]+$ ]] || ((paire < 1 || paire > ${#paires[@]})); then
    echo "Variante invalide : $paire (1 à ${#paires[@]})" >&2
    return 2
  fi
  local a b
  read -r a b <<<"${paires[paire - 1]}"

  echo "Injection en cours (deux pannes, cela peut prendre quelques minutes)…"
  local -a choisies=() lignes=()
  local liste="" v
  for ex in "${_E46_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" ]] || continue
    v=$((RANDOM % ${_E46_NB[$ex]} + 1))
    WB_EX="$ex"; WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible : remise en état." >&2
      wb_marqueur_ecrire E46 "$liste"
      _E46_annuler >/dev/null
      return 1
    fi
    wb_marqueur_ecrire "$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire E46 "$liste"
    choisies+=("$ex")
  done

  for ex in "${choisies[@]}"; do
    WB_VAR="$(wb_marqueur_lire "$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-2620 — De : Nadia Roussel (responsable astreinte) — priorité P2" \
    "Tu es d'astreinte cette semaine. Réveil difficile : plusieurs alertes et remontées depuis 6 h." \
    "${lignes[@]}" \
    "Je ne sais pas si c'est lié. Rétablis le service, tiens-moi informée toutes les 30 min" \
    "(un message court dans le canal #astreinte suffit), puis rédige le post-mortem avec le" \
    "modèle ressources/M00-E46/modele-post-mortem.md." \
    "" \
    "Temps cible : 90 min (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 00 46"
}
