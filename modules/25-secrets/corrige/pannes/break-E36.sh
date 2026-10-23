# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-E36.sh — M25-E36 « Panne : la CI ne lit plus ses secrets »
#
# Les jobs de mediagenda/api qui lisent le coffre (securite:signature en tête) échouent. Modification
# DIRECTE de la configuration de la méthode JWT gitlab/ ou du rôle ci-mediagenda-api (dérive par
# rapport à plateforme/secrets, M25-E10), avec le jeton d'administration de l'apprenant. Variantes :
#   1. bound_audiences du rôle changée en « openbao.par1.medisphere.internal » (le nom DNS du service) :
#      le jeton d'identité du job porte toujours aud = openbao.medisphere.internal → connexion refusée ;
#   2. rôle réécrit « comme l'exemple de la documentation » : bound_claims_type = string et
#      ref_protected écrit en BOOLÉEN true (la revendication de GitLab est la CHAÎNE "true") ;
#      la comparaison est typée → connexion refusée (et les étiquettes v* ne passeraient plus non plus) ;
#   3. méthode gitlab/ passée de la découverte OIDC à jwks_url, sur un chemin qui n'existe pas sur git01
#      (/oauth/discovery/jwks.json), enregistré avec skip_jwks_validation=true : TOUS les rôles de
#      gitlab/ sont refusés, y compris ci-plateforme-secrets (le pipeline qui sait réparer) ;
#   4. politique ci-mediagenda-api retirée des token_policies du rôle (remplacée par default) :
#      la connexion RÉUSSIT, la lecture de kv/plateforme/harbor/robot-ci est refusée (403).
#
# Sauvegardes : ~/.local/state/workbook/M25-E36/ (role.json : audiences, revendications liées, type,
# politiques du rôle ; config.json : configuration de gitlab/, lue par l'API avant toute écriture).
# Annulation : remise de ces valeurs (identiques à plateforme/secrets : une réparation par tofu apply
# n'est pas défaite) ; la configuration de la méthode n'est réécrite que si elle a dérivé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m25-commun-b.sh
source "$WB_ROOT/modules/25-secrets/corrige/pannes/_m25-commun-b.sh"

_E36_MONTAGE=gitlab
_E36_ROLE=ci-mediagenda-api
_E36_AUD=openbao.medisphere.internal
_E36_AUD_FAUSSE=openbao.par1.medisphere.internal
_E36_JWKS_FAUX="https://git01.par1.medisphere.internal/oauth/discovery/jwks.json"

_e36_role() { m25b_api GET "auth/$_E36_MONTAGE/role/$_E36_ROLE" 2>/dev/null; }
_e36_config() { m25b_api GET "auth/$_E36_MONTAGE/config" 2>/dev/null; }
# _e36_ecrire_role (corps JSON sur l'entrée standard) — mise à jour des seuls champs fournis.
_e36_ecrire_role() { m25b_api POST "auth/$_E36_MONTAGE/role/$_E36_ROLE" - >/dev/null; }
# _e36_ecrire_config (corps JSON sur l'entrée standard) — la configuration est RÉÉCRITE en entier.
_e36_ecrire_config() { m25b_api POST "auth/$_E36_MONTAGE/config" - >/dev/null; }

