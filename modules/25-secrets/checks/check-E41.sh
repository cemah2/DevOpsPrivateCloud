# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E41.sh — M25-E41 « Panne : les certificats de service sont refusés » : rôle services-k8s conforme
# (domaines svc et svc.cluster.local avec sous-domaines, client ET serveur) ; émetteur par défaut avec
# l'usage issuing-certificates ; CRL configurée comme le code (72 h, reconstruction automatique) et
# publiée avec au moins 6 h de validité ; certificats mTLS de la recette prêts ; alertes certificat non
# prêt et CRL ; journal INC-5241.
# Lecture seule : bao_api (rôle ; émetteur et configuration de la CRL si wb-checks a l'extrait M25-E41),
# point public crl/pem, kube (Certificates), Prometheus (règles), gitlab_api.

# shellcheck source=_m25-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-expert.sh"

title "M25-E41 — Panne : les certificats de service sont refusés"
require_cmd curl jq openssl kubectl
_m25p_connexion

check_cmd "rôle services-k8s : svc et svc.cluster.local avec sous-domaines, usages client ET serveur" \
  _m25p_jq "$(_m25p_bao pki-services/roles/services-k8s)" '
  (.data.allowed_domains | sort) == ["svc", "svc.cluster.local"] and .data.allow_subdomains == true
  and .data.server_flag == true and .data.client_flag == true'

_m25x_e41_cfg="$(_m25p_bao pki-services/config/issuers)"
if [[ "$_m25x_e41_cfg" == null ]]; then
  skip "émetteur par défaut : usage issuing-certificates" "wb-checks ne lit pas pki-services/config/issuers (extrait M25-E41)"
else
  _m25x_e41_em="$(_m25p_bao "pki-services/issuer/$(jq -r '.data.default // "default"' <<<"$_m25x_e41_cfg")")"
  if [[ "$_m25x_e41_em" == null ]]; then
    skip "émetteur par défaut : usage issuing-certificates" "wb-checks ne lit pas pki-services/issuer/+ (extrait M25-E41)"
  else
    check_cmd "émetteur par défaut ($(jq -r '.data.issuer_name // "?"' <<<"$_m25x_e41_em")) : usage issuing-certificates" \
      _m25p_jq "$_m25x_e41_em" '.data.usage | test("issuing-certificates")'
  fi
fi
_m25x_e41_crl="$(_m25p_bao pki-services/config/crl)"
if [[ "$_m25x_e41_crl" == null ]]; then
  skip "configuration de la CRL conforme au code" "wb-checks ne lit pas pki-services/config/crl (extrait M25-E41)"
else
  check_cmd "configuration de la CRL : 72 h, reconstruction automatique, non désactivée" \
    _m25p_jq "$_m25x_e41_crl" '.data.expiry == "72h" and .data.auto_rebuild == true and .data.disable == false'
fi
check_cmd "CRL publiée (pki-services/crl/pem) valable encore au moins 6 h (reconstruite 12 h avant échéance)" _m25x_crl_marge 21600

check_cmd "medidoc-recette : Certificate medidoc-mtls prêt" _m25x_certificat_pret medidoc-recette medidoc-mtls
check_cmd "mediagenda-recette : Certificate mediagenda-mtls prêt" _m25x_certificat_pret mediagenda-recette mediagenda-mtls

check_cmd "alerte chargée : certificat de service non prêt (certmanager_certificate_ready_status)" \
  _m25x_regle_presente 'certmanager_certificate_ready_status'
check_cmd "alerte chargée : CRL de pki-services bientôt périmée (medisphere_pki_crl_*)" \
  _m25x_regle_presente 'medisphere_pki_crl_'
check_cmd "journal de diagnostic INC-5241 sur main (plateforme/medisphere)" _m25x_journal INC-5241
