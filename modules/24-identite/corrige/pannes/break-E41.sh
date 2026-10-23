# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# break-E41.sh — M24-E41 « Panne : boucle de redirection derrière OAuth2 Proxy »
#
# Cible : l'instance OAuth2 Proxy de mon01 (unité oauth2-proxy-mailpit, rôle oauth2_proxy de M24-E18,
# fichiers /etc/oauth2-proxy/mailpit/) et le client Keycloak « oauth2-proxy » (royaume medisphere).
# Les instances du cluster (Argo CD, selfHeal) ne sont pas touchées : une modification à la main y
# serait défaite en quelques secondes.
#   1. « cookie_domains » ajouté à oauth2-proxy.cfg (« pour partager la session avec Hubble », dit Lucas) :
#      un cookie « __Host- » ne doit PAS porter d'attribut Domain ; le navigateur rejette le cookie de
#      CSRF et celui de session ; chaque retour de Keycloak finit en « Login Failed: Unable to find a valid
#      CSRF token », et on recommence ;
#   2. l'URI de retour de mon01 retirée des redirections du client « oauth2-proxy » de Keycloak (Lucas
#      « nettoie » : remplacée par la même sans « :8443 ») : Keycloak refuse avant le formulaire
#      (« Invalid parameter: redirect_uri ») ;
#   3. « redirect_url » de l'instance de mon01 remplacée par celle de Hubble (copiée des valeurs du
#      cluster) : Keycloak l'accepte (elle est enregistrée pour le même client), la personne se connecte
#      et arrive sur hubble.apps…/oauth2/callback, qui ne connaît pas son jeton CSRF : « Login Failed ».
# Écarts assumés à la fiche (corrigé) : « cookie trop gros » et « en-têtes X-Forwarded-* de la Gateway »
# ne sont pas injectés (non reproductibles de façon fiable dans le lab ; traités en diagnostic).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m24-commun.sh
source "$WB_ROOT/modules/24-identite/corrige/pannes/_m24-commun.sh"

_E41_CLIENT=oauth2-proxy
_E41_INSTANCE="${WB_M24_O2P_INSTANCE:-mailpit}"
_E41_URL="${WB_M24_O2P_URL:-https://mon01.par1.medisphere.internal:8443}"
_E41_RAPPEL="$_E41_URL/oauth2/callback"
_E41_RAPPEL_SANS_PORT="${_E41_RAPPEL/:8443/}"
_E41_RAPPEL_HUBBLE="https://hubble.apps.par1.medisphere.internal/oauth2/callback"
_E41_CFG="/etc/oauth2-proxy/$_E41_INSTANCE/oauth2-proxy.cfg"
_E41_UNITE="oauth2-proxy-$_E41_INSTANCE.service"
_E41_MARQUE="# M24-E41"

# _e41_cfg_modifier 'ligne à ajouter' 'motif sed à supprimer (vide : aucun)' — sur mon01 : sauvegarde,
# modification, redémarrage ; si l'instance ne repart pas, le fichier est remis et le code vaut 10.
_e41_cfg_modifier() {
  m24_wb_exec "$_M24_MON01" "F=$_E41_CFG" "U=$_E41_UNITE" "AJOUT=$1" "SUPPR=$2" <<'EOF'
[ -f "$F" ] || exit 10
systemctl is-active --quiet "$U" || exit 10
sauver "$F"
t="$(mktemp)"
if [ -n "$SUPPR" ]; then sed -E "/$SUPPR/d" "$F" > "$t"; else cat "$F" > "$t"; fi
printf '%s\n' "$AJOUT" >> "$t"
cat "$t" > "$F"
rm -f "$t"
systemctl restart "$U"
sleep 3
if ! systemctl is-active --quiet "$U"; then
  restaurer_fichiers
  systemctl restart "$U" || true
  journal "$U ne repart pas avec la modification : fichier remis"
  exit 10
fi
journal "$F modifié, $U redémarré"
EOF
}

# _e41_cfg_retablir — remet le fichier sauvegardé SEULEMENT s'il porte encore la marque de la panne.
_e41_cfg_retablir() {
  m24_wb_exec "$_M24_MON01" "F=$_E41_CFG" "U=$_E41_UNITE" "MARQUE=$_E41_MARQUE" <<'EOF'
if grep -qF "$MARQUE" "$F" 2>/dev/null; then
  restaurer_fichiers
  systemctl restart "$U" || true
  journal "annulation : $F remis, $U redémarré"
else
  m="$WB_DIR/$WB_EX.manifeste"
  if [ -f "$m" ]; then
    while IFS="$(printf '\t')" read -r src dst; do [ "$dst" = ABSENT ] || rm -f -- "$dst"; done < "$m"
    rm -f "$m"
  fi
  journal "annulation : $F déjà réparé, rien à remettre"
fi
EOF
}

# _e41_debut — en-têtes de la réponse de l'instance à une visite sans session (redirection vers Keycloak).
_e41_debut() {
  curl -s -o /dev/null -D - --max-time 20 --cacert "$_M24_RACINE" "$_E41_URL/" 2>/dev/null | tr -d '\r'
}

