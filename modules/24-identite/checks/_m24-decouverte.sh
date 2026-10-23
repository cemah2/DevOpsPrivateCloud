# shellcheck shell=bash
# _m24-decouverte.sh — fonctions partagées par les checks M24-E02 à M24-E08 (lecture seule).
# Sourcé par les check-EXX.sh du palier 1 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m24d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) :
#   - annuaire : « ipa_ldap » (compte système wb-checks, ~/.config/workbook/ipa-checks.env, M24-E03) ;
#   - Keycloak : « keycloak_api » (client wb-checks du royaume medisphere,
#     ~/.config/workbook/keycloak-checks.env, M24-E05) ; découverte OIDC sans authentification ;
#   - VMs : SSH en admin, commandes de consultation seulement (sudo -n en lecture) ;
#   - GitLab : gitlab_api (jeton read_api) ; NetBox : netbox_api.
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_MOI            ton identifiant (bloc A) : aussi ton compte dans l'annuaire (E03)
#   WB_M24_IPA        alias SSH de ipa01 (ipa01)
#   WB_M24_IDP        alias SSH de idp01 (idp01)
#   WB_RACINE_PKI     racine MédiSphère sur adm01 (/usr/local/share/ca-certificates/medisphere-root-ca.crt)

_M24D_MOI="${WB_MOI:-}"
_M24D_IPA="${WB_M24_IPA:-ipa01}"
_M24D_IDP="${WB_M24_IDP:-idp01}"
_M24D_RACINE="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
_M24D_DOMAINE=par1.medisphere.internal
_M24D_BASE="dc=par1,dc=medisphere,dc=internal"
_M24D_ROYAUME_KRB=PAR1.MEDISPHERE.INTERNAL
_M24D_SSO="https://sso.par1.medisphere.internal"
_M24D_EMETTEUR="$_M24D_SSO/realms/medisphere"
# Personnages de PLAN §2 (identifiants identiques à GitLab, PLAN §4.8).
_M24D_PERSONNAGES=(claire.morel karim.benali sophie.laurent julien.petit nadia.roussel lucas.martin)
_M24D_GROUPES=(plateforme-admins plateforme mediagenda medidoc securite support direction)

# _m24d_json JSON FILTRE_JQ [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m24d_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m24d_uri TEXTE — encodage pour une URL.
_m24d_uri() {
  jq -rn --arg v "$1" '$v | @uri'
}

# _m24d_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m24d_contenu_main() {
  gitlab_api "projects/$(_m24d_uri "$1")/repository/files/$(_m24d_uri "$2")/raw?ref=main" 2>/dev/null || true
}

# _m24d_pipeline_main PROJET — statut du dernier pipeline de main (vide si aucun).
_m24d_pipeline_main() {
  gitlab_api "projects/$(_m24d_uri "$1")/pipelines?ref=main&per_page=1" 2>/dev/null \
    | jq -r '.[0].status // empty' 2>/dev/null || true
}

# _m24d_contient TEXTE REGEX — le texte correspond à la regex étendue (sans afficher le texte).
_m24d_contient() {
  [[ -n "$1" ]] && grep -Eq -- "$2" <<<"$1"
}

# _m24d_ldap FILTRE [ATTRIBUTS…] — recherche dans l'annuaire (sortie vide en cas d'erreur).
_m24d_ldap() {
  ipa_ldap "$@" 2>/dev/null || true
}

# _m24d_kc CHEMIN — API d'administration de Keycloak (royaume medisphere) ou chemin absolu
# public (/realms/…) ; sortie vide en cas d'erreur.
_m24d_kc() {
  keycloak_api "$1" 2>/dev/null || true
}

# _m24d_kc_client CLIENT_ID — représentation JSON du client (vide si absent ou illisible), SANS son
# secret : jusqu'à Keycloak 26.7, le rôle view-clients de wb-checks reçoit le secret de chaque client
# confidentiel dans cette représentation (26.8 l'exige manage-clients) ; on le retire aussitôt.
_m24d_kc_client() {
  _m24d_kc "clients?clientId=$(_m24d_uri "$1")" | jq -c '.[0] // empty | del(.secret)' 2>/dev/null || true
}

# _m24d_chaine_tls HÔTE PORT [SNI] — la chaîne présentée se vérifie jusqu'à la racine MédiSphère.
_m24d_chaine_tls() {
  local hote="$1" port="$2" sni="${3:-$1}" sortie
  sortie="$(timeout "$WB_TIMEOUT" openssl s_client -connect "$hote:$port" -servername "$sni" \
    -CAfile "$_M24D_RACINE" -verify_return_error -verify_hostname "$sni" </dev/null 2>&1)" || return 1
  grep -q 'Verify return code: 0 (ok)' <<<"$sortie"
}

# _m24d_pem_selon_sujet REGEX — lit un paquet PEM sur l'entrée standard et écrit le premier
# certificat dont le sujet (UTF-8) correspond à la regex étendue (rien sinon).
_m24d_pem_selon_sujet() {
  local regex="$1" ligne cert="" sujet
  while IFS= read -r ligne; do
    case "$ligne" in
      *"BEGIN CERTIFICATE"*) cert="$ligne"$'\n' ;;
      *"END CERTIFICATE"*)
        cert+="$ligne"$'\n'
        sujet="$(openssl x509 -noout -subject -nameopt utf8,sep_comma_plus <<<"$cert" 2>/dev/null || true)"
        if grep -Eq -- "$regex" <<<"$sujet"; then
          printf '%s' "$cert"
          return 0
        fi
        cert="" ;;
      *) [[ -n "$cert" ]] && cert+="$ligne"$'\n' ;;
    esac
  done
  return 0
}

# _m24d_ssh HÔTE COMMANDE — sortie d'une commande de consultation sur une VM (vide si échec).
_m24d_ssh() {
  remote "$1" "$2" 2>/dev/null || true
}

# _m24d_public CHEMIN — GET public sur le fournisseur (découverte, JWKS) : JSON ou vide.
_m24d_public() {
  curl -sf --max-time "$WB_TIMEOUT" --cacert "$_M24D_RACINE" -H "Accept: application/json" "$_M24D_SSO$1" 2>/dev/null || true
}

# _m24d_ipa_e03_fait — l'annuaire est en code (E03 fait) : sert aux checks d'E02, rejouables après E03.
_m24d_ipa_e03_fait() {
  [[ -n "$(_m24d_contenu_main plateforme/identite annuaire/personnes.yml)" ]]
}

# _m24d_identite_tofu — le royaume est décrit en OpenTofu sur main (E08 fait).
_m24d_identite_tofu() {
  [[ -n "$(_m24d_contenu_main plateforme/identite tofu/royaume.tf)" ]]
}
