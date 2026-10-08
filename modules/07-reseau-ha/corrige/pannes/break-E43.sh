# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M07-E43 « Astreinte : la bordure en panne »
#
# Tire TROIS pannes distinctes parmi M07-E35 à M07-E42 (variante de chacune tirée au hasard), plus
# une panne propre à l'astreinte sur la bordure, et les injecte ensemble. Réutilise les fonctions
# panne_EXX_vN / verifier_EXX / annuler_EXX / resume_EXX des autres scripts (WB_PANNES_LIB=1).
#
# Panne propre (P) — sur la passerelle de SECOURS (celle qui ne porte pas la VIP 10.10.10.1), donc
# sans effet sur le trafic tant qu'aucune bascule n'a lieu, et jamais sur la passerelle active :
#   a. keepalived arrêté et désactivé (« maintenance » jamais terminée) → plus de redondance ;
#   b. conntrackd arrêté et désactivé → plus de synchronisation des connexions (variante a si
#      conntrackd n'est pas installé).
#
# Triplets exclus (pannes qui se masquent : même flux de test srv01 ↔ srv02 ou même Nginx) :
# E38+E39, E38+E41, E38+E42, E41+E42.
#   --variante N  force le triplet n° N (ordre lexicographique) ; sous-variantes aléatoires.
#   --annuler     annule tout (et toute panne M07-E35 à E42 encore marquée active).
#
# Ordre d'injection : E40, E36, E37, E39, E35, E42, E41, E38, puis la panne propre ; chaque panne est
# constatée sur place juste après son injection ; en cas d'échec, tout est annulé.

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

declare -A _E43_NB=([E35]=4 [E36]=4 [E37]=3 [E38]=3 [E39]=4 [E40]=3 [E41]=3 [E42]=3)
_E43_ORDRE=(E40 E36 E37 E39 E35 E42 E41 E38)
_E43_EXCLUS=" E38+E39 E38+E41 E38+E42 E41+E42 "

