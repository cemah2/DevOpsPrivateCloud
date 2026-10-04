# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M02-E43 « Astreinte : l'outillage en panne »
#
# Tire deux pannes distinctes parmi M02-E35 à M02-E42 (variante de chacune tirée au hasard) et
# les injecte ensemble. Réutilise les fonctions panne_EXX_vN / annuler_EXX / resume_EXX des
# autres scripts, chargés en mode bibliothèque (WB_PANNES_LIB=1 : leur main n'est pas défini).
#
#   --variante N  (1 à 28) force la paire n° N (ordre : 1 = E35+E36, 2 = E35+E37, …,
#                 28 = E41+E42) ; les sous-variantes restent aléatoires.
#   --annuler     annule les deux pannes (et toute panne M02-E35 à E42 encore marquée active).
#
# Ordre d'injection : E35 d'abord (elle exige un contrôle des sauvegardes sain au départ),
# E36 en dernier (elle coupe l'accès de l'automatisation à Proxmox). Les vérifications
# individuelles (verifier_EXX) ne sont pas rejouées : E38 attendrait un pipeline et E40
# mesurerait 45 s ; le contrôle final de l'exercice porte sur l'état sain.

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

declare -A _E43_NB=([E35]=4 [E36]=4 [E37]=4 [E38]=4 [E39]=4 [E40]=4 [E41]=3 [E42]=4)
_E43_ORDRE=(E35 E41 E37 E39 E40 E42 E38 E36)

_E43_paires() {
  local -a ex=(E35 E36 E37 E38 E39 E40 E41 E42)
  local i j
  for ((i = 0; i < ${#ex[@]}; i++)); do
    for ((j = i + 1; j < ${#ex[@]}; j++)); do
      printf '%s %s\n' "${ex[i]}" "${ex[j]}"
    done
  done
}

_E43_annuler() {
  local liste e ex var
  liste="$(wb_marqueur_lire M02-E43)"
  local -a actives=()
  for ((e = ${#_E43_ORDRE[@]} - 1; e >= 0; e--)); do
    ex="${_E43_ORDRE[e]}"
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M02-$ex"; then
      actives+=("$ex")
    fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M02-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M02-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex"
    wb_marqueur_suppr "M02-$ex"
  done
  wb_marqueur_suppr M02-E43
  echo "Astreinte M02-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 02 43"
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
    if wb_marqueur_existe "M02-$ex"; then
      echo "Une panne M02-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done

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

  echo "Injection en cours (deux pannes, cela peut prendre quelques minutes)…"
  local -a choisies=() lignes=()
  local liste="" v
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" ]] || continue
    v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    WB_EX="M02-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible (lab pas sain ?) : remise en état." >&2
      wb_marqueur_ecrire "M02-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M02-E43 "$liste"
      _E43_annuler >/dev/null
      return 1
    fi
    # La fonction de panne a pu basculer sur une autre variante (WB_VAR modifié, cf. E35).
    wb_marqueur_ecrire "M02-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M02-E43 "$liste"
    choisies+=("$ex")
  done

  for ex in "${choisies[@]}"; do
    WB_VAR="$(wb_marqueur_lire "M02-$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-2850 — De : Nadia Roussel (responsable astreinte) — priorité P2" \
    "Tu es d'astreinte. Lundi matin, plusieurs remontées sur l'outillage de l'équipe :" \
    "${lignes[@]}" \
    "Je ne sais pas si c'est lié. Rétablis l'outillage, tiens-moi informée toutes les 30 min" \
    "(un message court dans #astreinte), puis rédige le post-mortem avec le modèle de l'équipe" \
    "(modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Temps cible : 2 h (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 02 43"
}
