# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et code Python entre apostrophes
# break-E37.sh — M24-E37 « Panne : les nouveaux arrivants n'existent pas »
#
# Préparation commune : une arrivée fictive, WB_M24_ARRIVEE (défaut emma.durand, « Emma Durand »,
# développeuse MédiDoc, groupe medidoc), est créée DANS L'ANNUAIRE par le cadre de FreeIPA sur ipa01
# (raccourci du workbook : en vrai elle arrive par RB-241 et annuaire/personnes.yml). Puis :
#   1. le mot de passe du compte système svc-keycloak est changé dans l'annuaire (rotation commencée
#      d'un côté seulement) : la fédération ne se lie plus (LDAP 49), ni synchronisation ni recherche ;
#      les connexions qui exigent une lecture de l'annuaire échouent aussi ;
#   2. le filtre des personnes de la fédération « gèle » l'import : (createTimestamp<=…) ajouté à
#      (!(uid=admin)) : les personnes créées après cette date sont invisibles pour Keycloak, les autres
#      ne voient rien ;
#   3. le filtre du mappeur de groupes perd (cn=medidoc) (« groupe vide », dit Lucas) : la personne
#      arrive dans Keycloak SANS groupe ; pour les services, elle n'a aucun droit.
# Rien ne touche admin (annuaire), kc-secours, ni les comptes des personnages ou de l'apprenant.
# Sauvegardes : empreinte du mot de passe de svc-keycloak (lue en root, rétablie telle quelle),
# composants Keycloak exportés en JSON.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m24-commun.sh
source "$WB_ROOT/modules/24-identite/corrige/pannes/_m24-commun.sh"

_E37_DN_SVC="uid=svc-keycloak,cn=sysaccounts,cn=etc,$_M24_BASE"

# --- Annuaire (code Python exécuté sur ipa01) -----------------------------------------------------

read -r -d '' _E37_PY_ARRIVEE <<'PY' || true
uid = P["uid"]
try:
    api.Command.user_show(uid)
    sortie({"etat": "existe"})
except errors.NotFound:
    api.Command.user_add(uid, givenname=P["prenom"], sn=P["nom"], mail=P["mail"],
                         title="Développeuse MédiDoc (arrivée, M24-E37)")
    try:
        api.Command.group_add_member(P["groupe"], user=[uid])
    except errors.NotFound:
        pass
    sortie({"etat": "cree"})
PY

read -r -d '' _E37_PY_DEPART <<'PY' || true
try:
    u = api.Command.user_show(P["uid"], all=True)["result"]
    if "M24-E37" in " ".join(u.get("title", [])):
        api.Command.user_del(P["uid"])
        sortie({"etat": "supprime"})
    else:
        sortie({"etat": "non-cree-par-la-panne"})
except errors.NotFound:
    sortie({"etat": "absent"})
PY

read -r -d '' _E37_PY_MDP <<'PY' || true
import secrets
from ipapython.dn import DN
ldap = api.Backend.ldap2
e = ldap.get_entry(DN(P["dn"]), ["userPassword"])
if P["action"] == "lire":
    sortie({"hash": [v.decode() if isinstance(v, bytes) else v for v in e.get("userPassword", [])]})
elif P["action"] == "changer":
    e["userPassword"] = [secrets.token_hex(24)]
    ldap.update_entry(e)
    sortie({"etat": "change"})
elif P["action"] == "remettre":
    e["userPassword"] = P["hash"]
    ldap.update_entry(e)
    sortie({"etat": "remis"})
PY

_e37_arrivee() {
  m24_ipa_py "$_E37_PY_ARRIVEE" "$(jq -nc --arg u "$_M24_ARRIVEE" '{uid: $u, prenom: "Emma", nom: "Durand",
    mail: ($u + "@medisphere.internal"), groupe: "medidoc"}')" | tail -n 1
}

_e37_mdp() { m24_ipa_py "$_E37_PY_MDP" "$1" | tail -n 1; }

# --- Keycloak ----------------------------------------------------------------------------------------

# _e37_lie_ldap [DEPUIS] — Keycloak a tenté une liaison avec svc-keycloak et l'annuaire l'a refusée (code 49).
_e37_lie_ldap() {
  local d="${1:-$(m24_lire E37 depuis)}"
  m24_ssh "$_M24_IDP" "journalctl -u keycloak --since @$d --no-pager -o cat | grep -Eqi 'error code 49|Invalid Credentials'"
}

