# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M20-E43 « Astreinte : la mise en production tourne mal »
#
# Tire TROIS pannes distinctes parmi M20-E35 à M20-E42 (variante de chacune tirée au hasard) et les
# injecte ensemble. Réutilise panne_EXX_vN / verifier_EXX / annuler_EXX / resume_EXX des autres
# scripts, chargés en mode bibliothèque (WB_PANNES_LIB=1).
#
#   --variante N  force le trio n° N (ordre de la liste des trios admis) ; les sous-variantes restent
#                 aléatoires.
#   --annuler     annule les pannes de l'astreinte (et toute panne M20-E35 à E42 encore marquée).
#
# Règles :
#   - au plus UNE panne du groupe « dev » (E35, E36, E38, E39, E41 : elles modifient toutes l'overlay
#     de dev ou l'Application mediagenda-dev) ; les autres (E37 dépôt, E40 canary de recette,
#     E42 cluster de l'agence) se combinent librement. E42 n'est tirée que si lyo-k3s01 est
#     enregistrée dans Argo CD ;
#   - ordre d'injection : E42, E40, la panne de dev, puis E37 en DERNIER (tant qu'Argo CD ne lit
#     plus Git, les commits des autres pannes ne lui parviendraient pas). Annulation dans l'ordre
#     inverse : E37 d'abord, pour que les commits inverses des autres soient vus ;
#   - jamais la production : aucune des pannes ne la touche (le ticket la mentionne parce que la
#     mise en production est suspendue tant que l'incident dure).

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

declare -A _E43_NB=([E35]=4 [E36]=4 [E37]=4 [E38]=4 [E39]=3 [E40]=4 [E41]=3 [E42]=4)
_E43_DEV=(E35 E36 E38 E39 E41)
_E43_ORDRE=(E42 E40 E35 E36 E38 E39 E41 E37)
_E43_ORDRE_ANNULATION=(E37 E41 E39 E38 E36 E35 E40 E42)

# _e43_trios — trios admis, un par ligne.
_e43_trios() {
  local -a autres=(E37 E40)
  local d i j
  [[ -n "$(_e42_secret)" ]] && autres+=(E42)
  if ((${#autres[@]} == 3)); then printf '%s %s %s\n' "${autres[@]}"; fi
  for ((i = 0; i < ${#autres[@]}; i++)); do
    for ((j = i + 1; j < ${#autres[@]}; j++)); do
      for d in "${_E43_DEV[@]}"; do printf '%s %s %s\n' "${autres[i]}" "${autres[j]}" "$d"; done
    done
  done
}

_E43_annuler() {
  local liste ex var
  liste="$(wb_marqueur_lire M20-E43)"
  local -a actives=()
  for ex in "${_E43_ORDRE_ANNULATION[@]}"; do
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M20-$ex"; then
      actives+=("$ex")
    fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M20-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M20-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M20-$ex"
  done
  WB_EX=M20-E43
  WB_VAR=0
  wb_marqueur_suppr M20-E43
  echo "Astreinte M20-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 20 43"
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
    if wb_marqueur_existe "M20-$ex"; then
      echo "Une panne M20-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done

  local -a trios
  mapfile -t trios < <(_e43_trios)
  if [[ -z "$trio" ]]; then
    trio=$((RANDOM % ${#trios[@]} + 1))
  fi
  if ! [[ "$trio" =~ ^[0-9]+$ ]] || ((trio < 1 || trio > ${#trios[@]})); then
    echo "Variante invalide : $trio (1 à ${#trios[@]})" >&2
    return 2
  fi
  local a b c
  read -r a b c <<<"${trios[trio - 1]}"

  echo "Injection en cours (trois pannes, MR et synchronisations comprises : compte 10 à 30 minutes)…"
  WB_EX=M20-E43
  WB_VAR=0
  # Santé de tout ce que les trois pannes touchent, une seule fois avant la première injection.
  local -a apps=("$_M20_APP_DEV" "$_M20_APP_RECETTE")
  m20_sain "${apps[@]}" || { echo "Applications pas saines avant l'astreinte : rien n'est cassé." >&2; return 1; }
  if [[ " $a $b $c " == *" E40 "* ]] && ! _e40_preparer; then
    echo "Le canary de recette n'est pas prêt : rien n'est cassé." >&2
    return 1
  fi
  wb_marqueur_ecrire M20-E43 ""

  _M20_ASTREINTE=1
  local -a choisies=() lignes=()
  local liste="" v
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" || "$ex" == "$c" ]] || continue
    v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    WB_EX="M20-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible (lab pas sain ?) : remise en état." >&2
      wb_marqueur_ecrire "M20-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M20-E43 "$liste"
      unset _M20_ASTREINTE
      _E43_annuler >/dev/null
      return 1
    fi
    # La fonction de panne a pu basculer sur une autre variante (WB_VAR modifié, m20_essayer).
    wb_marqueur_ecrire "M20-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M20-E43 "$liste"
    if ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      unset _M20_ASTREINTE
      _E43_annuler >/dev/null
      return 1
    fi
    choisies+=("$ex")
  done
  unset _M20_ASTREINTE

  for ex in "${choisies[@]}"; do
    WB_EX="M20-$ex"
    WB_VAR="$(wb_marqueur_lire "M20-$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-4743 — De : Nadia Roussel (responsable astreinte) — priorité P1" \
    "Tu es d'astreinte. Jeudi, 17 h 40 : Julien a lancé la mise en production de MédiAgenda (MR de" \
    "promotion fusionnée, synchronisation de prod prévue à 18 h) et les remontées s'enchaînent :" \
    "${lignes[@]}" \
    "La mise en production est suspendue : ne synchronise pas la prod tant que l'incident n'est pas" \
    "clos (le gel des changements commence demain 16 h, M20-E29). Tiens-moi informée toutes les" \
    "30 min, puis rédige le post-mortem avec le modèle de l'équipe" \
    "(modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Règles : tout correctif passe par Git (MR) ou par le code de la plateforme ; aucune" \
    "désactivation durable de l'auto-synchronisation ; aucun « argocd app sync --force » en prod." \
    "Temps cible : 2 h (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 20 43"
}
