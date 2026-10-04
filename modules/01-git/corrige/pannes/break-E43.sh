# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M01-E43 « Astreinte : la forge en difficulté »
#
# Tire deux pannes distinctes parmi M01-E36 à M01-E42 (variante de chacune tirée au hasard) et
# les injecte ensemble. Réutilise panne_EXX_vN / verifier_EXX / annuler_EXX des autres scripts,
# chargés en « mode bibliothèque » (WB_PANNES_LIB=1 : leur main n'est pas défini).
#
#   --variante N  (1 à 21) force la paire n° N (ordre lexicographique : 1 = E36+E37,
#                 2 = E36+E38, … 21 = E41+E42) ; les sous-variantes restent aléatoires.
#   --annuler     annule les deux pannes (et toute panne M01-E36 à E42 encore marquée active).
#
# Ordre d'injection : d'abord ce qui est local (dépôts de Lucas), puis ce qui passe par l'API
# GitLab, puis ce qui coupe SSH, et la 502 en dernier (elle couperait l'API des autres
# injections). Chaque panne est contrôlée (verifier_EXX) juste après son injection, avant la
# suivante. L'annulation suit l'ordre inverse (la 502 d'abord, pour retrouver l'API).

_WB_E43_DIR="$(dirname "${BASH_SOURCE[0]}")"
WB_PANNES_LIB=1
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

# Nombre de variantes de chaque panne élémentaire
declare -A _E43_NB=([E36]=4 [E37]=3 [E38]=4 [E39]=4 [E40]=4 [E41]=4 [E42]=4)
# Ordre d'injection (l'annulation suit l'ordre inverse)
_E43_ORDRE=(E41 E42 E39 E38 E36 E40 E37)

_E43_paires() {
  local -a ex=(E36 E37 E38 E39 E40 E41 E42)
  local i j
  for ((i = 0; i < ${#ex[@]}; i++)); do
    for ((j = i + 1; j < ${#ex[@]}; j++)); do
      printf '%s %s\n' "${ex[i]}" "${ex[j]}"
    done
  done
}

_E43_annuler() {
  local liste e ex var
  liste="$(wb_marqueur_lire M01-E43)"
  local -a actives=()
  for ((e = ${#_E43_ORDRE[@]} - 1; e >= 0; e--)); do
    ex="${_E43_ORDRE[e]}"
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M01-$ex"; then
      actives+=("$ex")
    fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M01-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M01-$ex"; WB_VAR="${var:-annulation}"
    "annuler_$ex" || wb_avert "annulation de M01-$ex incomplète"
    wb_marqueur_suppr "M01-$ex"
  done
  wb_marqueur_suppr M01-E43
  echo "Astreinte M01-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 01 43"
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
    if wb_marqueur_existe "M01-$ex"; then
      echo "Une panne M01-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
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

  echo "Injection en cours (deux pannes : jusqu'à 10 minutes si GitLab doit redémarrer)…"
  local -a choisies=() lignes=()
  local liste="" v
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" ]] || continue
    v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    WB_EX="M01-$ex"; WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null || ! "verifier_$ex"; then
      echo "Injection de la panne M01-$ex impossible ou non constatée : remise en état." >&2
      "annuler_$ex" || true
      wb_marqueur_ecrire M01-E43 "$liste"
      _E43_annuler >/dev/null
      return 1
    fi
    # La fonction de panne peut avoir basculé sur une autre variante (WB_VAR modifié).
    wb_marqueur_ecrire "M01-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M01-E43 "$liste"
    choisies+=("$ex")
  done

  for ex in "${choisies[@]}"; do
    WB_VAR="$(wb_marqueur_lire "M01-$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-2788 — De : Nadia Roussel (responsable astreinte) — priorité P2" \
    "Tu es d'astreinte. Depuis 7 h, plusieurs remontées sur la forge :" \
    "${lignes[@]}" \
    "Je ne sais pas si c'est lié. Rétablis le service, tiens-moi informée toutes les 30 min" \
    "(un message court dans le canal #astreinte suffit), puis rédige le post-mortem dans" \
    "docs/socle/post-mortems/ de plateforme/medisphere, par MR." \
    "" \
    "Temps cible : 90 min (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 01 43"
}