_m24E37_une() {
  local n="$1" l lid gm h filtre ts
  l="$(m24_kc_ldap)"
  [[ -n "$l" ]] || return 10
  lid="$(jq -r .id <<<"$l")"
  m24_ecrire E37 variante "$n"
  m24_ecrire E37 depuis "$(m24_maintenant)"
  case "$n" in
    1)
      h="$(_e37_mdp "$(jq -nc --arg d "$_E37_DN_SVC" '{dn: $d, action: "lire"}')" | jq -c '.hash // empty')" || h=""
      [[ -n "$h" && "$h" != "[]" ]] || return 10
      m24_ecrire E37 hash-svc "$h"
      _e37_mdp "$(jq -nc --arg d "$_E37_DN_SVC" '{dn: $d, action: "changer"}')" | grep -q change || return 1
      ;;
    2)
      filtre="$(jq -r '.config.customUserSearchFilter[0] // ""' <<<"$l")"
      [[ "$filtre" == *createTimestamp* ]] && return 10
      ts="$(date -u -d '-2 hours' +%Y%m%d%H%M%SZ)"
      [[ -n "$filtre" ]] || filtre="(objectClass=*)"
      m24_ecrire E37 filtre-injecte "(&$filtre(createTimestamp<=$ts))"
      m24_kc_sauver E37 ldap "$l"
      m24_kc_json PUT "components/$lid" "$(jq -c --arg f "(&$filtre(createTimestamp<=$ts))" '.config.customUserSearchFilter = [$f]' <<<"$l")" >/dev/null || return 1
      ;;
    3)
      gm="$(m24_kc_mappeur_groupes "$lid")"
      [[ -n "$gm" ]] || return 10
      filtre="$(jq -r '.config["groups.ldap.filter"][0] // ""' <<<"$gm")"
      [[ "$filtre" == *"(cn=medidoc)"* ]] || return 10
      m24_kc_sauver E37 mappeur "$gm"
      m24_ecrire E37 filtre-injecte "${filtre//(cn=medidoc)/}"
      m24_kc_json PUT "components/$(jq -r .id <<<"$gm")" \
        "$(jq -c --arg f "${filtre//(cn=medidoc)/}" '.config["groups.ldap.filter"] = [$f]' <<<"$gm")" >/dev/null || return 1
      ;;
  esac
  # L'arrivée est créée APRÈS la modification (v2 : après la date du filtre).
  _e37_arrivee | grep -Eq '"(cree|existe)"' || return 1
  m24_ecrire E37 arrivee "$_M24_ARRIVEE"
  m24_kc_synchro "$lid" triggerChangedUsersSync
  m24_journal E37 "variante $n posée ; arrivée $_M24_ARRIVEE créée dans l'annuaire"
}

# _e37_effet N — la panne est visible depuis Keycloak.
_e37_effet() {
  local lid u
  lid="$(m24_kc_ldap | jq -r '.id // empty')"
  [[ -n "$lid" ]] || return 1
  m24_kc_synchro "$lid" triggerChangedUsersSync
  case "$1" in
    1) [[ -z "$(m24_kc_utilisateur "$_M24_ARRIVEE")" ]] && _e37_lie_ldap ;;
    2) [[ -z "$(m24_kc_utilisateur "$_M24_ARRIVEE")" ]] && [[ -z "$(m24_kc GET "users?search=$(_m24_enc "$_M24_ARRIVEE")" 2>/dev/null | jq -r '.[0].id // empty')" ]] ;;
    3)
      u="$(m24_kc_utilisateur "$_M24_ARRIVEE" | jq -r '.id // empty')"
      [[ -n "$u" ]] && ! m24_kc GET "users/$u/groups" 2>/dev/null | jq -e 'any(.[]; .name == "medidoc")' >/dev/null
      ;;
  esac
}

verifier_E37() { m24_attendre 60 _e37_effet "$WB_VAR"; }

panne_E37_v1() { m24_sain_keycloak && m24_sain_hote "$_M24_IPA" && m24_essayer E37 3 1; }
panne_E37_v2() { m24_sain_keycloak && m24_sain_hote "$_M24_IPA" && m24_essayer E37 3 2; }
panne_E37_v3() { m24_sain_keycloak && m24_sain_hote "$_M24_IPA" && m24_essayer E37 3 3; }

