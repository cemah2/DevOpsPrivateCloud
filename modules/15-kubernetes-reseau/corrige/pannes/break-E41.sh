# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M15-E41 « Panne : le nom n'est plus publié »
#
# Témoin : HTTPRoute mediagenda-recette/temoin-dns (temoin-dns.apps.par1.medisphere.internal, même
# Gateway et même Service que la route mediagenda).
# Variantes :
#   1. filtre de domaine d'ExternalDNS : --domain-filter=app.par1.medisphere.internal (faute de
#      frappe) ; la route témoin, créée ensuite, n'est jamais publiée ;
#   2. txt-owner-id : la route témoin est créée et publiée, puis l'identifiant de propriétaire
#      passe à k8s-par2 (« copie de la configuration du futur cluster ») et la route est supprimée :
#      son nom reste publié (enregistrement orphelin), et ExternalDNS ne gère plus les noms existants ;
#   3. RBAC : la règle du ClusterRole d'ExternalDNS sur gateway.networking.k8s.io est retirée ;
#      la route témoin n'est jamais publiée.
# Sauvegardes : Deployment d'ExternalDNS, ClusterRole, HTTPRoute témoin (absente).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m15-commun.sh
source "$WB_ROOT/modules/15-kubernetes-reseau/corrige/pannes/_m15-commun.sh"

_E41_ROUTE=temoin-dns
_E41_NOM="temoin-dns.$_M15_ZONE"
_E41_NS_EDNS=external-dns

# _e41_deploiement — Deployment d'ExternalDNS (arguments contenant --provider=rfc2136).
_e41_deploiement() {
  m15_k -n "$_E41_NS_EDNS" get deploy -o json 2>/dev/null | jq -r '
    .items[] | select([.spec.template.spec.containers[].args[]?] | any(test("^--provider(=| )rfc2136"))) | .metadata.name' | head -n 1
}

# _e41_clusterroles — ClusterRoles liés au compte de service d'ExternalDNS.
_e41_clusterroles() {
  m15_k get clusterrolebindings -o json 2>/dev/null | jq -r --arg ns "$_E41_NS_EDNS" '
    .items[] | select(.roleRef.kind == "ClusterRole")
    | select([.subjects[]? | select(.kind == "ServiceAccount" and .namespace == $ns)] | length > 0)
    | .roleRef.name' | sort -u
}

_e41_route_temoin() {
  local j pref
  j="$(m15_k -n "$_M15_NS_APP" get httproute "$_M15_ROUTE" -o json 2>/dev/null)" || return 1
  m15_sauver httproute "$_E41_ROUTE" "$_M15_NS_APP"
  pref="$(jq -c '.spec.parentRefs' <<<"$j")"
  jq -n --arg nom "$_E41_ROUTE" --arg ns "$_M15_NS_APP" --arg h "$_E41_NOM" --argjson p "$pref" \
    --argjson b "$(jq -c '.spec.rules[0].backendRefs' <<<"$j")" '{
      apiVersion: "gateway.networking.k8s.io/v1", kind: "HTTPRoute",
      metadata: {name: $nom, namespace: $ns, annotations: {"medisphere.fr/demande": "DEV-1645 : page de maintenance"}},
      spec: {parentRefs: $p, hostnames: [$h], rules: [{backendRefs: $b}]}}' \
    | m15_k apply -f - >/dev/null 2>&1
}

_e41_publie() { [[ -n "$(m15_dig "$_E41_NOM")" ]]; }
_e41_absent() { ! _e41_publie; }

# _e41_args_patch 'filtre sur une chaîne' — applique un sub() aux arguments du premier conteneur.
_e41_args_patch() {
  local d="$1" f="$2"
  m15_patch_json deploy "$d" "$_E41_NS_EDNS" ".spec.template.spec.containers[0].args |= map($f)" || return 1
  m15_k -n "$_E41_NS_EDNS" rollout status "deploy/$d" --timeout=120s >/dev/null 2>&1 || true
}

