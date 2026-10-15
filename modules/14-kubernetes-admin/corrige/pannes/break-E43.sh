# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M14-E43 « Astreinte : le cluster en détresse »
#
# Tire TROIS pannes distinctes parmi M14-E35 à M14-E42 (variante de chacune tirée au hasard) et les
# injecte ensemble. Réutilise panne_EXX_vN / verifier_EXX / annuler_EXX / resume_EXX des autres
# scripts, chargés en mode bibliothèque (WB_PANNES_LIB=1).
#
#   --variante N  (1 à 40) force le trio n° N (ordre lexicographique des trios admis) ; les
#                 sous-variantes restent aléatoires.
#   --annuler     annule les trois pannes (et toute panne M14-E35 à E42 encore marquée active).
#
# Règles :
#   - au plus UNE panne parmi E36, E37, E38 (elles modifient toutes le déploiement témoin « agenda ») ;
#     si l'une d'elles est tirée avec E42, E42 prend une variante qui ne touche pas « agenda » (1 à 3) ;
#   - c'est le seul exercice qui peut toucher deux nœuds de contrôle à la fois (E39 et E40) : un
#     instantané etcd est d'abord pris ET vérifié (snapshot status), sinon rien n'est cassé ;
#     l'instantané reste sur le premier nœud de contrôle sain, /var/lib/workbook/M14-E43.instantane.db,
#     jusqu'à l'annulation ;
#   - avant la première injection : témoins prêts et cluster sain (une seule fois, puis
#     _M14_ASTREINTE=1 dispense chaque panne de ces contrôles, que la précédente ferait échouer) ;
#   - ordre d'injection (dépendances) : pannes de charge de travail (E36/E37/E38), DNS (E42), nœud
#     (E35), accès (E41 : peut rendre ton kubeconfig inutilisable), etcd (E40 : peut bloquer toute
#     écriture), API (E39 : peut couper la VIP) en dernier. Annulation dans l'ordre inverse.

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

declare -A _E43_NB=([E35]=6 [E36]=4 [E37]=4 [E38]=4 [E39]=4 [E40]=3 [E41]=4 [E42]=4)
_E43_ORDRE=(E38 E37 E36 E42 E35 E41 E40 E39)

# _E43_trios — trios admis (au plus un de E36/E37/E38), un par ligne.
_E43_trios() {
  local -a ex=(E35 E36 E37 E38 E39 E40 E41 E42)
  local i j k p e
  for ((i = 0; i < ${#ex[@]}; i++)); do
    for ((j = i + 1; j < ${#ex[@]}; j++)); do
      for ((k = j + 1; k < ${#ex[@]}; k++)); do
        p=0
        for e in "${ex[i]}" "${ex[j]}" "${ex[k]}"; do [[ "$e" =~ ^E3[678]$ ]] && p=$((p + 1)); done
        ((p <= 1)) && printf '%s %s %s\n' "${ex[i]}" "${ex[j]}" "${ex[k]}"
      done
    done
  done
}

_E43_annuler() {
  local liste e ex var r
  liste="$(wb_marqueur_lire M14-E43)"
  local -a actives=()
  for ((e = ${#_E43_ORDRE[@]} - 1; e >= 0; e--)); do
    ex="${_E43_ORDRE[e]}"
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M14-$ex"; then
      actives+=("$ex")
    fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M14-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M14-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M14-$ex"
  done
  WB_EX=M14-E43
  WB_VAR=0
  r="$(m14_lire E43 relais)"
  if [[ -n "$r" ]]; then
    m14_wb_exec "$r" >/dev/null <<'EOF' || wb_avert "instantané de sécurité non effacé sur $r (/var/lib/workbook/M14-E43.instantane.db)"
rm -f "$WB_DIR/$WB_EX.instantane.db"
EOF
  fi
  m14_oublier E43 relais
  wb_marqueur_suppr M14-E43
  echo "Astreinte M14-E43 annulée : pannes ${actives[*]:-aucune} retirées. Contrôle : lab/bin/check 14 43"
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
    if wb_marqueur_existe "M14-$ex"; then
      echo "Une panne M14-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done

  local -a trios
  mapfile -t trios < <(_E43_trios)
  if [[ -z "$trio" ]]; then
    trio=$((RANDOM % ${#trios[@]} + 1))
  fi
  if ! [[ "$trio" =~ ^[0-9]+$ ]] || ((trio < 1 || trio > ${#trios[@]})); then
    echo "Variante invalide : $trio (1 à ${#trios[@]})" >&2
    return 2
  fi
  local a b c
  read -r a b c <<<"${trios[trio - 1]}"

  echo "Injection en cours (trois pannes et un instantané etcd : compte 5 à 15 minutes)…"
  WB_EX=M14-E43
  WB_VAR=0
  m14_temoins || { echo "Témoins du palier 4 impossibles à préparer : rien n'est cassé." >&2; return 1; }
  m14_sain || { echo "Cluster pas sain avant l'astreinte : rien n'est cassé." >&2; return 1; }
  local r
  r="$(m14_etcd_relais)" || { echo "Aucun membre etcd joignable : rien n'est cassé." >&2; return 1; }
  if ! m14_instantane_etcd "$r"; then
    echo "Instantané etcd de sécurité impossible ou invalide : rien n'est cassé." >&2
    return 1
  fi
  m14_ecrire E43 relais "$r"
  wb_marqueur_ecrire M14-E43 ""

  _M14_ASTREINTE=1
  local -a choisies=() lignes=()
  local liste="" v p=0
  [[ " $a $b $c " =~ \ E3[678]\  ]] && p=1
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" || "$ex" == "$c" ]] || continue
    if [[ "$ex" == E42 && "$p" == 1 ]]; then
      v=$((RANDOM % 3 + 1))
    else
      v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    fi
    WB_EX="M14-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible (lab pas sain ?) : remise en état." >&2
      wb_marqueur_ecrire "M14-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M14-E43 "$liste"
      unset _M14_ASTREINTE
      _E43_annuler >/dev/null
      return 1
    fi
    # La fonction de panne a pu basculer sur une autre variante (WB_VAR modifié, m14_essayer).
    wb_marqueur_ecrire "M14-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M14-E43 "$liste"
    if ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      unset _M14_ASTREINTE
      _E43_annuler >/dev/null
      return 1
    fi
    choisies+=("$ex")
  done
  unset _M14_ASTREINTE

  for ex in "${choisies[@]}"; do
    WB_EX="M14-$ex"
    WB_VAR="$(wb_marqueur_lire "M14-$ex")"
    lignes+=("- $("resume_$ex")")
  done

  wb_symptome "Ticket INC-4150 — De : Nadia Roussel (responsable astreinte) — priorité P1" \
    "Tu es d'astreinte. Jeudi, 4 h 05 : plusieurs remontées sur le cluster k8s-par1 :" \
    "${lignes[@]}" \
    "La recette de MédiAgenda commence à 8 h sur ce cluster : il doit être sain d'ici là." \
    "Tiens-moi informée toutes les 30 min, puis rédige le post-mortem avec le modèle de l'équipe" \
    "(modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Filet : un instantané etcd vérifié a été pris avant l'incident sur $r" \
    "(/var/lib/workbook/M14-E43.instantane.db) ; il ne sert qu'en dernier recours (RB-141)." \
    "Accès : SSH vers les nœuds, console « qm terminal » ou agent QEMU depuis pve01," \
    "admin.conf en Vault « critique » (bris de glace, à justifier dans le post-mortem)." \
    "Temps cible : 2 h 30 (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 14 43"
}