annuler_E37() {
  local v h l gm inj id lid u t k
  v="$(m24_lire E37 variante)"
  case "$v" in
    1)
      h="$(m24_lire E37 hash-svc)"
      if [[ -n "$h" ]]; then
        # Rétablit l'empreinte d'origine (le mot de passe du Vault critique redevient valable), mais
        # seulement si la liaison de Keycloak échoue ENCORE maintenant : une rotation complète faite par
        # l'apprenant (annuaire + Vault + OpenTofu) n'est jamais défaite.
        t="$(m24_maintenant)"
        lid="$(m24_kc_ldap 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)"
        if [[ -n "$lid" ]]; then m24_kc_synchro "$lid" triggerChangedUsersSync; fi
        sleep 5
        if _e37_lie_ldap "$t" 2>/dev/null; then
          _e37_mdp "$(jq -nc --arg d "$_E37_DN_SVC" --argjson h "$h" '{dn: $d, action: "remettre", hash: $h}')" >/dev/null 2>&1 ||
            wb_avert "empreinte du mot de passe de svc-keycloak non rétablie (sauvegarde : $(m24_etat E37)/hash-svc)"
        fi
      fi
      ;;
    2)
      l="$(m24_kc_ldap 2>/dev/null || true)"
      inj="$(m24_lire E37 filtre-injecte)"
      if [[ -n "$l" && "$(jq -r '.config.customUserSearchFilter[0] // ""' <<<"$l")" == "$inj" ]]; then
        id="$(jq -r .id <<<"$l")"
        m24_kc_json PUT "components/$id" "$(jq -c --argjson s "$(m24_kc_sauve E37 ldap || echo null)" \
          'if $s then .config.customUserSearchFilter = ($s.config.customUserSearchFilter // []) else . end' <<<"$l")" >/dev/null 2>&1 ||
          wb_avert "filtre des personnes de la fédération non rétabli"
      fi
      ;;
    3)
      l="$(m24_kc_ldap 2>/dev/null || true)"
      lid="$(jq -r '.id // empty' <<<"$l" 2>/dev/null || true)"
      gm="$([[ -n "$lid" ]] && m24_kc_mappeur_groupes "$lid" 2>/dev/null || true)"
      inj="$(m24_lire E37 filtre-injecte)"
      if [[ -n "$gm" && "$(jq -r '.config["groups.ldap.filter"][0] // ""' <<<"$gm")" == "$inj" ]]; then
        m24_kc_json PUT "components/$(jq -r .id <<<"$gm")" "$(jq -c --argjson s "$(m24_kc_sauve E37 mappeur || echo null)" \
          'if $s then .config["groups.ldap.filter"] = $s.config["groups.ldap.filter"] else . end' <<<"$gm")" >/dev/null 2>&1 ||
          wb_avert "filtre du mappeur de groupes non rétabli"
      fi
      ;;
  esac
  # L'arrivée fictive disparaît de l'annuaire (seulement si c'est la panne qui l'a créée), puis de Keycloak.
  if [[ -n "$(m24_lire E37 arrivee)" ]]; then
    m24_ipa_py "$_E37_PY_DEPART" "$(jq -nc --arg u "$_M24_ARRIVEE" '{uid: $u}')" >/dev/null 2>&1 || wb_avert "$_M24_ARRIVEE non supprimée de l'annuaire"
    u="$(m24_kc_utilisateur "$_M24_ARRIVEE" 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)"
    if [[ -n "$u" ]]; then m24_kc DELETE "users/$u" >/dev/null 2>&1 || true; fi
  fi
  for k in variante depuis hash-svc filtre-injecte arrivee; do m24_oublier E37 "$k"; done
  m24_kc_oublier E37 ldap
  m24_kc_oublier E37 mappeur
  m24_journal E37 "annulation"
}

resume_E37() { echo "Emma Durand, arrivée ce matin chez MédiDoc, est dans l'annuaire mais n'existe pour aucun service."; }

symptome_E37() {
  wb_symptome "Ticket INC-5137 — De : Nadia Roussel" \
    "Emma Durand ($_M24_ARRIVEE) arrive aujourd'hui dans l'équipe MédiDoc. Sa fiche est dans l'annuaire" \
    "depuis $(date +%H:%M) (groupe medidoc), j'ai vérifié. Mais elle ne peut rien faire : « elle n'existe pas »" \
    "côté services, et je ne la trouve pas comme il faut dans Keycloak. Le prochain arrivant, c'est lundi." \
    "Les comptes des autres semblent marcher… je crois. Je n'ai pas tout essayé." \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 24 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 24 E37 3 "$@"; }
fi
