#!/usr/bin/env bash
# outils/cert-ingress.sh — certificat du point d'entrée S3 (rgw.par1.medisphere.internal) :
# émission, renouvellement, application au service ingress.rgw.par1 (M08-E11, PLAT-921).
# Sur adm01, utilisateur admin. Lancé chaque jour par ceph-cert-ingress.timer.
#   (sans option)   renouvelle si l'échéance est à moins de 15 jours, applique si le certificat
#                   présenté par la VIP n'est pas le certificat en cours
#   --force         renouvelle et applique sans condition
#   --appliquer     applique le certificat en cours (appliquer.sh)
#   --verifier      n'écrit rien : affiche le « --dry-run » de la spécification complétée
# Le certificat et la clé ne sont JAMAIS dans le dépôt ni sur le disque de ceph01 : la spécification
# complétée part par l'entrée standard de ssh vers « ceph orch apply -i - ».
# Renouvellement : par le certificat lui-même (TLS mutuel, sans mot de passe). Réémission avec le
# provisioner JWK ceph-ingress (mot de passe sur adm01) seulement si le certificat a expiré.
set -euo pipefail
umask 077
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export CEPH_ADMIN="${CEPH_ADMIN:-ceph01}"

NOM=rgw.par1.medisphere.internal
VIP=10.10.30.200
DOSSIER="${CEPH_INGRESS_DOSSIER:-$HOME/.config/workbook/ceph-ingress}"
CERT="$DOSSIER/cert.pem"
CLE="$DOSSIER/cle.pem"
MDP="${CEPH_INGRESS_MDP:-$HOME/.config/workbook/step-ceph-ingress.pass}"
PROVISIONER=ceph-ingress
SEUIL=360h            # 15 jours : politique de certification (M06-E33)
SPEC="$MS_RACINE/specs/ingress.yaml"
MODE="${1:-auto}"

empreinte_locale()   { openssl x509 -in "$CERT" -noout -fingerprint -sha256 | cut -d= -f2; }
empreinte_presentee() {
  timeout 10 openssl s_client -connect "$VIP:443" -servername "$NOM" </dev/null 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || true
}
emettre() {
  [[ -r "$MDP" ]] || { ms_erreur "mot de passe du provisioner illisible : $MDP"; exit 1; }
  ms_info "Émission d'un certificat pour $NOM (provisioner $PROVISIONER)"
  step ca certificate "$NOM" "$CERT.nouveau" "$CLE.nouveau" --provisioner "$PROVISIONER" \
    --provisioner-password-file "$MDP" --not-after 720h --force
  mv -f "$CERT.nouveau" "$CERT"; mv -f "$CLE.nouveau" "$CLE"
}
renouveler() {
  ms_info "Renouvellement de $NOM (TLS mutuel)"
  step ca renew --force "$CERT" "$CLE"
}
appliquer() {   # appliquer [--dry-run]
  CERT="$CERT" CLE="$CLE" ms_yq '.spec.ssl_cert = load_str(strenv(CERT)) | .spec.ssl_key = load_str(strenv(CLE))' "$SPEC" \
    | ms_ceph orch apply -i - "$@"
}

install -d -m 700 "$DOSSIER"
case "$MODE" in
  --verifier) [[ -s "$CERT" ]] || { ms_erreur "aucun certificat dans $DOSSIER"; exit 1; }; appliquer --dry-run; exit 0 ;;
  --appliquer|--force|auto) ;;
  *) echo "Usage : $0 [--force | --appliquer | --verifier]" >&2; exit 2 ;;
esac

if [[ ! -s "$CERT" ]] || ! openssl x509 -in "$CERT" -noout -checkend 0 >/dev/null; then
  emettre                                           # absent ou expiré : renouvellement refusé
elif [[ "$MODE" == --force ]] || step certificate needs-renewal --expires-in "$SEUIL" "$CERT" >/dev/null 2>&1; then
  renouveler
fi

locale="$(empreinte_locale)"
presentee="$(empreinte_presentee)"
if [[ "$MODE" == auto && "$locale" == "$presentee" ]]; then
  ms_info "La VIP présente déjà le certificat en cours ($(openssl x509 -in "$CERT" -noout -enddate))."
  exit 0
fi

appliquer
# cephadm reconfigure haproxy sur chaque hôte : on attend que la VIP présente le nouveau certificat.
for _ in $(seq 1 24); do
  [[ "$(empreinte_presentee)" == "$locale" ]] && { ms_info "Certificat en service sur la VIP."; exit 0; }
  sleep 10
done
ms_erreur "après 4 minutes, la VIP ne présente toujours pas le nouveau certificat"
exit 1