_e41_cookie_domaine() { _e41_debut | grep -Eqi '^set-cookie: __Host-[^;]*;.*domain='; }
_e41_retour_hubble() {
  _e41_debut | grep -i '^location:' | grep -qF "redirect_uri=$(jq -rn --arg v "$_E41_RAPPEL_HUBBLE" '$v|@uri')"
}

_m24E41_une() {
  local n="$1" c id rc=0
  m24_ecrire E41 variante "$n"
  case "$n" in
    1)
      m24_sain_hote "$_M24_MON01" || return 1
      _e41_cfg_modifier "cookie_domains = [\".par1.medisphere.internal\"] $_E41_MARQUE Lucas : session commune avec Hubble" "" || rc=$?
      ((rc == 0)) || return "$rc"
      ;;
    2)
      c="$(m24_kc_client "$_E41_CLIENT")"
      [[ -n "$c" ]] || return 10
      jq -e --arg u "$_E41_RAPPEL" '.redirectUris | index($u) != null' >/dev/null <<<"$c" || return 10
      id="$(jq -r .id <<<"$c")"
      m24_kc_sauver E41 client "$c"
      m24_kc_json PUT "clients/$id" "$(jq -c --arg a "$_E41_RAPPEL" --arg b "$_E41_RAPPEL_SANS_PORT" \
        '{id, clientId, redirectUris: [.redirectUris[] | if . == $a then $b else . end]}' <<<"$c")" >/dev/null || return 1
      ;;
    3)
      m24_sain_hote "$_M24_MON01" || return 1
      c="$(m24_kc_client "$_E41_CLIENT")"
      # Sans l'URI de Hubble enregistrée, la variante ne montrerait que le symptôme de la 2.
      jq -e --arg u "$_E41_RAPPEL_HUBBLE" '.redirectUris | index($u) != null' >/dev/null 2>&1 <<<"$c" || return 10
      _e41_cfg_modifier "redirect_url = \"$_E41_RAPPEL_HUBBLE\" $_E41_MARQUE Lucas : copiée des valeurs du cluster" '^redirect_url[[:space:]]*=' || rc=$?
      ((rc == 0)) || return "$rc"
      ;;
  esac
  m24_journal E41 "variante $n posée"
}

verifier_E41() {
  case "$WB_VAR" in
    1) m24_attendre 30 _e41_cookie_domaine ;;
    2) [[ "$(m24_kc_code_auth "$_E41_CLIENT" "$_E41_RAPPEL")" == 400 ]] ;;
    3) m24_attendre 30 _e41_retour_hubble ;;
    *) return 1 ;;
  esac
}

panne_E41_v1() { m24_sain_keycloak && m24_essayer E41 3 1; }
panne_E41_v2() { m24_sain_keycloak && m24_essayer E41 3 2; }
panne_E41_v3() { m24_sain_keycloak && m24_essayer E41 3 3; }

annuler_E41() {
  local v c id
  v="$(m24_lire E41 variante)"
  case "$v" in
    1 | 3)
      _e41_cfg_retablir >/dev/null 2>&1 || wb_avert "mon01 : $_E41_CFG à vérifier (rejoue le rôle oauth2_proxy)"
      ;;
    2)
      c="$(m24_kc_client "$_E41_CLIENT" 2>/dev/null || true)"
      if [[ -n "$c" ]] && jq -e --arg b "$_E41_RAPPEL_SANS_PORT" '.redirectUris | index($b) != null' >/dev/null 2>&1 <<<"$c"; then
        id="$(jq -r .id <<<"$c")"
        m24_kc_json PUT "clients/$id" "$(jq -c --arg a "$_E41_RAPPEL" --arg b "$_E41_RAPPEL_SANS_PORT" \
          '{id, clientId, redirectUris: ([.redirectUris[] | if . == $b then $a else . end] | unique)}' <<<"$c")" >/dev/null 2>&1 ||
          wb_avert "redirections du client oauth2-proxy non rétablies (export : $(m24_etat E41)/kc-client.json)"
      fi
      ;;
  esac
  m24_oublier E41 variante
  m24_kc_oublier E41 client
  m24_journal E41 "annulation"
}

resume_E41() { echo "L'interface de Mailpit (mon01:8443) renvoie au SSO en boucle ou finit sur une page d'erreur ; Hubble et Pyroscope vont bien."; }

symptome_E41() {
  local detail
  case "$WB_VAR" in
    1) detail="J'ouvre https://mon01.par1.medisphere.internal:8443, je passe par Keycloak, je reviens… sur « Login Failed: Unable to find a valid CSRF token. Please try again. » Je réessaie : pareil, en boucle." ;;
    2) detail="J'ouvre https://mon01.par1.medisphere.internal:8443 et j'arrive directement sur une page d'erreur de Keycloak, sans formulaire de connexion." ;;
    *) detail="J'ouvre https://mon01.par1.medisphere.internal:8443, je me connecte, et je me retrouve sur hubble.apps… avec « Login Failed ». Je reviens sur Mailpit : rebelote." ;;
  esac
  wb_symptome "Ticket INC-5141 — De : Nadia Roussel" \
    "$detail" \
    "Hubble et Pyroscope, derrière le même SSO, marchent. Je n'ai plus accès aux courriels d'alerte de l'astreinte." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 24 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 24 E41 3 "$@"; }
fi
