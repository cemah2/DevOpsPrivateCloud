# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-E41.sh — M25-E41 « Panne : les certificats de service sont refusés »
#
# PKI de services (pki-services/), modifiée DIRECTEMENT dans OpenBao (dérive par rapport à
# plateforme/secrets). Variantes :
#   1. rôle services-k8s réduit à « svc.cluster.local » : les noms « <service>.<espace>.svc » sont
#      refusés à la signature ; renouvellement forcé de medidoc-mtls → CertificateRequest en échec ;
#   2. rôle services-k8s sans client_flag : certificats émis avec le seul usage serverAuth ;
#      renouvellement forcé de mediagenda-mtls → le relais de MédiDoc refuse le certificat CLIENT ;
#   3. émetteur par défaut privé de l'usage issuing-certificates (« préparation de la succession de la
#      CA ») : plus aucune signature ; renouvellement forcé de medidoc-mtls → échec ;
#   4. CRL : expiry 5 min, auto_rebuild coupé, CRL reconstruite : elle est périmée quelques minutes plus
#      tard ; tout client qui vérifie la CRL (openssl verify -crl_check) refuse les certificats.
# Une durée demandée au-delà de max_ttl est RÉDUITE (pas refusée) : ce n'est pas une variante.
#
# Écritures par POST complet (relu puis modifié par jq) : plateforme-admin n'a pas la capacité
# « patch ». Sauvegardes : ~/.local/state/workbook/M25-E41/ (rôle, émetteur, configuration de la CRL).
# Annulation : remise des valeurs sauvegardées, CRL reconstruite, renouvellement du certificat touché.

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m25-commun-b.sh
source "$WB_ROOT/modules/25-secrets/corrige/pannes/_m25-commun-b.sh"

_E41_ROLE=pki-services/roles/services-k8s
_E41_CRL=pki-services/config/crl

_e41_emetteur_id() { m25b_api GET pki-services/config/issuers 2>/dev/null | jq -r '.data.default // empty' 2>/dev/null || true; }

_e41_pret() {
  local r e
  m25b_jeton_charger || return 1
  r="$(m25b_api GET "$_E41_ROLE")" || { wb_avert "rôle services-k8s illisible (M25-E16 fait ?)"; return 1; }
  jq -e '.data.client_flag == true and .data.server_flag == true and ((.data.allowed_domains | index("svc")) != null)' >/dev/null 2>&1 <<<"$r" \
    || { wb_avert "rôle services-k8s différent du corrigé de M25-E16 : rien n'est cassé"; return 1; }
  if ! m25b_certificat_pret medidoc-recette medidoc-mtls || ! m25b_certificat_pret mediagenda-recette mediagenda-mtls; then
    wb_avert "certificats mTLS de la recette pas prêts : rien n'est cassé"
    return 1
  fi
  e="$(_e41_emetteur_id)"
  [[ -n "$e" ]] || { wb_avert "émetteur par défaut de pki-services introuvable"; return 1; }
  m25b_ecrire_si_absent E41 role.json "$(jq -c .data <<<"$r")"
  m25b_ecrire_si_absent E41 emetteur.id "$e"
  m25b_ecrire_si_absent E41 emetteur.json "$(m25b_api GET "pki-services/issuer/$e" | jq -c '.data
    | {issuer_name, leaf_not_after_behavior, manual_chain, usage, revocation_signature_algorithm,
       issuing_certificates, crl_distribution_points, ocsp_servers, delta_crl_distribution_points}')"
  m25b_ecrire_si_absent E41 crl.json "$(m25b_api GET "$_E41_CRL" | jq -c .data)"
}

# _e41_role FILTRE_JQ — réécrit le rôle à partir de la sauvegarde transformée.
_e41_role() { m25b_lire E41 role.json | jq -c "$1" | m25b_api POST "$_E41_ROLE" - >/dev/null; }

panne_E41_v1() {
  _e41_pret || return 1
  _e41_role '.allowed_domains = ["svc.cluster.local"]' || return 1
  m25b_ecrire E41 certificat "medidoc-recette medidoc-mtls"
  m25b_renouveler_certificat medidoc-recette medidoc-mtls || wb_avert "renouvellement forcé impossible : la panne se verra à l'échéance"
  m25b_journal E41 "rôle services-k8s : allowed_domains = svc.cluster.local ; medidoc-mtls renouvelé"
}

panne_E41_v2() {
  _e41_pret || return 1
  _e41_role '.client_flag = false' || return 1
  m25b_ecrire E41 certificat "mediagenda-recette mediagenda-mtls"
  m25b_renouveler_certificat mediagenda-recette mediagenda-mtls || return 1
  m25b_journal E41 "rôle services-k8s : client_flag = false ; mediagenda-mtls renouvelé"
}

