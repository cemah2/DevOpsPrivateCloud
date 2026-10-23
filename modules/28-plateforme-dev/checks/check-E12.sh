# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E12.sh — M28-E12 : Guide d'accueil d'une équipe : le chemin balisé
# Présence et contenu des deux documents (GitLab, GET) ; la qualité s'évalue avec le corrigé.

# shellcheck source=_m28-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-decouverte.sh"

title "M28-E12 — Guide d'accueil d'une équipe : le chemin balisé"
require_cmd jq curl

check_cmd "guide-accueil-equipe.md : locataire, portail, déploiement, autoscaling, documentation, supervision" \
  _m28d_doc docs/plateforme-dev/guide-accueil-equipe.md 'locataire' 'portail' 'Argo CD|déploi' 'HPA|KEDA|charge' 'TechDocs|documentation' 'Grafana|supervis'
check_cmd "guide-accueil-equipe.md : vérifications et interdits expliqués" \
  _m28d_doc docs/plateforme-dev/guide-accueil-equipe.md 'v[ée]rifi' 'interdit' 'pourquoi'
_M28D_E12="$(_m28d_fichier plateforme/medisphere docs/plateforme-dev/runbooks/RB-280-creer-un-locataire.md 2>/dev/null || true)"
check_cmd "runbooks/RB-280-creer-un-locataire.md présent" test -n "$_M28D_E12"
check_cmd "RB-280 : au moins 6 étapes numérotées" test "$(grep -Ec '^[[:space:]]*[0-9]+\.' <<<"$_M28D_E12" || true)" -ge 6
for _m28d_e12_m in 'Tenant|locataire' 'annuaire|FreeIPA|ipa' 'Argo CD|AppProject' 'OpenBao|coffre|kv/' 'v[ée]rifi' 'retour arri'; do
  check_cmd "RB-280 traite : $_m28d_e12_m" grep -Eqi -- "$_m28d_e12_m" <<<"$_M28D_E12"
done
