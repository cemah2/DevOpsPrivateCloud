# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M09-E43 « Astreinte : le cluster en détresse »
#
# Tire deux pannes distinctes parmi M09-E35 à M09-E42 (variante de chacune tirée au hasard) et les
# injecte ensemble. Réutilise panne_EXX_vN / verifier_EXX / annuler_EXX / resume_EXX des autres
# scripts, chargés en mode bibliothèque (WB_PANNES_LIB=1).
#
#   --variante N  (1 à 25) force la paire n° N (ordre : 1 = E35+E37, 2 = E35+E38, … ; paires exclues :
#                 E35+E36, E35+E42 et E36+E42, trois pannes de quorum qui se masquent l'une l'autre et
#                 désarment toutes la HA) ; les sous-variantes restent aléatoires.
#   --annuler     annule les deux pannes (et toute panne M09-E35 à E42 encore marquée active).
#
# Ordre d'injection (dépendances) : E40 (réplication : SSH entre nœuds et quorum), E41 (pvesm set :
# quorum), E37 (crée des VMs sur ceph-vm, HA armée), E38 (VM sur ceph-vm), E39 (bloque Ceph : après
# tout ce qui crée des disques), E36, E42, E35 (pertes de quorum : en dernier). Chaque panne est
# constatée sur place (verifier_EXX) juste après son injection ; en cas d'échec, tout est annulé.
# Annulation dans l'ordre inverse (le quorum et Ceph reviennent avant qu'on détruise les VMs de test).

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

declare -A _E43_NB=([E35]=3 [E36]=4 [E37]=3 [E38]=4 [E39]=3 [E40]=3 [E41]=3 [E42]=3)
_E43_ORDRE=(E40 E41 E37 E38 E39 E36 E42 E35)

_E43_paires() {
  local -a ex=(E35 E36 E37 E38 E39 E40 E41 E42)
  local i j p
  for ((i = 0; i < ${#ex[@]}; i++)); do
    for ((j = i + 1; j < ${#ex[@]}; j++)); do
      p="${ex[i]} ${ex[j]}"
      [[ "$p" == "E35 E36" || "$p" == "E35 E42" || "$p" == "E36 E42" ]] && continue
      printf '%s\n' "$p"
    done
  done
}

_E43_annuler() {
  local liste e ex var
  liste="$(wb_marqueur_lire M09-E43)"
  local -a actives=()
  for ((e = ${#_E43_ORDRE[@]} - 1; e >= 0; e--)); do
    ex="${_E43_ORDRE[e]}"
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M09-$ex"; then
      actives+=("$ex")
    fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M09-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M09-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M09-$ex"
  done
  wb_marqueur_suppr M09-E43
  echo "Astreinte M09-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 09 43"
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
    if wb_marqueur_existe "M09-$ex"; then
      echo "Une panne M09-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done
  WB_EX=M09-E43

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

  echo "Injection en cours (deux pannes, cela peut prendre une dizaine de minutes)…"
  local -a choisies=() lignes=()
  local liste="" v
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" ]] || continue
    v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    WB_EX="M09-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible (lab pas sain ?) : remise en état." >&2
      wb_marqueur_ecrire "M09-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M09-E43 "$liste"
      _E43_annuler >/dev/null
      return 1
    fi
    # La fonction de panne a pu basculer sur une autre variante (WB_VAR modifié, m09_essayer).
    wb_marqueur_ecrire "M09-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M09-E43 "$liste"
    if ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      _E43_annuler >/dev/null
      return 1
    fi
    choisies+=("$ex")
  done

  for ex in "${choisies[@]}"; do
    WB_EX="M09-$ex"
    WB_VAR="$(wb_marqueur_lire "M09-$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-3650 — De : Nadia Roussel (responsable astreinte) — priorité P2" \
    "Tu es d'astreinte. Mardi, 6 h 55 : deux remontées sur le cluster de virtualisation hv-par1 :" \
    "${lignes[@]}" \
    "La recette de MédiAgenda tourne sur ce cluster à partir de 9 h. Tiens-moi informée toutes les" \
    "30 min (#astreinte), puis rédige le post-mortem avec le modèle de l'équipe" \
    "(modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Accès : ssh hv01, hv02, hv03 depuis adm01 (root, clé du fichier de réponse) ; console des nœuds par" \
    "« qm terminal » ou noVNC sur pve01 en dernier recours. Une HA désarmée par l'injection est" \
    "réarmée par --annuler." \
    "Temps cible : 2 h (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 09 43"
}
