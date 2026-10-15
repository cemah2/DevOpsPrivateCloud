# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M16-E43 « Astreinte : les données de MédiAgenda sont en danger »
#
# Tire trois pannes parmi M16-E35 à M16-E42, une par famille (variante de chacune au hasard) :
#   A. la base : E41 (archivage des WAL) ou E40 (bascule) ;
#   B. les sauvegardes : E39 (Velero) ou E42 (instantanés) ;
#   C. les volumes : E35 (PVC Pending), E36 (ContainerCreating), E37 (nœud perdu), E38 (Ceph refuse).
# Combinaisons exclues : E40 avec E36 ou E37 (des nœuds cordonnés ou perdus empêcheraient l'autre
# panne de se manifester). 12 combinaisons :
#   --variante N  (1 à 12) force la combinaison n° N ; les sous-variantes restent aléatoires.
#   --annuler     annule les pannes de l'astreinte (et toute panne M16-E35 à E42 encore active).
# Réutilise panne_EXX_vN / verifier_EXX / annuler_EXX / resume_EXX des autres scripts, chargés en
# mode bibliothèque (WB_PANNES_LIB=1). Préconditions vérifiées une seule fois avant la première
# panne (témoins, k8s-par1, mediagenda-db, Velero) ; ordre d'injection A, B, C (une panne C peut
# rendre la base ou un nœud indisponibles) ; annulation dans l'ordre inverse.

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

declare -A _E43_NB=([E35]=4 [E36]=3 [E37]=2 [E38]=3 [E39]=4 [E40]=3 [E41]=3 [E42]=3)
_E43_ORDRE=(E41 E40 E39 E42 E35 E36 E38 E37)

_E43_combinaisons() {
  local a b c
  for a in E41 E40; do
    for b in E39 E42; do
      for c in E35 E36 E37 E38; do
        [[ "$a" == E40 && ( "$c" == E36 || "$c" == E37 ) ]] && continue
        printf '%s %s %s\n' "$a" "$b" "$c"
      done
    done
  done
}

_E43_annuler() {
  local liste e ex var
  liste="$(wb_marqueur_lire M16-E43)"
  local -a actives=()
  for ((e = ${#_E43_ORDRE[@]} - 1; e >= 0; e--)); do
    ex="${_E43_ORDRE[e]}"
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M16-$ex"; then
      actives+=("$ex")
    fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M16-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M16-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M16-$ex"
  done
  wb_marqueur_suppr M16-E43
  echo "Astreinte M16-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 16 43"
}

# _E43_prealables — une seule fois, avant la première panne.
_E43_prealables() {
  local bsl
  WB_EX=M16-E43
  WB_VAR=0
  m16_temoins || { echo "Témoins du palier 4 impossibles à préparer : rien n'est cassé." >&2; return 1; }
  m16_sain_csi || { echo "k8s-par1 pas sain avant l'astreinte : rien n'est cassé." >&2; return 1; }
  m16_cnpg_sain || { echo "mediagenda-db n'a pas ses 3 instances prêtes : rien n'est cassé." >&2; return 1; }
  bsl="$(m16_bsl)"
  [[ -n "$bsl" && "$(m16_bsl_phase "$bsl")" == Available ]] \
    || { echo "Velero : aucun emplacement de sauvegarde Available : rien n'est cassé." >&2; return 1; }
  m16_horodater E43
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
  for ex in E43 "${_E43_ORDRE[@]}"; do
    if wb_marqueur_existe "M16-$ex"; then
      echo "Une panne M16-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
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
  local a b c
  read -r a b c <<<"${combis[combi - 1]}"

  echo "Injection en cours (trois pannes, cela peut prendre une dizaine de minutes)…"
  _E43_prealables || return 1
  _M16_ASTREINTE=1
  local -a choisies=() lignes=()
  local liste="" v
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" || "$ex" == "$c" ]] || continue
    v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    WB_EX="M16-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible (lab pas sain ?) : remise en état." >&2
      wb_marqueur_ecrire "M16-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M16-E43 "$liste"
      unset _M16_ASTREINTE
      _E43_annuler >/dev/null
      return 1
    fi
    # La fonction de panne a pu basculer sur une autre variante (WB_VAR modifié, m16_essayer).
    wb_marqueur_ecrire "M16-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M16-E43 "$liste"
    if ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      unset _M16_ASTREINTE
      _E43_annuler >/dev/null
      return 1
    fi
    choisies+=("$ex")
  done
  unset _M16_ASTREINTE

  for ex in "${choisies[@]}"; do
    WB_EX="M16-$ex"
    WB_VAR="$(wb_marqueur_lire "M16-$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-4350 — De : Nadia Roussel (responsable astreinte) — priorité P1" \
    "Tu es d'astreinte. Jeudi, 1 h 50 : trois remontées en vingt minutes sur k8s-par1 :" \
    "${lignes[@]}" \
    "La recette de MédiAgenda reprend à 8 h avec des données réelles anonymisées : à ce moment-là," \
    "la base doit être restaurable à un instant donné, sauvegardée hors du cluster, et les volumes" \
    "doivent se créer et se monter. Tiens-moi informée toutes les 30 min (#astreinte), puis rédige" \
    "le post-mortem avec le modèle de l'équipe (modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Accès : kubectl (ton identité), SSH vers k8s-w01-03 et ceph01, console « qm terminal » depuis pve01." \
    "Temps cible : 2 h (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 16 43"
}
