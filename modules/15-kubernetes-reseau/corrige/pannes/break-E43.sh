# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M15-E43 « Astreinte : plus rien n'entre dans le cluster »
#
# Tire TROIS pannes, une par famille, avec une sous-variante aléatoire parmi celles permises :
#   entrée      : E38 (variantes 2, 3, 4 : annonces BGP) ou E39 (variantes 1, 2 : certificat) ;
#   réseau/DNS  : E36 (1, 2, 3) ou E42 (1, 2, 3) ;
#   application : E35 (1, 2, 3), E37 (1, 2, 3), E40 (1, 2, 3, 4) ou E41 (1, 3).
# Ordre d'injection : réseau, puis application, puis entrée (les pannes de l'application modifient
# le Service dont la panne E36 a besoin pour trouver le Deployment ; une entrée coupée rendrait les
# vérifications des deux autres familles sans objet). Annulation dans l'ordre inverse.
#   --variante N  (1 à 16) force la combinaison de pannes (pas les sous-variantes) ;
#   --annuler     retire les trois pannes (et toute panne M15-E35 à E42 encore marquée active).
# Les témoins et l'état sain sont contrôlés une seule fois, avant la première panne.

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

declare -A _E43_SOUS=([E35]="1 2 3" [E36]="1 2 3" [E37]="1 2 3" [E38]="2 3 4" [E39]="1 2"
  [E40]="1 2 3 4" [E41]="1 3" [E42]="1 2 3")
_E43_ENTREE=(E38 E39)
_E43_RESEAU=(E36 E42)
_E43_APPLI=(E35 E37 E40 E41)
_E43_TOUTES=(E35 E36 E37 E38 E39 E40 E41 E42)

# _E43_combinaisons — lignes « réseau appli entrée », dans l'ordre d'injection.
_E43_combinaisons() {
  local a r e
  for e in "${_E43_ENTREE[@]}"; do
    for r in "${_E43_RESEAU[@]}"; do
      for a in "${_E43_APPLI[@]}"; do
        printf '%s %s %s\n' "$r" "$a" "$e"
      done
    done
  done
}

_E43_annuler() {
  local liste ex var i
  liste="$(wb_marqueur_lire M15-E43)"
  local -a actives=()
  # Ordre inverse de l'injection : entrée, application, réseau.
  for ex in E38 E39 E35 E37 E40 E41 E36 E42; do
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M15-$ex"; then
      actives+=("$ex")
    fi
  done
  for i in "${actives[@]}"; do
    ex="$i"
    var="$(wb_marqueur_lire "M15-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M15-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M15-$ex"
  done
  wb_marqueur_suppr M15-E43
  echo "Astreinte M15-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 15 43"
}

main() {
  local combi="" annuler=0
  while (($#)); do
    case "$1" in
      --variante)
        if (($# < 2)); then echo "--variante attend un numéro" >&2; return 2; fi
        combi="$2"; shift 2 ;;
      --variante=*) combi="${1#*=}"; shift ;;
      --annuler) annuler=1; shift ;;
      *) echo "Option inconnue : $1 (attendu : --variante N, --annuler)" >&2; return 2 ;;
    esac
  done

  if ((annuler)); then
    _E43_annuler
    return 0
  fi

  local ex
  for ex in E43 "${_E43_TOUTES[@]}"; do
    if wb_marqueur_existe "M15-$ex"; then
      echo "Une panne M15-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done

  local -a combis
  mapfile -t combis < <(_E43_combinaisons)
  if [[ -z "$combi" ]]; then
    combi=$((RANDOM % ${#combis[@]} + 1))
  fi
  if ! [[ "$combi" =~ ^[0-9]+$ ]] || ((combi < 1 || combi > ${#combis[@]})); then
    echo "Variante invalide : $combi (1 à ${#combis[@]})" >&2
    return 2
  fi
  local -a choisies
  read -r -a choisies <<<"${combis[combi - 1]}"

  echo "Injection en cours (trois pannes, cela peut prendre jusqu'à 15 minutes)…"
  WB_EX=M15-E43
  WB_VAR=0
  m15_temoins || { echo "Témoins du palier 4 impossibles à préparer : rien n'est cassé." >&2; return 1; }
  m15_sain || { echo "Cluster pas sain avant l'astreinte : rien n'est cassé." >&2; return 1; }
  _M15_ASTREINTE=1
  local -a lignes=() sous
  local liste="" v
  for ex in "${choisies[@]}"; do
    read -r -a sous <<<"${_E43_SOUS[$ex]}"
    v="${sous[RANDOM % ${#sous[@]}]}"
    WB_EX="M15-$ex"
    WB_VAR="$v"
    # Appel direct de la variante tirée, sans repli sur une autre (m15_essayer est contourné) :
    # l'astreinte ne doit pas glisser vers une variante hors de sa famille.
    if ! "_m15${ex}_une" "$v" >/dev/null 2>&1; then
      echo "Injection de la panne $ex impossible sur ce lab : remise en état." >&2
      wb_marqueur_ecrire "M15-$ex" "$v"
      liste+="$ex:$v "
      wb_marqueur_ecrire M15-E43 "$liste"
      unset _M15_ASTREINTE
      _E43_annuler >/dev/null
      return 1
    fi
    WB_VAR="$v"
    wb_marqueur_ecrire "M15-$ex" "$v"
    liste+="$ex:$v "
    wb_marqueur_ecrire M15-E43 "$liste"
    if ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      unset _M15_ASTREINTE
      _E43_annuler >/dev/null
      return 1
    fi
    lignes+=("- $("resume_$ex")")
  done
  unset _M15_ASTREINTE

  wb_symptome "Ticket INC-4250 — De : Nadia Roussel (responsable astreinte) — priorité P1" \
    "Tu es d'astreinte. Jeudi, 23 h 10 : la sonde externe ne joint plus MédiAgenda en recette, où" \
    "une campagne de tests de charge du client démarre à 7 h. Remontées reçues :" \
    "${lignes[@]}" \
    "Il y a eu trois interventions dans la journée, aucune avec un ticket de changement." \
    "Tiens-moi informée toutes les 30 min (#astreinte), puis rédige le post-mortem avec le modèle" \
    "de l'équipe (modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Interdits : supprimer une politique de refus par défaut, désactiver Cilium ou le chiffrement," \
    "basculer la VIP de la bordure, poser un certificat à la main." \
    "Temps cible : 2 h (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 15 43"
}
