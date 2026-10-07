# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M05-E43 « Astreinte : l'IaC en panne »
#
# Tire deux pannes distinctes parmi M05-E35 à M05-E42 (variante de chacune tirée au hasard ; une
# variante sans effet sur ce lab est remplacée par la suivante) et les injecte ensemble. Réutilise
# panne_EXX_vN / verifier_EXX / annuler_EXX / resume_EXX des autres scripts, chargés en mode
# bibliothèque (WB_PANNES_LIB=1).
#
#   --variante N  (1 à 27) force la paire n° N, dans l'ordre de _E43_paires (1 = E35+E36,
#                 2 = E35+E37, …) ; la paire E35+E41 est exclue (deux pannes qui cassent le
#                 plan du socle sans commit, et check-E35 contrôle aussi l'image current
#                 que retire E41 v1 : leurs diagnostics se confondent) ; les sous-variantes restent aléatoires.
#   --annuler     annule les deux pannes (et toute panne M05-E35 à E42 encore marquée active).
#
# Ordre d'injection (dépendances) : E38 (droits Proxmox, sans OpenTofu), E39, E40 (lit l'état
# envs), E35 (exige un plan socle vide), E36 (la console de la v2 a besoin de la phrase de
# chiffrement d'origine), E42 (init / espace de travail), E41 (peut rendre OpenTofu inutilisable),
# E37 en dernier (coupe l'accès au backend). Chaque panne est constatée sur place juste après son
# injection ; en cas d'échec, tout est annulé. Annulation dans l'ordre inverse (E37 d'abord : les
# autres annulations ont besoin du backend). La copie de travail ~/src/infra doit être propre au
# départ (contrôlé une fois).

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
_E43_ORDRE=(E38 E39 E40 E35 E36 E42 E41 E37)

_E43_paires() {
  local -a ex=(E35 E36 E37 E38 E39 E40 E41 E42)
  local i j
  for ((i = 0; i < ${#ex[@]}; i++)); do
    for ((j = i + 1; j < ${#ex[@]}; j++)); do
      [[ "${ex[i]} ${ex[j]}" == "E35 E41" ]] && continue
      printf '%s %s\n' "${ex[i]}" "${ex[j]}"
    done
  done
}

_E43_annuler() {
  local liste e ex var
  liste="$(wb_marqueur_lire M05-E43)"
  local -a actives=()
  for ((e = ${#_E43_ORDRE[@]} - 1; e >= 0; e--)); do
    ex="${_E43_ORDRE[e]}"
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M05-$ex"; then
      actives+=("$ex")
    fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M05-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M05-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M05-$ex"
  done
  wb_marqueur_suppr M05-E43
  echo "Astreinte M05-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 05 43"
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
    if wb_marqueur_existe "M05-$ex"; then
      echo "Une panne M05-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done
  WB_EX=M05-E43
  m05_prerequis socle envs || return 1

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

  echo "Injection en cours (deux pannes, plusieurs plans OpenTofu : cela peut prendre quelques minutes)…"
  _M05_ASTREINTE=1
  local -a choisies=() lignes=()
  local liste="" v
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" ]] || continue
    v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    WB_EX="M05-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible (lab pas sain ?) : remise en état." >&2
      wb_marqueur_ecrire "M05-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M05-E43 "$liste"
      _E43_annuler >/dev/null
      unset _M05_ASTREINTE
      return 1
    fi
    # La fonction de panne a pu basculer sur une autre variante (WB_VAR modifié, m05_essayer).
    wb_marqueur_ecrire "M05-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M05-E43 "$liste"
    if ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      _E43_annuler >/dev/null
      unset _M05_ASTREINTE
      return 1
    fi
    choisies+=("$ex")
  done
  unset _M05_ASTREINTE

  for ex in "${choisies[@]}"; do
    WB_EX="M05-$ex"
    WB_VAR="$(wb_marqueur_lire "M05-$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-3250 — De : Nadia Roussel (responsable astreinte) — priorité P2" \
    "Tu es d'astreinte. Jeudi, 7 h 50 : plusieurs remontées sur la chaîne d'infrastructure as code :" \
    "${lignes[@]}" \
    "Julien a une démonstration de MédiAgenda à 14 h sur envs/lab-m05, et la MR de Karim sur le" \
    "socle attend son apply. Gel des apply sur socle jusqu'à ton feu vert." \
    "Rétablis la chaîne, tiens-moi informée toutes les 30 min (un message court dans #astreinte)," \
    "puis rédige le post-mortem avec le modèle de l'équipe" \
    "(modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Temps cible : 2 h (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 05 43"
}