_E43_triplets() {
  local -a ex=(E35 E36 E37 E38 E39 E40 E41 E42)
  local i j k a b c
  for ((i = 0; i < ${#ex[@]}; i++)); do
    for ((j = i + 1; j < ${#ex[@]}; j++)); do
      for ((k = j + 1; k < ${#ex[@]}; k++)); do
        a="${ex[i]}"; b="${ex[j]}"; c="${ex[k]}"
        [[ "$_E43_EXCLUS" == *" $a+$b "* || "$_E43_EXCLUS" == *" $a+$c "* || "$_E43_EXCLUS" == *" $b+$c "* ]] && continue
        printf '%s %s %s\n' "$a" "$b" "$c"
      done
    done
  done
}

# ---------------------------------------------------------------------------
# Panne propre : la passerelle de secours n'est plus prête
# ---------------------------------------------------------------------------

# _e43_secours — affiche la passerelle qui ne porte PAS la VIP 10.10.10.1 (rien si indéterminé).
_e43_secours() {
  local v1=0 v2=0
  if ! m07_existe gw01 || ! m07_existe gw02; then return 0; fi
  m07_vip_sur gw01 10.10.10.1 && v1=1
  m07_vip_sur gw02 10.10.10.1 && v2=1
  if ((v1 == 1 && v2 == 0)); then echo gw02; elif ((v1 == 0 && v2 == 1)); then echo gw01; fi
}

_e43_propre_injecter() {
  local cible rc=0
  cible="$(_e43_secours)"
  if [[ -z "$cible" ]]; then
    wb_avert "impossible de déterminer la passerelle de secours (gw02 absente, ou VIP 10.10.10.1 sur zéro ou deux passerelles)"
    return 1
  fi
  m07_ecrire E43 cible "$cible"
  m07_exec "$cible" N="$((RANDOM % 2 + 1))" <<'EOF' || rc=$?
s=keepalived
if [ "$N" = 2 ] && systemctl is-active -q conntrackd 2>/dev/null; then s=conntrackd; fi
systemctl is-active -q "$s" || exit 1
systemctl disable --now "$s" >/dev/null 2>&1 || exit 1
defaire_noter "! systemctl is-active -q $s" "systemctl enable --now $s"
journal "$s arrêté et désactivé (panne propre de l'astreinte)"
echo "$s"
EOF
  if ((rc != 0)); then
    wb_avert "$cible : arrêt du service impossible"
    return 1
  fi
}

_e43_propre_service() {
  m07_exec "$(m07_lire E43 cible)" 2>/dev/null <<'EOF' || true
for s in keepalived conntrackd; do
  if ! systemctl is-active -q "$s" && grep -qs "$s arrêté" "$WB_DIR/pannes.log"; then echo "$s"; fi
done
EOF
}

_e43_propre_annuler() {
  local cible
  cible="$(m07_lire E43 cible)"
  [[ -n "$cible" ]] || return 0
  WB_EX=M07-E43
  m07_annuler_hote "$cible"
}

# ---------------------------------------------------------------------------

_E43_annuler() {
  local liste e ex var
  liste="$(wb_marqueur_lire M07-E43)"
  local -a actives=()
  for ((e = ${#_E43_ORDRE[@]} - 1; e >= 0; e--)); do
    ex="${_E43_ORDRE[e]}"
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M07-$ex"; then
      actives+=("$ex")
    fi
  done
  _e43_propre_annuler
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M07-$ex")"
    if [[ -z "$var" ]]; then
      var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    fi
    WB_EX="M07-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M07-$ex"
  done
  wb_marqueur_suppr M07-E43
  echo "Astreinte M07-E43 annulée : pannes ${actives[*]:-aucune} et panne de la bordure retirées. Contrôle : lab/bin/check 07 43"
}

main() {
  local triplet="" annuler=0
  while (($#)); do
    case "$1" in
      --variante)
        if (($# < 2)); then echo "--variante attend un numéro" >&2; return 2; fi
        triplet="$2"; shift 2 ;;
      --variante=*) triplet="${1#*=}"; shift ;;
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
    if wb_marqueur_existe "M07-$ex"; then
      echo "Une panne M07-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done

  local -a triplets
  mapfile -t triplets < <(_E43_triplets)
  if [[ -z "$triplet" ]]; then
    triplet=$((RANDOM % ${#triplets[@]} + 1))
  fi
  if ! [[ "$triplet" =~ ^[0-9]+$ ]] || ((triplet < 1 || triplet > ${#triplets[@]})); then
    echo "Variante invalide : $triplet (1 à ${#triplets[@]})" >&2
    return 2
  fi
  local a b c
  read -r a b c <<<"${triplets[triplet - 1]}"

  echo "Injection en cours (quatre pannes, cela peut prendre plusieurs minutes)…"
  local -a choisies=() lignes=()
  local liste="" v
  wb_marqueur_ecrire M07-E43 "$liste"
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" || "$ex" == "$c" ]] || continue
    v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    WB_EX="M07-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de la panne $ex impossible (lab pas sain ?) : remise en état." >&2
      wb_marqueur_ecrire "M07-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M07-E43 "$liste"
      _E43_annuler >/dev/null
      return 1
    fi
    # La fonction de panne a pu basculer sur une autre variante (WB_VAR modifié, m07_essayer).
    wb_marqueur_ecrire "M07-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M07-E43 "$liste"
    if ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      _E43_annuler >/dev/null
      return 1
    fi
    choisies+=("$ex")
  done

  WB_EX=M07-E43
  WB_VAR=propre
  if ! _e43_propre_injecter >/dev/null || [[ -z "$(_e43_propre_service)" ]]; then
    echo "La panne de la bordure n'a pas pu être posée : remise en état, rien n'est cassé." >&2
    _E43_annuler >/dev/null
    return 1
  fi

  for ex in "${choisies[@]}"; do
    WB_EX="M07-$ex"
    WB_VAR="$(wb_marqueur_lire "M07-$ex")"
    lignes+=("- $("resume_$ex")")
  done
  lignes+=("- La sonde de la bordure (ms-verif-reseau) est orange : « redondance de la bordure dégradée ».")

  wb_symptome "Ticket INC-3410 — De : Nadia Roussel (responsable astreinte) — priorité P2" \
    "Tu es d'astreinte. Mardi, 6 h 40 : plusieurs remontées sur le réseau et la bordure :" \
    "${lignes[@]}" \
    "Une bascule de la bordure est planifiée à 9 h pour une maintenance de pve01 : tout doit être" \
    "redondant et sain d'ici là. Tiens-moi informée toutes les 30 min, puis rédige le post-mortem" \
    "avec le modèle de l'équipe (modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Accès de secours : agent QEMU (qm guest exec) pour toutes les VMs, console qm terminal." \
    "Temps cible : 2 h 30 (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 07 43"
}
