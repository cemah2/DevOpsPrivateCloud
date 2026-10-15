# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M15-E39 « Panne : la Gateway refuse le HTTPS »
#
# Cible : la Gateway passerelles/gw-par1 et MédiAgenda recette.
# Variantes :
#   1. Secret absent : le certificateRefs de l'écouteur HTTPS vise un nom de Secret qui n'existe pas
#      (le nom du Certificate au lieu de celui de son Secret, ou l'inverse) ;
#   2. mauvais espace : le certificateRefs vise le bon nom dans l'espace cert-manager, sans
#      ReferenceGrant (et le Secret n'y est pas) ;
#   3. allowedRoutes : l'étiquette medisphere.fr/exposition est retirée de l'espace
#      mediagenda-recette : la route n'est plus acceptée par l'écouteur.
# Sauvegardes : Gateway, Namespace.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m15-commun.sh
source "$WB_ROOT/modules/15-kubernetes-reseau/corrige/pannes/_m15-commun.sh"

_e39_gw() { m15_k -n "$_M15_GW_NS" get gateway "$_M15_GW" -o json 2>/dev/null; }

# _e39_ecouteur_https_ko — un écouteur HTTPS de la Gateway a ResolvedRefs à False.
_e39_ecouteur_https_ko() {
  _e39_gw | jq -e '[.status.listeners[]? | select(.conditions[]? | .type == "ResolvedRefs" and .status == "False")] | length > 0' >/dev/null
}
# _e39_route_refusee — la route mediagenda n'est plus acceptée par gw-par1.
_e39_route_refusee() {
  m15_k -n "$_M15_NS_APP" get httproute "$_M15_ROUTE" -o json 2>/dev/null | jq -e --arg g "$_M15_GW" '
    [.status.parents[]? | select(.parentRef.name == $g) | .conditions[]? | select(.type == "Accepted" and .status == "True")] | length == 0' >/dev/null
}

_m15E39_une() {
  local n="$1" j nom neuf
  j="$(_e39_gw)" || return 1
  nom="$(jq -r '[.spec.listeners[] | select(.protocol == "HTTPS")][0].tls.certificateRefs[0].name // empty' <<<"$j")"
  [[ -n "$nom" ]] || return 10
  m15_ecrire E39 secret "$nom"
  case "$n" in
    1)
      for neuf in apps-joker apps-joker-tls "$nom-ancien"; do
        [[ "$neuf" != "$nom" ]] || continue
        m15_k -n "$_M15_GW_NS" get secret "$neuf" >/dev/null 2>&1 || break
      done
      m15_patch_json gateway "$_M15_GW" "$_M15_GW_NS" \
        "(.spec.listeners[] | select(.protocol == \"HTTPS\") | .tls.certificateRefs[0].name) = \"$neuf\"" || return 1
      m15_ecrire E39 pose "nom:$neuf"
      ;;
    2)
      m15_k -n cert-manager get secret "$nom" >/dev/null 2>&1 && return 10
      m15_patch_json gateway "$_M15_GW" "$_M15_GW_NS" \
        '(.spec.listeners[] | select(.protocol == "HTTPS") | .tls.certificateRefs[0].namespace) = "cert-manager"' || return 1
      m15_ecrire E39 pose "ns:cert-manager"
      ;;
    3)
      [[ -n "$(m15_k get ns "$_M15_NS_APP" -o jsonpath='{.metadata.labels.medisphere\.fr/exposition}' 2>/dev/null)" ]] || return 10
      m15_patch_json ns "$_M15_NS_APP" "" 'del(.metadata.labels["medisphere.fr/exposition"])' || return 1
      m15_ecrire E39 pose "etiquette"
      ;;
  esac
  m15_journal E39 "variante $n posée"
}

panne_E39_v1() { m15_preparer && m15_essayer E39 3 1; }
panne_E39_v2() { m15_preparer && m15_essayer E39 3 2; }
panne_E39_v3() { m15_preparer && m15_essayer E39 3 3; }

verifier_E39() {
  case "$WB_VAR" in
    1 | 2) m15_attendre 90 _e39_ecouteur_https_ko && m15_attendre 60 m15_entree_ko ;;
    *) m15_attendre 90 _e39_route_refusee ;;
  esac
}

annuler_E39() {
  local pose
  pose="$(m15_lire E39 pose)"
  case "$pose" in
    nom:*)
      if _e39_gw | jq -e --arg n "${pose#nom:}" '[.spec.listeners[] | select(.protocol == "HTTPS") | .tls.certificateRefs[0].name] | index($n)' >/dev/null 2>&1; then
        m15_remettre gateway "$_M15_GW" "$_M15_GW_NS"
      fi
      ;;
    ns:*)
      if _e39_gw | jq -e '[.spec.listeners[] | select(.protocol == "HTTPS") | .tls.certificateRefs[0].namespace] | index("cert-manager")' >/dev/null 2>&1; then
        m15_remettre gateway "$_M15_GW" "$_M15_GW_NS"
      fi
      ;;
    etiquette)
      if [[ -z "$(m15_k get ns "$_M15_NS_APP" -o jsonpath='{.metadata.labels.medisphere\.fr/exposition}' 2>/dev/null || true)" ]]; then
        m15_k label ns "$_M15_NS_APP" medisphere.fr/exposition=oui >/dev/null 2>&1 || wb_avert "annulation : étiquette d'exposition non remise"
      fi
      ;;
  esac
  m15_oublier E39
}

resume_E39() {
  case "${WB_VAR:-}" in
    3) echo "https://$_M15_HOTE/ renvoie 404 alors que les autres applications publiées répondent." ;;
    *) echo "Toutes les applications publiées en HTTPS sur la Gateway échouent à la négociation TLS." ;;
  esac
}

symptome_E39() {
  case "$WB_VAR" in
    3)
      wb_symptome "Ticket INC-4245 — De : Julien Petit" \
        "https://$_M15_HOTE/ répond « 404 » depuis ce matin, avec un certificat valide." \
        "Les autres applications publiées sur la Gateway répondent. Nos pods, notre Service et" \
        "notre HTTPRoute n'ont pas bougé (je l'ai vérifié dans Git). Pendant la maintenance d'hier," \
        "Lucas a « fait le tri dans les espaces de noms »." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 15 39"
      ;;
    *)
      wb_symptome "Ticket INC-4245 — De : Nadia Roussel" \
        "Toutes les applications publiées en HTTPS sur la Gateway (MédiAgenda recette, Hubble…) sont" \
        "en erreur : le navigateur parle de connexion réinitialisée, curl d'une erreur TLS dès la" \
        "négociation. Le port 443 de $_M15_GW_IP répond pourtant, et le port 80 redirige toujours." \
        "Lucas a « rangé les certificats » hier. Karim veut que le certificat reste émis par" \
        "cert-manager : pas de certificat posé à la main." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 15 39"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 15 E39 3 "$@"; }
fi
