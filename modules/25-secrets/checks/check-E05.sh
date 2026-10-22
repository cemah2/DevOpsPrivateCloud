# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E05.sh — M25-E05 : Politiques et jetons
# À lancer depuis adm01. Lecture seule : texte des politiques ACL, liste des jetons vivants par leurs
# accessors (métadonnées : nom affiché, politiques ; jamais le jeton), document sur main.

# shellcheck source=_m25-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-decouverte.sh"

title "M25-E05 — Politiques et jetons"
require_cmd jq curl

_m25d_annoncer_acces

# _m25d_e05_aucune_regle POLITIQUE REGEX — la politique a des règles et aucune ligne
# « <chemin> <capacités> » (voir _m25d_regles) ne correspond à la regex.
_m25d_e05_aucune_regle() { _m25d_aucun "$2" "$(_m25d_regles "$1")"; }

# _m25d_e05_une_regle POLITIQUE REGEX — au moins une règle correspond.
_m25d_e05_une_regle() { _m25d_contient "$(_m25d_regles "$1")" "$2"; }

# --- 1. Les politiques des groupes ------------------------------------------------------------------
_m25d_e05_liste="$(_m25d_liste sys/policies/acl)"
for _m25d_e05_p in plateforme-admin plateforme-lecture securite-audit mediagenda-dev; do
  check_cmd "Politique $_m25d_e05_p présente" grep -qx -- "$_m25d_e05_p" <<<"$_m25d_e05_liste"
done
check_cmd "mediagenda-dev : écriture dans kv/data/mediagenda/dev/*" _m25d_e05_une_regle \
  mediagenda-dev '^kv/data/mediagenda/dev/\* .*"(create|update)"'
check_cmd "mediagenda-dev : rien sur recette ni prod, aucun chemin global (*, kv/*, kv/data/*)" _m25d_e05_aucune_regle \
  mediagenda-dev '^(\*|\+)|^kv/(data/|metadata/)?(\*|\+)|mediagenda/(recette|prod)'
check_cmd "mediagenda-dev : ni destruction définitive (kv/destroy), ni sudo" _m25d_e05_aucune_regle \
  mediagenda-dev '^kv/destroy|"sudo"'
check_cmd "plateforme-lecture : aucune valeur de secret (pas de kv/data)" _m25d_e05_aucune_regle \
  plateforme-lecture '^kv/(data|\*|\+)'
check_cmd "plateforme-lecture : aucune écriture (create, delete, sudo ; update seulement pour capabilities-self)" \
  _m25d_e05_aucune_regle plateforme-lecture '"(create|delete|sudo)"|^([^s]|s[^y]|sys/[^c]).* .*"update"'
check_cmd "securite-audit : aucune valeur de secret, ni création ni suppression" _m25d_e05_aucune_regle \
  securite-audit '^kv/(data|\*|\+)|"(create|delete)"'
check_cmd "plateforme-admin : ni chemin global (*, +/*), ni sys/raw, ni secrets des applications" _m25d_e05_aucune_regle \
  plateforme-admin '^(\*|\+)|^sys/raw|^kv/(\*|\+|data/(\*|\+|mediagenda))'
check_cmd "plateforme-admin : peut sceller le coffre en urgence (sys/seal avec sudo)" _m25d_e05_une_regle \
  plateforme-admin '^sys/seal .*"sudo"'

# --- 2. Le ménage après les essais ---------------------------------------------------------------------
check_cmd "Plus de politique d'essai (essai-*) sur le serveur" _m25d_aucun '^essai' "$_m25d_e05_liste"
_m25d_e05_essais=""
while IFS= read -r _m25d_e05_acc; do
  [[ -n "$_m25d_e05_acc" ]] || continue
  _m25d_e05_essais+="$(_m25d_requete POST auth/token/lookup-accessor \
    "$(jq -nc --arg a "$_m25d_e05_acc" '{accessor: $a}')" | jq -r '.data.display_name // empty' 2>/dev/null || true)"$'\n'
done < <(_m25d_liste auth/token/accessors)
if [[ -z "${_m25d_e05_essais//[[:space:]]/}" ]]; then
  skip "Jetons d'essai révoqués" "liste des jetons illisible avec l'accès courant"
else
  check_cmd "Tous les jetons d'essai d'E05 sont révoqués (nom affiché token-essai-e05*)" \
    _m25d_aucun '^token-essai-e05' "$_m25d_e05_essais"
fi

# --- 3. Le modèle écrit ---------------------------------------------------------------------------------
_m25d_e05_doc="$(_m25d_contenu_main plateforme/medisphere docs/securite/secrets/modele-acces-coffre.md)"
check_cmd "plateforme/medisphere : docs/securite/secrets/modele-acces-coffre.md sur main" \
  _m25d_contient "$_m25d_e05_doc" 'plateforme-admin'
check_cmd "modele-acces-coffre.md : la règle de priorité entre motifs (le plus précis l'emporte) est écrite" \
  _m25d_contient "$_m25d_e05_doc" '[Pp]riorit|plus précis'