# _e36_pret — état d'entrée conforme au corrigé de M25-E10 ; sauvegarde (une seule fois).
_e36_pret() {
  local r c
  m25b_jeton_charger || return 1
  r="$(_e36_role)" || { wb_avert "rôle $_E36_MONTAGE/$_E36_ROLE introuvable (M25-E10 fait ?)"; return 1; }
  c="$(_e36_config)" || { wb_avert "méthode $_E36_MONTAGE/ illisible (M25-E10 fait ?)"; return 1; }
  jq -e --arg a "$_E36_AUD" '.data.bound_audiences == [$a]
      and ([.data.bound_claims.ref_protected] | flatten) == ["true"]
      and .data.bound_claims_type == "glob"
      and ((.data.token_policies // []) | index("ci-mediagenda-api")) != null' >/dev/null 2>&1 <<<"$r" \
    || { wb_avert "rôle $_E36_ROLE différent du corrigé de M25-E10 (audience, ref_protected, type, politique) : rien n'est cassé"; return 1; }
  jq -e '(.data.oidc_discovery_url // "") != "" and (.data.jwks_url // "") == ""' >/dev/null 2>&1 <<<"$c" \
    || { wb_avert "méthode $_E36_MONTAGE/ sans découverte OIDC : état de départ inattendu, rien n'est cassé"; return 1; }
  m25b_ecrire_si_absent E36 role.json "$(jq -c '.data | {bound_audiences, bound_claims, bound_claims_type, token_policies}' <<<"$r")"
  # Configuration complète (pour la réécrire telle quelle) : pas de secret dans une méthode jwt sans
  # client OIDC (la lecture ne renvoie jamais oidc_client_secret), seulement le certificat public de la racine.
  m25b_ecrire_si_absent E36 config.json "$(jq -c '.data | del(.status) | with_entries(select(.value != null))' <<<"$c")"
}

panne_E36_v1() {
  _e36_pret || return 1
  jq -nc --arg a "$_E36_AUD_FAUSSE" '{bound_audiences: [$a]}' | _e36_ecrire_role || return 1
  m25b_journal E36 "rôle $_E36_ROLE : bound_audiences = $_E36_AUD_FAUSSE"
}

panne_E36_v2() {
  _e36_pret || return 1
  m25b_lire E36 role.json \
    | jq -c '{bound_claims_type: "string", bound_claims: (.bound_claims + {ref_protected: true})}' \
    | _e36_ecrire_role || return 1
  m25b_journal E36 "rôle $_E36_ROLE : bound_claims_type = string, ref_protected = true (booléen)"
}

panne_E36_v3() {
  _e36_pret || return 1
  m25b_lire E36 config.json \
    | jq -c --arg u "$_E36_JWKS_FAUX" 'del(.jwt_validation_pubkeys, .jwks_pairs)
        | .jwks_ca_pem = (.oidc_discovery_ca_pem // "") | .jwks_url = $u
        | .oidc_discovery_url = "" | .oidc_discovery_ca_pem = "" | .skip_jwks_validation = true' \
    | _e36_ecrire_config || return 1
  m25b_journal E36 "méthode $_E36_MONTAGE/ : jwks_url = $_E36_JWKS_FAUX (découverte retirée, validation sautée)"
}

panne_E36_v4() {
  _e36_pret || return 1
  m25b_lire E36 role.json \
    | jq -c '{token_policies: (((.token_policies // []) - ["ci-mediagenda-api"]) + ["default"] | unique)}' \
    | _e36_ecrire_role || return 1
  m25b_journal E36 "rôle $_E36_ROLE : politique ci-mediagenda-api retirée de token_policies"
}

verifier_E36() {
  local r c
  m25b_jeton_charger || return 1
  case "$WB_VAR" in
    1) r="$(_e36_role)" && jq -e --arg a "$_E36_AUD" '(.data.bound_audiences // []) | index($a) == null' >/dev/null 2>&1 <<<"$r" ;;
    2) r="$(_e36_role)" && jq -e '[.data.bound_claims.ref_protected] | flatten | any(. == true)' >/dev/null 2>&1 <<<"$r" ;;
    3) c="$(_e36_config)" && jq -e --arg u "$_E36_JWKS_FAUX" '.data.jwks_url == $u' >/dev/null 2>&1 <<<"$c" ;;
    4) r="$(_e36_role)" && jq -e '(.data.token_policies // []) | index("ci-mediagenda-api") == null' >/dev/null 2>&1 <<<"$r" ;;
    *) return 1 ;;
  esac
}

annuler_E36() {
  local c
  if ! m25b_jeton_charger; then
    wb_avert "annulation impossible sans jeton plateforme-admin : connecte-toi puis relance « lab/bin/break 25 36 --annuler »"
    wb_avert "(ou rejoue plateforme/secrets depuis adm01 : tofu apply ramène la méthode gitlab/ et le rôle $_E36_ROLE)"
    return 0
  fi
  if m25b_existe E36 role.json; then
    m25b_lire E36 role.json | _e36_ecrire_role || wb_avert "rôle $_E36_ROLE non restauré"
  fi
  c="$(_e36_config || true)"
  if m25b_existe E36 config.json && ! jq -e '(.data.jwks_url // "") == "" and (.data.oidc_discovery_url // "") != ""' >/dev/null 2>&1 <<<"$c"; then
    # Réécriture avec validation de la découverte ; si git01 ne répond pas à cet instant, même
    # configuration sans la validation (OpenBao relira la découverte à la première connexion).
    if ! m25b_lire E36 config.json | _e36_ecrire_config; then
      m25b_lire E36 config.json | jq -c '.skip_jwks_validation = true' | _e36_ecrire_config \
        || wb_avert "configuration de $_E36_MONTAGE/ non restaurée : tofu apply de plateforme/secrets depuis adm01"
    fi
  fi
  m25b_journal E36 "annulation"
  m25b_oublier E36 role.json
  m25b_oublier E36 config.json
}

symptome_E36() {
  wb_symptome "INC-5236 — De : Julien Petit — la publication de MédiAgenda échoue sur le coffre" \
    "Depuis ce matin, le pipeline de main de mediagenda/api s'arrête dans securite:signature, à l'étape" \
    "OpenBao (connexion ou lecture du robot Harbor). Rien n'a changé dans le dépôt ni dans le composant." \
    "Relancer le job ne change rien. Les autres projets ? Personne n'a regardé." \
    "Temps cible : 45 min. Contrôle : lab/bin/check 25 36"
}

resume_E36() { echo "les jobs de mediagenda/api n'obtiennent plus leurs secrets d'OpenBao (méthode gitlab/)"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 25 E36 4 "$@"; }
fi