_m15E41_une() {
  local n="$1" d cr vu=0
  d="$(_e41_deploiement)"
  [[ -n "$d" ]] || return 1
  m15_ecrire E41 deploiement "$d"
  case "$n" in
    1)
      m15_k -n "$_E41_NS_EDNS" get deploy "$d" -o json | jq -e '[.spec.template.spec.containers[0].args[]] | index("--domain-filter=apps.par1.medisphere.internal")' >/dev/null || return 10
      _e41_args_patch "$d" 'if . == "--domain-filter=apps.par1.medisphere.internal" then "--domain-filter=app.par1.medisphere.internal" else . end' || return 1
      _e41_route_temoin || return 1
      ;;
    2)
      m15_k -n "$_E41_NS_EDNS" get deploy "$d" -o json | jq -e '[.spec.template.spec.containers[0].args[]] | index("--txt-owner-id=k8s-par1")' >/dev/null || return 10
      _e41_route_temoin || return 1
      # Attendre la publication (intervalle d'ExternalDNS : 1 min par défaut).
      m15_attendre 240 _e41_publie || return 10
      _e41_args_patch "$d" 'if . == "--txt-owner-id=k8s-par1" then "--txt-owner-id=k8s-par2" else . end' || return 1
      m15_k -n "$_M15_NS_APP" delete httproute "$_E41_ROUTE" --ignore-not-found >/dev/null 2>&1 || return 1
      ;;
    3)
      while read -r cr; do
        [[ -n "$cr" ]] || continue
        if m15_patch_json clusterrole "$cr" "" '.rules |= map(select((.apiGroups // []) | index("gateway.networking.k8s.io") | not))'; then
          printf '%s\n' "$cr" >>"$(m15_etat E41)/roles"
          vu=1
        fi
      done < <(_e41_clusterroles)
      ((vu)) || return 10
      # Redémarrage : ExternalDNS relit ses informateurs (et échoue sur la ressource interdite).
      m15_k -n "$_E41_NS_EDNS" rollout restart "deploy/$d" >/dev/null 2>&1 || true
      _e41_route_temoin || return 1
      ;;
  esac
  m15_journal E41 "variante $n posée"
}

panne_E41_v1() { m15_preparer && m15_essayer E41 3 1; }
panne_E41_v2() { m15_preparer && m15_essayer E41 3 2; }
panne_E41_v3() { m15_preparer && m15_essayer E41 3 3; }

verifier_E41() {
  # Deux intervalles d'ExternalDNS : le nom témoin est toujours absent (1, 3) ou toujours là (2).
  sleep 150
  case "$WB_VAR" in
    2) _e41_publie ;;
    *) _e41_absent ;;
  esac
}

annuler_E41() {
  local d f cr
  d="$(m15_lire E41 deploiement)"
  if [[ -n "$d" ]] && m15_k -n "$_E41_NS_EDNS" get deploy "$d" -o json 2>/dev/null \
    | jq -e '[.spec.template.spec.containers[0].args[]] | (index("--domain-filter=app.par1.medisphere.internal") or index("--txt-owner-id=k8s-par2"))' >/dev/null 2>&1; then
    m15_remettre deploy "$d" "$_E41_NS_EDNS"
  fi
  f="$(m15_etat E41)/roles"
  if [[ -f "$f" ]]; then
    while read -r cr; do
      if m15_k get clusterrole "$cr" -o json 2>/dev/null | jq -e '[.rules[]? | .apiGroups[]?] | index("gateway.networking.k8s.io") | not' >/dev/null 2>&1; then
        m15_remettre clusterrole "$cr" ""
      fi
    done <"$f"
    m15_k -n "$_E41_NS_EDNS" rollout restart "deploy/$d" >/dev/null 2>&1 || true
  fi
  # La route témoin disparaît ; ExternalDNS (propriétaire k8s-par1) retire ensuite son nom.
  m15_k -n "$_M15_NS_APP" delete httproute "$_E41_ROUTE" --ignore-not-found >/dev/null 2>&1 || true
  m15_oublier E41
}

resume_E41() {
  case "${WB_VAR:-}" in
    2) echo "Le nom $_E41_NOM est toujours publié alors que sa route a été supprimée." ;;
    *) echo "La nouvelle route $_E41_ROUTE ($_E41_NOM) n'a jamais obtenu son nom DNS." ;;
  esac
}

symptome_E41() {
  case "$WB_VAR" in
    2)
      wb_symptome "Ticket INC-4247 — De : Sophie Laurent" \
        "Audit DNS de la zone $_M15_ZONE : le nom $_E41_NOM répond toujours," \
        "alors que la route a été supprimée tout à l'heure (page de maintenance retirée). Un nom" \
        "qui pointe vers une Gateway sans application, c'est un nom qu'on peut détourner." \
        "Je veux savoir pourquoi le nettoyage automatique ne s'est pas fait, et s'il se fera la" \
        "prochaine fois. Les autres noms de la zone semblent normaux." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 15 41"
      ;;
    *)
      wb_symptome "Ticket INC-4247 — De : Julien Petit" \
        "J'ai créé la route $_M15_NS_APP/$_E41_ROUTE pour la page de maintenance : la route est" \
        "acceptée par la Gateway, mais $_E41_NOM n'existe toujours pas" \
        "(NXDOMAIN) après 15 minutes. Les noms déjà publiés résolvent normalement." \
        "Avant, un nom apparaissait en moins de deux minutes." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 15 41"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 15 E41 3 "$@"; }
fi