panne_E41_v3() {
  local e
  _e41_pret || return 1
  e="$(m25b_lire E41 emetteur.id)"
  m25b_lire E41 emetteur.json | jq -c '.usage = "read-only,crl-signing,ocsp-signing"' \
    | m25b_api POST "pki-services/issuer/$e" - >/dev/null || return 1
  m25b_ecrire E41 certificat "medidoc-recette medidoc-mtls"
  m25b_renouveler_certificat medidoc-recette medidoc-mtls || wb_avert "renouvellement forcé impossible : la panne se verra à l'échéance"
  m25b_journal E41 "émetteur $e : usage sans issuing-certificates ; medidoc-mtls renouvelé"
}

panne_E41_v4() {
  _e41_pret || return 1
  jq -nc '{expiry: "5m", auto_rebuild: false}' | m25b_api POST "$_E41_CRL" - >/dev/null || return 1
  m25b_api GET pki-services/crl/rotate >/dev/null || return 1
  m25b_journal E41 "CRL : expiry 5m, auto_rebuild false, reconstruite"
}

# _e41_crl_proche — la CRL publiée expire dans moins de 10 minutes.
_e41_crl_proche() {
  local p
  p="$(curl -s --max-time 10 "$_M25B_URL/v1/pki-services/crl/pem" 2>/dev/null | openssl crl -noout -nextupdate 2>/dev/null | cut -d= -f2)"
  [[ -n "$p" ]] && (($(date -d "$p" +%s) - $(date +%s) < 600))
}

verifier_E41() {
  local e
  m25b_jeton_charger || return 1
  case "$WB_VAR" in
    1) m25b_api GET "$_E41_ROLE" | jq -e '.data.allowed_domains == ["svc.cluster.local"]' >/dev/null 2>&1 ;;
    2) m25b_api GET "$_E41_ROLE" | jq -e '.data.client_flag == false' >/dev/null 2>&1 ;;
    3) e="$(m25b_lire E41 emetteur.id)"
       m25b_api GET "pki-services/issuer/$e" | jq -e '.data.usage | test("issuing-certificates") | not' >/dev/null 2>&1 ;;
    4) _e41_crl_proche ;;
    *) return 1 ;;
  esac
}

annuler_E41() {
  local e c
  if ! m25b_jeton_charger; then
    wb_avert "annulation impossible sans jeton plateforme-admin : connecte-toi puis relance « lab/bin/break 25 41 --annuler »"
    wb_avert "(ou rejoue plateforme/secrets : tofu apply rétablit le rôle et la CRL ; l'usage de l'émetteur se remet à la main)"
    return 0
  fi
  if m25b_existe E41 role.json; then
    m25b_lire E41 role.json | m25b_api POST "$_E41_ROLE" - >/dev/null || wb_avert "rôle services-k8s non restauré"
  fi
  e="$(m25b_lire E41 emetteur.id)"
  if [[ -n "$e" ]] && m25b_existe E41 emetteur.json; then
    m25b_lire E41 emetteur.json | m25b_api POST "pki-services/issuer/$e" - >/dev/null || wb_avert "émetteur $e non restauré"
  fi
  if m25b_existe E41 crl.json; then
    m25b_lire E41 crl.json | jq -c '{expiry, auto_rebuild, auto_rebuild_grace_period, disable, enable_delta}' \
      | m25b_api POST "$_E41_CRL" - >/dev/null || wb_avert "configuration de la CRL non restaurée"
  fi
  m25b_api GET pki-services/crl/rotate >/dev/null || true
  c="$(m25b_lire E41 certificat)"
  if [[ -n "$c" ]]; then
    # shellcheck disable=SC2086  # « espace nom »
    m25b_renouveler_certificat $c || true
  fi
  m25b_journal E41 "annulation"
  m25b_oublier E41 role.json
  m25b_oublier E41 emetteur.json
  m25b_oublier E41 emetteur.id
  m25b_oublier E41 crl.json
  m25b_oublier E41 certificat
}

symptome_E41() {
  wb_symptome "INC-5241 — De : Julien Petit — les certificats de service sont refusés en recette" \
    "Selon le moment : cert-manager signale un certificat de service en échec, les appels de MédiAgenda" \
    "vers MédiDoc (pièces jointes) tombent à la poignée de main TLS, ou le contrôle hebdomadaire de" \
    "Sophie (openssl verify -crl_check sur un certificat de la recette) le rejette. Rien n'a été" \
    "déployé côté équipes. Certains effets peuvent mettre quelques minutes à apparaître." \
    "Temps cible : 40 min. Contrôle : lab/bin/check 25 41"
}

resume_E41() { echo "certificats de service de la recette en échec ou refusés (cert-manager, relais mTLS ou contrôle CRL)"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 25 E41 4 "$@"; }
fi
