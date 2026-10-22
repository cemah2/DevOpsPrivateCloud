# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et LogQL entre apostrophes
#
# check-E09.sh — M22-E09 : Données de santé dans les journaux : filtrer et masquer
# À lancer depuis adm01. Lecture seule : pod témoin de wb-essais (« kube »), recherche des motifs de
# données personnelles dans TOUS les locataires sur 1 h (LogQL), configuration sur main (GitLab).
# Le contrôle n'a de sens que si le témoin écrit des valeurs factices : il est exigé (sinon KO), sauf
# quand le mini-projet le rejoue (_M22_MINI_PROJET) : le témoin est alors retiré et la recherche des
# motifs porte sur 24 h.

# shellcheck source=_m22-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-operationnel.sh"

title "M22-E09 — Données de santé dans les journaux : filtrer et masquer"
require_cmd jq kubectl curl

# --- 1. Le témoin écrit, et ses lignes arrivent masquées ----------------------------------------------
_m22o_e09_depuis=1h
if [[ -n "${_M22_MINI_PROJET:-}" ]]; then _m22o_e09_depuis=24h; fi
_m22o_e09_temoin="$(_m22o_k get pods -n wb-essais -l app.kubernetes.io/name=temoin-donnees -o json)"
if [[ -n "${_M22_MINI_PROJET:-}" ]] && ! _m22o_json "$_m22o_e09_temoin" 'any(.items[]; .status.phase == "Running")'; then
  skip "témoin temoin-donnees (wb-essais)" "retiré à la livraison, comme attendu : seule la recherche des motifs sur 24 h est rejouée"
else
check_cmd "wb-essais : pod témoin temoin-donnees en marche (ressources/E09-temoin)" _m22o_json \
  "$_m22o_e09_temoin" 'any(.items[]; .status.phase == "Running")'
_m22o_e09_t="$(_m22o_texte '{namespace="wb-essais", container="temoin"} |= "M22-E09"' plateforme 15m)"
check_cmd "lignes du témoin reçues par Loki dans les 15 dernières minutes" bash -c '[[ -n "$1" ]]' _ "$_m22o_e09_t"
check_cmd "témoin : NIR remplacé (avec et sans espaces)" bash -c \
  'grep -Eq "\"nir\": ?\"\\[NIR-MASQUE\\]\"" <<<"$1" && grep -q "NIR \\[NIR-MASQUE\\]" <<<"$1"' _ "$_m22o_e09_t"
check_cmd "témoin : nom du patient remplacé" bash -c '[[ -n "$1" ]] && ! grep -q "Jeanne Témoin" <<<"$1"' _ "$_m22o_e09_t"
check_cmd "témoin : courriels externes remplacés" bash -c \
  '[[ -n "$1" ]] && ! grep -Eq "jeanne\\.temoin@example\\.org|jean\\.dupont@exemple\\.fr" <<<"$1"' _ "$_m22o_e09_t"
check_cmd "témoin : adresses MédiSphère conservées (astreinte@, plateforme@…), utiles aux enquêtes" bash -c \
  'grep -q "astreinte@medisphere\\.internal" <<<"$1" && grep -q "plateforme@par1\\.medisphere\\.internal" <<<"$1"' _ "$_m22o_e09_t"
check_cmd "témoin : un horodatage en nanosecondes (19 chiffres) n'est pas pris pour un NIR" bash -c \
  'grep -Eq "\"horodatage_ns\": ?\"[0-9]{19}\"" <<<"$1"' _ "$_m22o_e09_t"
fi

# --- 2. Plus rien dans aucun locataire (1 h ; 24 h au mini-projet) ------------------------------------------
# _m22o_e09_compte 'LogQL' LOCATAIRE — nombre de lignes trouvées (au plus 100), ou « erreur » si Loki
# n'a pas répondu : une recherche qui échoue ne doit jamais passer pour une recherche vide.
_m22o_e09_compte() {
  local r
  r="$(curl -sf --max-time 60 -G -H "X-Scope-OrgID: $2" -H "Accept: application/json" \
    --data-urlencode "query=$1" --data-urlencode "since=$_m22o_e09_depuis" --data-urlencode "limit=100" \
    "$_M22O_LOKI/loki/api/v1/query_range" 2>/dev/null || true)"
  jq -r 'if .status == "success" then ([.data.result[]?.values | length] | add // 0) else "erreur" end' \
    <<<"${r:-{\}}" 2>/dev/null || echo erreur
}
for _m22o_e09_loc in "${_M22O_LOCATAIRES[@]}"; do
  _m22o_e09_nir="$(_m22o_e09_compte "{job=~\".+\"} |~ \`$_M22O_RE_NIR\`" "$_m22o_e09_loc")"
  check_cmd "$_m22o_e09_loc : aucune ligne ressemblant à un NIR depuis $_m22o_e09_depuis (trouvée(s) : ${_m22o_e09_nir})" \
    bash -c '[[ "$1" == 0 ]]' _ "$_m22o_e09_nir"
  _m22o_e09_mel="$(_m22o_e09_compte "{job=~\".+\"} |~ \`$_M22O_RE_COURRIEL\` !~ \`@([a-z0-9-]+\\.)*medisphere\\.internal\`" "$_m22o_e09_loc")"
  check_cmd "$_m22o_e09_loc : aucune adresse de courriel externe depuis $_m22o_e09_depuis (trouvée(s) : ${_m22o_e09_mel})" \
    bash -c '[[ "$1" == 0 ]]' _ "$_m22o_e09_mel"
done

# --- 3. Dans le code ------------------------------------------------------------------------------------
check_output "plateforme/observabilite (main) : masquage dans la configuration d'Alloy (stage.replace)" 'stage\.replace' \
  _m22o_contenu_main "$_M22O_P_OBS" alloy/config.alloy
check_output "plateforme/ansible (main) : les VMs masquent aussi (gabarit du rôle alloy)" 'stage\.replace' \
  _m22o_contenu_main projects/plateforme%2Fansible roles/alloy/templates/config.alloy.j2
check_cmd "plateforme/medisphere (main) : docs/observabilite/journaux/politique-journaux.md (règle des données de santé)" \
  _m22o_fichier_main "$_M22O_P_DOC" docs/observabilite/journaux/politique-journaux.md
