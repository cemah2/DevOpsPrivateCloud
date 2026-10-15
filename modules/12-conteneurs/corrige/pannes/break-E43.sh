# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E43.sh — M12-E43 « Astreinte : la pile de recette est en panne »
#
# Trois pannes simultanées sur la pile de recette de ctr01, une par « étage », tirées au hasard :
#   A. démarrage de l'API : E35 v1 (variable renommée), E35 v2 (forme exec), E41 v1 (mémoire),
#      E41 v3 (sonde impossible + autoheal) ;
#   B. données et réseau : E36 v1 (propriétaire du volume), E37 v1 à v4 (réseau, alias, nftables) ;
#   C. hôte et voisins : E39 v1 à v3 (disque plein), E35 v3 (MédiDoc sur scratch) — si C tire E35,
#      A est tiré parmi E41 seulement (un exercice ne porte qu'une panne à la fois).
# Réutilise panne_EXX_vN / verifier_EXX / annuler_EXX / resume_EXX des scripts des exercices, chargés
# en mode bibliothèque (WB_PANNES_LIB=1). Ordre d'injection : B (vérifiée tant que l'API répond),
# puis A, puis C (le disque plein en dernier : les autres injections ont besoin d'écrire).
# Annulation dans l'ordre inverse, puis une seule remise de la pile de recette à sa référence.
#
#   --variante N  (1 à 3) force le tirage de l'étage C : 1 = disque plein (E39), 2 = MédiDoc (E35 v3),
#                 3 = disque plein et API sur E41 ; les autres tirages restent aléatoires.
#   --annuler     annule les trois pannes (et toute panne M12-E35 à E41 encore marquée active).

_WB_E43_DIR="$(dirname "${BASH_SOURCE[0]}")"
WB_PANNES_LIB=1
# shellcheck source=break-E35.sh
source "$_WB_E43_DIR/break-E35.sh"
# shellcheck source=break-E36.sh
source "$_WB_E43_DIR/break-E36.sh"
# shellcheck source=break-E37.sh
source "$_WB_E43_DIR/break-E37.sh"
# shellcheck source=break-E39.sh
source "$_WB_E43_DIR/break-E39.sh"
# shellcheck source=break-E41.sh
source "$_WB_E43_DIR/break-E41.sh"
unset WB_PANNES_LIB

_E43_ORDRE=(E36 E37 E35 E41 E39)

_e43_tirer() {
  local -a l=("$@")
  printf '%s\n' "${l[RANDOM % ${#l[@]}]}"
}

_e43_annuler() {
  local liste ex var e
  liste="$(wb_marqueur_lire M12-E43)"
  _M12_ASTREINTE=1
  for ((e = ${#_E43_ORDRE[@]} - 1; e >= 0; e--)); do
    ex="${_E43_ORDRE[e]}"
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M12-$ex"; then
      var="$(wb_marqueur_lire "M12-$ex")"
      if [[ -z "$var" ]]; then
        var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
      fi
      WB_EX="M12-$ex"
      WB_VAR="${var:-annulation}"
      "annuler_$ex" || true
      wb_marqueur_suppr "M12-$ex"
    fi
  done
  unset _M12_ASTREINTE
  WB_EX=M12-E43
  WB_VAR=annulation
  m12_recette_installer >/dev/null || wb_avert "pile de recette non réinstallée : relance lab/bin/break 12 43 --annuler"
  wb_marqueur_suppr M12-E43
  echo "Astreinte M12-E43 annulée : pile de recette remise à sa référence. Contrôle : lab/bin/check 12 43"
}

main() {
  local forcer="" annuler=0
  while (($#)); do
    case "$1" in
      --variante)
        if (($# < 2)); then echo "--variante attend un numéro" >&2; return 2; fi
        forcer="$2"; shift 2 ;;
      --variante=*) forcer="${1#*=}"; shift ;;
      --annuler) annuler=1; shift ;;
      *) echo "Option inconnue : $1 (attendu : --variante N, --annuler)" >&2; return 2 ;;
    esac
  done
  if ((annuler)); then
    _e43_annuler
    return 0
  fi
  if [[ -n "$forcer" ]] && ! [[ "$forcer" =~ ^[1-3]$ ]]; then
    echo "Variante invalide : $forcer (1 à 3)" >&2
    return 2
  fi

  WB_EX=M12-E43
  WB_VAR=0
  if wb_marqueur_existe M12-E43 || m12_autres_pannes; then
    echo "Une panne du module 12 est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
    return 1
  fi

  # Tirage : étage C, puis A (compatible), puis B
  local c a b mode
  mode="${forcer:-$((RANDOM % 3 + 1))}"
  case "$mode" in
    2) c="E35:3"; a="$(_e43_tirer E41:1 E41:3)" ;;
    3) c="E39:$((RANDOM % 3 + 1))"; a="$(_e43_tirer E41:1 E41:3)" ;;
    *) c="E39:$((RANDOM % 3 + 1))"; a="$(_e43_tirer E35:1 E35:2 E41:1 E41:3)" ;;
  esac
  b="$(_e43_tirer E36:1 E37:1 E37:2 E37:3 E37:4)"

  echo "Injection en cours (trois pannes : cinq à dix minutes, davantage la première fois)…"
  m12_recette_installer || { echo "Pile de recette impossible à préparer : rien n'est cassé." >&2; return 1; }
  m12_recette_saine || { echo "Pile de recette pas saine avant l'astreinte : rien n'est cassé." >&2; return 1; }

  _M12_ASTREINTE=1
  local -a lignes=()
  local liste="" p ex v
  for p in "$b" "$a" "$c"; do
    ex="${p%%:*}"; v="${p##*:}"
    WB_EX="M12-$ex"
    WB_VAR="$v"
    if ! "panne_${ex}_v${v}" >/dev/null || ! "verifier_$ex" 2>/dev/null; then
      echo "La panne $ex n'a pas pu être injectée ou constatée : remise en état, rien n'est cassé." >&2
      wb_marqueur_ecrire "M12-$ex" "$WB_VAR"
      liste+="$ex:$WB_VAR "
      wb_marqueur_ecrire M12-E43 "$liste"
      unset _M12_ASTREINTE
      _e43_annuler >/dev/null
      return 1
    fi
    wb_marqueur_ecrire "M12-$ex" "$WB_VAR"
    liste+="$ex:$WB_VAR "
    wb_marqueur_ecrire M12-E43 "$liste"
    lignes+=("- $("resume_$ex")")
  done
  unset _M12_ASTREINTE
  WB_EX=M12-E43

  wb_symptome "Ticket INC-3943 — De : Nadia Roussel (responsable astreinte) — priorité P2" \
    "Tu es d'astreinte. Jeudi, 6 h 50 : la recette de MédiAgenda sur ctr01 est inutilisable, et" \
    "l'équipe de Julien lance sa campagne de tests de non-régression à 9 h. Remontées :" \
    "${lignes[@]}" \
    "Lucas a « fait plusieurs petites choses » sur ctr01 cette semaine et ne se souvient plus" \
    "lesquelles. Rétablis la pile complète (API, base, cache, MédiDoc), tiens-moi informée toutes" \
    "les 30 min (#astreinte), puis rédige le post-mortem avec le modèle de l'équipe" \
    "(modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Accès : ssh ctr01 ; pile dans /srv/recette (sudo docker compose …)." \
    "Temps cible : 1 h 30 (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 12 43"
}
