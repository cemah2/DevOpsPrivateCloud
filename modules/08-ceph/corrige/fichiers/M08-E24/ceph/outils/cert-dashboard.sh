#!/usr/bin/env bash
# outils/cert-dashboard.sh — certificat du tableau de bord de ceph-par1 (M08-E24, PLAT-950).
# Même principe que cert-ingress.sh (M08-E11) : sur adm01, utilisateur admin, lancé chaque jour par
# ceph-cert-dashboard.timer.
#   (sans option)   renouvelle si l'échéance est à moins de 15 jours, applique si le mgr actif ne
#                   présente pas le certificat en cours
#   --force         renouvelle et applique sans condition
#   --appliquer     applique le certificat en cours
# UN certificat pour les trois hôtes qui peuvent porter un mgr (étiquette « mgr » sur ceph01-03) :
# chaque nom en SAN, posé GLOBALEMENT dans le tableau de bord ; ainsi le mgr qui devient actif présente
# toujours un certificat à son nom. Émis par le provisioner JWK ceph-dashboard, dont la politique
# n'autorise que ces trois noms ; renouvelé par le certificat lui-même (TLS mutuel).
# Le certificat et la clé ne vont jamais sur le disque des nœuds : ils passent par l'entrée standard de
# ssh vers « ceph dashboard set-ssl-certificate[-key] -i - » et sont stockés par le mgr.
set -euo pipefail
umask 077
# shellcheck source-path=SCRIPTDIR source-path=SCRIPTDIR/../../../M08-E23/ceph/outils source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export CEPH_ADMIN="${CEPH_ADMIN:-ceph01}"

NOMS=(ceph01.par1.medisphere.internal ceph02.par1.medisphere.internal ceph03.par1.medisphere.internal)
DOSSIER="${CEPH_DASHBOARD_DOSSIER:-$HOME/.config/workbook/ceph-dashboard}"
CERT="$DOSSIER/cert.pem"
CLE="$DOSSIER/cle.pem"
MDP="${CEPH_DASHBOARD_MDP:-$HOME/.config/workbook/step-ceph-dashboard.pass}"
PROVISIONER=ceph-dashboard
SEUIL=360h            # 15 jours : politique de certification (M06-E33)
MODE="${1:-auto}"

# hote_actif — nom de l'hôte du mgr actif, lu dans l'URL publiée par le module dashboard.
hote_actif() {
  ms_ceph mgr services --format json 2>/dev/null | jq -r '.dashboard // empty' | sed -E 's#^https?://([^:/]+).*#\1#'
}
empreinte_locale() { openssl x509 -in "$CERT" -noout -fingerprint -sha256 | cut -d= -f2; }
empreinte_presentee() {
  local h
  h="$(hote_actif)"
  [[ -n "$h" ]] || return 0
  timeout 10 openssl s_client -connect "$h:8443" -servername "$h" </dev/null 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || true
}
emettre() {
  local sans=() n
  [[ -r "$MDP" ]] || { ms_erreur "mot de passe du provisioner illisible : $MDP"; exit 1; }
  for n in "${NOMS[@]}"; do sans+=(--san "$n"); done
  ms_info "Émission d'un certificat pour ${NOMS[*]} (provisioner $PROVISIONER)"
  step ca certificate "${NOMS[0]}" "$CERT.nouveau" "$CLE.nouveau" "${sans[@]}" --provisioner "$PROVISIONER" \
    --provisioner-password-file "$MDP" --not-after 720h --force
  mv -f "$CERT.nouveau" "$CERT"
  mv -f "$CLE.nouveau" "$CLE"
}
renouveler() {
  ms_info "Renouvellement (TLS mutuel)"
  step ca renew --force "$CERT" "$CLE"
}
appliquer() {
  ms_ceph dashboard set-ssl-certificate -i - <"$CERT"
  ms_ceph dashboard set-ssl-certificate-key -i - <"$CLE"
  # Le module ne relit pas son certificat à chaud : quelques secondes sans interface, rien d'autre.
  ms_ceph mgr module disable dashboard
  ms_ceph mgr module enable dashboard
}

install -d -m 700 "$DOSSIER"
case "$MODE" in
  --appliquer | --force | auto) ;;
  *) echo "Usage : $0 [--force | --appliquer]" >&2; exit 2 ;;
esac

if [[ ! -s "$CERT" ]] || ! openssl x509 -in "$CERT" -noout -checkend 0 >/dev/null; then
  emettre                                           # absent ou expiré : le renouvellement serait refusé
elif [[ "$MODE" == --force ]] || step certificate needs-renewal --expires-in "$SEUIL" "$CERT" >/dev/null 2>&1; then
  renouveler
fi

locale="$(empreinte_locale)"
if [[ "$MODE" == auto && "$locale" == "$(empreinte_presentee)" ]]; then
  ms_info "Le mgr actif présente déjà le certificat en cours ($(openssl x509 -in "$CERT" -noout -enddate))."
  exit 0
fi

appliquer
for _ in $(seq 1 12); do
  [[ "$(empreinte_presentee)" == "$locale" ]] && { ms_info "Certificat en service sur le mgr actif ($(hote_actif))."; exit 0; }
  sleep 10
done
ms_erreur "après 2 minutes, le mgr actif ne présente toujours pas le nouveau certificat"
exit 1
