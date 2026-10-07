# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M04-E43 « Astreinte : la chaîne de configuration en panne »
#
# Tire deux pannes distinctes parmi M04-E35 à M04-E42 (variante de chacune tirée au hasard) et
# les injecte ensemble. Réutilise les fonctions panne_EXX_vN / verifier_EXX / annuler_EXX /
# resume_EXX des autres scripts, chargés en mode bibliothèque (WB_PANNES_LIB=1).
#
#   --variante N  (1 à 28) force la paire n° N (ordre : 1 = E35+E36, 2 = E35+E37, …,
#                 28 = E41+E42) ; les sous-variantes restent aléatoires.
#   --annuler     annule les deux pannes (et toute panne M04-E35 à E42 encore marquée active).
#
# Ordre d'injection (dépendances entre pannes) : E37 (sa sonde lance un playbook sur dns01),
# E36, E39 (lit l'inventaire), E41 (agit sur git01 avant que ses clés d'hôte ne changent), E35,
# E42, E38 (rend Ansible inutilisable : après tout ce qui lance Ansible), E40 en dernier (coupe
# SSH vers runner01). Chaque panne est constatée sur place (verifier_EXX) juste après son
# injection ; en cas d'échec, les deux pannes sont annulées. Annulation dans l'ordre inverse.
# La copie de travail ~/src/ansible doit être propre au départ (contrôlé une fois).

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

declare -A _E43_NB=([E35]=4 [E36]=4 [E37]=4 [E38]=4 [E39]=4 [E40]=4 [E41]=4 [E42]=4)
_E43_ORDRE=(E37 E36 E39 E41 E35 E42 E38 E40)

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
  liste="$(wb_marqueur_lire M04-E43)"
  local -a actives=()
  for ((e = ${#_E43_ORDRE[@]} - 1; e >= 0; e--)); do
    ex="${_E43_ORDRE[e]}"
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M04-$ex"; then
      actives+=("$ex")
    fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M04-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M04-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M04-$ex"
  done
  wb_marqueur_suppr M04-E43
  echo "Astreinte M04-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 04 43"
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
    if wb_marqueur_existe "M04-$ex"; then
      echo "Une panne M04-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done
  WB_EX=M04-E43
  m04_prerequis || return 1

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
  _M04_ASTREINTE=1
  local -a choisies=() lignes=()
  local liste="" v
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" ]] || continue
    v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    WB_EX="M04-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible (lab pas sain ?) : remise en état." >&2
      wb_marqueur_ecrire "M04-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M04-E43 "$liste"
      _E43_annuler >/dev/null
      unset _M04_ASTREINTE
      return 1
    fi
    # La fonction de panne a pu basculer sur une autre variante (WB_VAR modifié, m04_essayer).
    wb_marqueur_ecrire "M04-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M04-E43 "$liste"
    if ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      _E43_annuler >/dev/null
      unset _M04_ASTREINTE
      return 1
    fi
    choisies+=("$ex")
  done
  unset _M04_ASTREINTE

  for ex in "${choisies[@]}"; do
    WB_VAR="$(wb_marqueur_lire "M04-$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-3150 — De : Nadia Roussel (responsable astreinte) — priorité P2" \
    "Tu es d'astreinte. Mardi, 7 h 40 : plusieurs remontées sur la chaîne de configuration du socle :" \
    "${lignes[@]}" \
    "La fenêtre de maintenance de ce soir (mises à jour de sécurité par site.yml) est menacée." \
    "Rétablis la chaîne, tiens-moi informée toutes les 30 min (un message court dans #astreinte)," \
    "puis rédige le post-mortem avec le modèle de l'équipe" \
    "(modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Temps cible : 2 h (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 04 43"
}
