# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# break-E38.sh — M24-E38 « Panne : « jeton expiré » à la première connexion »
#
#   1. horloge de idp01 reculée de 10 minutes (chrony arrêté puis « date -s ») : chaque jeton naît
#      déjà expiré (exp = maintenant − 5 min) ; les codes OTP sont refusés aussi ;
#   2. durée de vie du jeton d'accès du royaume medisphere passée à 10 secondes (réglage du royaume,
#      exporté avant) : chaque service reçoit un jeton expiré avant même de l'avoir utilisé, ou presque ;
#   3. horloge du DERNIER nœud de contrôle avancée de 7 minutes : kube-apiserver de ce nœud voit tous
#      les jetons OIDC (5 min) expirés ; kubectl échoue une fois sur trois (répartition par la VIP).
#      Avancée (jamais reculée) : un nœud en retard serait déclaré NotReady (bail du kubelet ancien).
#      Effet de bord borné : un jeton de compte de service émis par CE kube-apiserver pendant la panne
#      a un « nbf » dans le futur pour les deux autres (tolérance d'une minute) : un pod créé pendant
#      la panne peut voir ses appels à l'API refusés quelques minutes. Durée de la panne à garder courte.
# Jamais pve01, jamais une passerelle (source de temps du lab), jamais etcd en dehors de ce nœud.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m24-commun.sh
source "$WB_ROOT/modules/24-identite/corrige/pannes/_m24-commun.sh"

_e38_cp_cible() { printf '%s\n' "${_M24_CP[${#_M24_CP[@]} - 1]}"; }

# _e38_decaler HÔTE SECONDES — arrête la synchronisation et décale l'horloge (signe compris).
_e38_decaler() {
  m24_wb_exec "$1" "D=$2" <<'EOF'
u="$(unite_temps)"
systemctl is-active --quiet "$u" && echo actif > "$WB_DIR/$WB_EX.temps" || echo inactif > "$WB_DIR/$WB_EX.temps"
systemctl stop "$u"
date -s "@$(( $(date +%s) + D ))" >/dev/null
journal "$u arrêté, horloge décalée de $D s"
EOF
}

# _e38_resynchroniser HÔTE — relance chrony et force un pas immédiat.
_e38_resynchroniser() {
  m24_wb_exec "$1" <<'EOF'
u="$(unite_temps)"
systemctl start "$u"
sleep 2
chronyc -a makestep >/dev/null 2>&1 || chronyc makestep >/dev/null 2>&1 || true
rm -f "$WB_DIR/$WB_EX.temps"
journal "$u relancé, makestep"
EOF
}

_m24E38_une() {
  local n="$1" r
  m24_ecrire E38 variante "$n"
  case "$n" in
    1)
      m24_sain_hote "$_M24_IDP" || return 1
      _e38_decaler "$_M24_IDP" -600 || return 1
      ;;
    2)
      r="$(m24_kc GET "" 2>/dev/null)" || r=""
      [[ -n "$r" ]] || return 1
      m24_kc_sauver E38 royaume "$(jq -c '{accessTokenLifespan, accessTokenLifespanForImplicitFlow}' <<<"$r")"
      m24_kc_json PUT "" '{"accessTokenLifespan": 10}' >/dev/null || return 1
      ;;
    3)
      m24_sain_hote "$(_e38_cp_cible)" || return 1
      _e38_decaler "$(_e38_cp_cible)" 420 || return 1
      ;;
  esac
  m24_journal E38 "variante $n posée"
}

verifier_E38() {
  local e
  case "$WB_VAR" in
    1) e="$(m24_ecart_horloge "$_M24_IDP")" && ((e <= -500)) ;;
    2) [[ "$(m24_kc GET "" 2>/dev/null | jq -r '.accessTokenLifespan // empty')" == 10 ]] ;;
    3) e="$(m24_ecart_horloge "$(_e38_cp_cible)")" && ((e >= 360)) ;;
    *) return 1 ;;
  esac
}

panne_E38_v1() { m24_sain_keycloak && m24_essayer E38 3 1; }
panne_E38_v2() { m24_sain_keycloak && m24_essayer E38 3 2; }
panne_E38_v3() { m24_sain_keycloak && m24_essayer E38 3 3; }

annuler_E38() {
  local v s e
  v="$(m24_lire E38 variante)"
  case "$v" in
    1 | 3)
      local h="$_M24_IDP"
      [[ "$v" == 3 ]] && h="$(_e38_cp_cible)"
      # Toujours sans danger : relancer chrony et faire un pas vers l'heure de la passerelle.
      e="$(m24_ecart_horloge "$h" 2>/dev/null || echo 0)"
      if ((e > 60 || e < -60)) || ! m24_ssh "$h" 'systemctl is-active --quiet chrony || systemctl is-active --quiet chronyd' >/dev/null 2>&1; then
        _e38_resynchroniser "$h" >/dev/null 2>&1 || wb_avert "$h : chrony non relancé (systemctl start chrony ; chronyc makestep)"
      fi
      ;;
    2)
      s="$(m24_kc_sauve E38 royaume || true)"
      if [[ -n "$s" && "$(m24_kc GET "" 2>/dev/null | jq -r '.accessTokenLifespan // empty' 2>/dev/null || true)" == 10 ]]; then
        m24_kc_json PUT "" "$(jq -c '{accessTokenLifespan}' <<<"$s")" >/dev/null 2>&1 || wb_avert "durée du jeton d'accès non rétablie"
      fi
      ;;
  esac
  m24_oublier E38 variante
  m24_kc_oublier E38 royaume
  m24_journal E38 "annulation"
}

resume_E38() { echo "« Jeton expiré » ou « token is expired » dès la connexion, pour certains services ou certaines requêtes."; }

symptome_E38() {
  local detail
  case "$WB_VAR" in
    1) detail="Grafana, Argo CD et kubectl : je me connecte, et tout de suite « token expired » / « jeton expiré ». Karim ajoute que son code OTP est refusé." ;;
    2) detail="Je me connecte à Argo CD, ça marche dix secondes, puis l'interface me renvoie au SSO en boucle ; kubectl redemande le navigateur sans arrêt." ;;
    *) detail="kubectl marche… une fois sur trois. Les autres fois : « Unauthorized ». Les interfaces web, elles, vont bien." ;;
  esac
  wb_symptome "Ticket INC-5138 — De : Karim Benali" \
    "$detail" \
    "Personne n'a rien déployé depuis hier soir. J'ai vidé mes cookies et le cache de kubelogin : pareil." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 24 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 24 E38 3 "$@"; }
fi
