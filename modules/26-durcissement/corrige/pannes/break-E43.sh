# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants entre apostrophes
# break-E43.sh — M26-E43 « Astreinte : la semaine avant l'audit »
#
# Tire DEUX pannes distinctes parmi M26-E35 à M26-E42 et les injecte, PLUS une dérive de conformité sur
# une VM non critique (réglage de durcissement défait : SSH PermitRootLogin, un sysctl). Réutilise
# panne_EXX_vN / verifier_EXX / annuler_EXX / resume_EXX des autres scripts, chargés en mode bibliothèque
# (WB_PANNES_LIB=1).
#   --variante N  force le couple n° N (ordre lexicographique des couples admis) ; les sous-variantes
#                 restent aléatoires. --annuler annule tout (couple + dérive).
# Règles : au plus UNE parmi {E40, E41} (toutes deux au niveau du nœud) ; au plus UNE parmi {E38, E39}
# (toutes deux au niveau des services d'hôte). Ordre d'injection : admission (E35/E36/E37), puis hôtes
# (E38/E39), puis nœuds (E40/E41/E42) ; la dérive est posée AVANT (sudo intact) et retirée APRÈS.
#
# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m26-commun.sh
source "$WB_ROOT/modules/26-durcissement/corrige/pannes/_m26-commun.sh"

_WB_E43_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck disable=SC2034  # lu par les scripts break-EXX.sh sourcés (ils ne redéfinissent pas main)
WB_PANNES_LIB=1
for _e in E35 E36 E37 E38 E39 E40 E41 E42; do
  # shellcheck disable=SC1090
  source "$_WB_E43_DIR/break-$_e.sh"
done
unset WB_PANNES_LIB _e

declare -A _E43_NB=([E35]=3 [E36]=4 [E37]=4 [E38]=3 [E39]=3 [E40]=3 [E41]=3 [E42]=3)
_E43_ORDRE=(E35 E36 E37 E38 E39 E40 E41 E42)
_E43_DERIVE_VM="${WB_M26_DERIVE_VM:-nbx01}"

_E43_couples() {
  local -a ex=(E35 E36 E37 E38 E39 E40 E41 E42)
  local i j t
  for ((i = 0; i < ${#ex[@]}; i++)); do
    for ((j = i + 1; j < ${#ex[@]}; j++)); do
      t=" ${ex[i]} ${ex[j]} "
      [[ "$t" == *" E40 "* && "$t" == *" E41 "* ]] && continue
      [[ "$t" == *" E38 "* && "$t" == *" E39 "* ]] && continue
      printf '%s %s\n' "${ex[i]}" "${ex[j]}"
    done
  done
}

_e43_derive_poser() {
  m26_hote_sain "$_E43_DERIVE_VM" || return 1
  # Mémorisé AVANT l'injection : une injection à moitié faite s'annule aussi (sauvegardes sur la VM).
  m26_ecrire E43 derive "$_E43_DERIVE_VM"
  # WB_EX fixé : les sauvegardes de la dérive ne se mêlent pas à celles d'une panne E38 sur la même VM.
  WB_EX=M26-E43 m26_wb_exec "$_E43_DERIVE_VM" >/dev/null <<'EOF' || return 1
# sshd garde la PREMIÈRE valeur lue : le fichier doit être lu avant 00-durcissement.conf (rôle, E10/E11),
# d'où un nom qui le précède dans l'ordre alphabétique (sinon la dérive serait sans effet).
d=/etc/ssh/sshd_config.d/00-acces-urgence.conf
sauver "$d"
printf '# ajouté à la main pendant un dépannage\nPermitRootLogin yes\nX11Forwarding yes\n' > "$d"
sshd -t 2>/dev/null || { rm -f "$d"; echo "configuration sshd invalide" >&2; exit 1; }
s=/etc/sysctl.d/99-wb-derive.conf
sauver "$s"
printf 'kernel.dmesg_restrict = 0\n' > "$s"
sysctl -qw kernel.dmesg_restrict=0 2>/dev/null || true
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
# Effet constaté (§11.10) : sshd applique bien la dérive.
sshd -T 2>/dev/null | grep -qi '^permitrootlogin yes' || { echo "dérive sans effet sur sshd" >&2; exit 1; }
journal "dérive de conformité : PermitRootLogin yes, X11Forwarding yes, kernel.dmesg_restrict=0"
EOF
}
_e43_derive_defaire() {
  local vm
  vm="$(m26_lire E43 derive)"
  [[ -n "$vm" ]] || return 0
  WB_EX=M26-E43 m26_wb_exec "$vm" >/dev/null <<'EOF' || wb_avert "annulation de la dérive incomplète sur $vm"
restaurer_fichiers
sysctl -qw kernel.dmesg_restrict=1 2>/dev/null || true
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
journal "annulation : dérive de conformité rétablie"
EOF
  m26_oublier E43 derive
}

_E43_annuler() {
  local liste ex var
  liste="$(wb_marqueur_lire M26-E43)"
  local -a actives=()
  for ((i = ${#_E43_ORDRE[@]} - 1; i >= 0; i--)); do
    ex="${_E43_ORDRE[i]}"
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M26-$ex"; then actives+=("$ex"); fi
  done
  for ex in "${actives[@]}"; do
    var="$(wb_marqueur_lire "M26-$ex")"
    [[ -n "$var" ]] || var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
    WB_EX="M26-$ex"
    WB_VAR="${var:-annulation}"
    "annuler_$ex" || true
    wb_marqueur_suppr "M26-$ex"
  done
  # La dérive en DERNIER : si E38 a cassé sudo sur la même VM, il faut d'abord l'avoir annulée.
  _e43_derive_defaire
  wb_marqueur_suppr M26-E43
  echo "Astreinte M26-E43 annulée : pannes ${actives[*]:-aucune} et dérive retirées. Contrôle : lab/bin/check 26 43"
}

main() {
  local couple="" annuler=0
  while (($#)); do
    case "$1" in
      --variante) if (($# < 2)); then echo "--variante attend un numéro" >&2; return 2; fi; couple="$2"; shift 2 ;;
      --variante=*) couple="${1#*=}"; shift ;;
      --annuler) annuler=1; shift ;;
      *) echo "Option inconnue : $1 (attendu : --variante N, --annuler)" >&2; return 2 ;;
    esac
  done
  if ((annuler)); then _E43_annuler; return 0; fi

  local ex
  for ex in E43 "${_E43_ORDRE[@]}"; do
    if wb_marqueur_existe "M26-$ex"; then
      echo "Une panne M26-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done

  local -a couples
  mapfile -t couples < <(_E43_couples)
  [[ -z "$couple" ]] && couple=$((RANDOM % ${#couples[@]} + 1))
  if ! [[ "$couple" =~ ^[0-9]+$ ]] || ((couple < 1 || couple > ${#couples[@]})); then
    echo "Variante invalide : $couple (1 à ${#couples[@]})" >&2
    return 2
  fi
  local a b
  read -r a b <<<"${couples[couple - 1]}"

  echo "Injection en cours (deux pannes, une dérive, des MR et des synchronisations : 15 à 45 minutes)…"
  WB_EX=M26-E43
  WB_VAR=0
  m26_kube_sain || { echo "Cluster pas sain avant l'astreinte : rien n'est cassé." >&2; return 1; }
  wb_marqueur_ecrire M26-E43 ""

  local -a choisies=() lignes=()
  local liste="" v
  # La dérive d'abord, tant que sudo fonctionne partout (E38 peut ensuite casser sudo sur la même VM).
  if ! _e43_derive_poser; then
    echo "Dérive de conformité impossible à poser : remise en état." >&2
    _E43_annuler >/dev/null
    return 1
  fi
  for ex in "${_E43_ORDRE[@]}"; do
    [[ "$ex" == "$a" || "$ex" == "$b" ]] || continue
    v=$((RANDOM % ${_E43_NB[$ex]} + 1))
    WB_EX="M26-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null; then
      echo "Injection de $ex impossible (lab pas sain ?) : remise en état." >&2
      wb_marqueur_ecrire "M26-$ex" "$WB_VAR"; liste+="$ex:$WB_VAR "; wb_marqueur_ecrire M26-E43 "$liste"
      _E43_annuler >/dev/null
      return 1
    fi
    wb_marqueur_ecrire "M26-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M26-E43 "$liste"
    if ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être constatée après injection : remise en état, rien n'est cassé." >&2
      _E43_annuler >/dev/null
      return 1
    fi
    choisies+=("$ex")
  done

  for ex in "${choisies[@]}"; do
    WB_EX="M26-$ex"
    WB_VAR="$(wb_marqueur_lire "M26-$ex")"
    lignes+=("- $("resume_$ex")")
  done
  lignes+=("- La conformité d'une VM a baissé (un réglage de durcissement a été défait).")

  wb_symptome "Ticket INC-5343 — De : Nadia Roussel (responsable astreinte) — priorité P2" \
    "Tu es d'astreinte, la semaine avant l'audit HDS. Plusieurs remontées à la fois :" \
    "${lignes[@]}" \
    "L'auditeur vient dans quelques jours : à la fin, le parc doit être mesuré et conforme, l'admission" \
    "doit refuser ce qui ne l'est pas, la détection doit fonctionner, et tu dois pouvoir montrer une" \
    "réponse à incident. Tiens-moi informée toutes les 30 min, puis rédige le post-mortem et RB-265" \
    "(semaine avant l'audit) avec le modèle de l'équipe." \
    "" \
    "Rappel : jamais kube-system/kyverno/argocd ; un nœud à la fois ; les corrections passent par Git." \
    "Temps cible : 2 h (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 26 43"
}
