# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M06-E37 « Panne : certificat refusé »
#
# Variantes :
#   1. nbx01 : le fichier ssl_certificate de nginx ne contient plus que le certificat feuille (chaîne
#      sans l'intermédiaire « MédiSphère Intermediate CA ») → les clients qui n'ont que la racine
#      refusent (« unable to get local issuer certificate ») ; un navigateur qui a l'intermédiaire
#      en cache peut l'accepter ;
#   2. git01 : « restauration de /etc/gitlab » qui remet un certificat signé par une « MédiSphère CA
#      provisoire » (CA éphémère fabriquée par le script, même clé privée que le vrai certificat) ;
#   3. runner01 : la racine MédiSphère retirée du magasin système (fichier supprimé,
#      update-ca-certificates --fresh, gitlab-runner redémarré « après les mises à jour ») ;
#   4. runner01 : horloge avancée de 45 jours, chrony arrêté (« reprise d'un instantané ») → tous les
#      certificats (30 jours max.) paraissent expirés ; les certificats SSH aussi : runner01 n'est
#      plus joignable qu'en secours (agent QEMU, compte secours).
# Sauvegardes : /var/lib/workbook/M06-E37.* sur l'hôte touché (fichiers d'origine, décalage d'horloge).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m06-commun.sh
source "$WB_ROOT/modules/06-services-socle/corrige/pannes/_m06-commun.sh"

_E37_NBX="nbx01.$_M06_ZONE"
_E37_GIT="git01.$_M06_ZONE"

# _e37_runner_curl — code de curl lancé SUR runner01 vers GitLab (par l'agent QEMU : SSH peut être
# en cause). Affiche le code de sortie de curl (0 = certificat accepté).
_e37_runner_curl() {
  local o
  o="$(remote "$WB_PVE_HOST" "qm guest exec ${_M06_VMID[runner01]} --timeout 30 -- bash -c 'curl -sS -o /dev/null --max-time 10 https://$_E37_GIT/users/sign_in; echo rc=\$?'" 2>/dev/null)" || true
  sed -nE 's/.*rc=([0-9]+).*/\1/p' <<<"$o" | head -n 1
}

_e37_precondition() {
  local h
  for h in "$_E37_NBX ${_M06_IP[nbx01]}" "$_E37_GIT ${_M06_IP[git01]}"; do
    # shellcheck disable=SC2086
    if [[ "$(m06_curl_code $h)" != 0 ]]; then
      wb_avert "le certificat de ${h%% *} est déjà refusé avant la panne : lab/bin/check 06 37"
      return 1
    fi
  done
  if [[ "$(_e37_runner_curl)" != 0 ]]; then
    wb_avert "runner01 n'accepte déjà pas le certificat de GitLab (ou l'agent QEMU ne répond pas) : lab/bin/check 06 37"
    return 1
  fi
}

_mE37_une() {
  local n="$1" rc=0
  case "$n" in
    1)
      m06_wb_exec nbx01 >/dev/null <<'EOF' || rc=$?
f="$(nginx -T 2>/dev/null | sed -nE 's/^[[:space:]]*ssl_certificate[[:space:]]+([^;]+);.*/\1/p' | head -n 1)"
[ -n "$f" ] && [ -f "$f" ] || exit 10
[ "$(grep -c 'BEGIN CERTIFICATE' "$f")" -ge 2 ] || exit 10
sauver "$f"
awk '{ print } /END CERTIFICATE/ { exit }' "$WB_DIR/M06-E37.$(printf '%s' "$f" | tr '/' '_').orig" >"$f"
noter_injecte "$f"
nginx -t >/dev/null 2>&1 && systemctl reload nginx
journal "$f : chaîne réduite au certificat feuille"
EOF
      ;;
    2)
      m06_wb_exec git01 FQDN="$_E37_GIT" >/dev/null <<'EOF' || rc=$?
cle_rb() { sed -nE "s/^[[:space:]]*(gitlab_rails\['nginx'\]|nginx)\['$1'\][[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\2/p" /etc/gitlab/gitlab.rb | tail -n 1; }
crt="$(cle_rb ssl_certificate)"; crt="${crt:-/etc/gitlab/ssl/$FQDN.crt}"
key="$(cle_rb ssl_certificate_key)"; key="${key:-/etc/gitlab/ssl/$FQDN.key}"
[ -f "$crt" ] && [ -f "$key" ] || exit 10
t="$(mktemp -d)"
openssl req -utf8 -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
  -subj "/O=MédiSphère/CN=MédiSphère CA provisoire" -keyout "$t/ca.key" -out "$t/ca.crt" >/dev/null 2>&1 || exit 1
openssl req -new -key "$key" -subj "/CN=$FQDN" -out "$t/req.csr" >/dev/null 2>&1 || exit 1
printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n' "$FQDN" >"$t/ext"
openssl x509 -req -in "$t/req.csr" -CA "$t/ca.crt" -CAkey "$t/ca.key" -CAcreateserial -days 365 \
  -extfile "$t/ext" -out "$t/feuille.crt" >/dev/null 2>&1 || exit 1
sauver "$crt"
cat "$t/feuille.crt" >"$crt"
noter_injecte "$crt"
rm -rf "$t"
gitlab-ctl hup nginx >/dev/null
journal "$crt : remplacé par un certificat signé par une « MédiSphère CA provisoire » (CA éphémère détruite)"
EOF
      ;;
    3)
      m06_wb_exec runner01 >/dev/null <<'EOF' || rc=$?
f=/usr/local/share/ca-certificates/medisphere-root-ca.crt
[ -f "$f" ] || exit 10
sauver "$f"
rm -f "$f"
noter_injecte "$f"
update-ca-certificates --fresh >/dev/null 2>&1
systemctl restart gitlab-runner
journal "racine MédiSphère retirée du magasin système, gitlab-runner redémarré"
EOF
      ;;
    4)
      m06_wb_exec runner01 >/dev/null <<'EOF' || rc=$?
[ -f "$WB_DIR/M06-E37.horloge" ] || printf '%s\n' "$(date +%s)" >"$WB_DIR/M06-E37.horloge"
systemctl stop chrony
date -s "@$(( $(date +%s) + 45 * 86400 ))" >/dev/null
journal "chrony arrêté, horloge avancée de 45 jours (référence dans M06-E37.horloge)"
EOF
      ;;
  esac
  ((rc == 0)) || return "$rc"
  sleep 2
  case "$n" in
    1) [[ "$(m06_curl_code "$_E37_NBX" "${_M06_IP[nbx01]}")" != 0 ]] ;;
    2) [[ "$(m06_curl_code "$_E37_GIT" "${_M06_IP[git01]}")" != 0 ]] ;;
    3 | 4) [[ "$(_e37_runner_curl)" =~ ^[1-9] ]] ;;
  esac || { _e37_defaire "$n"; return 10; }
  m06_fermer_ssh runner01
}

_e37_defaire() {
  case "$1" in
    1)
      m06_wb_exec nbx01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur nbx01"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
garder_reparations
restaurer_fichiers
nginx -t >/dev/null 2>&1 && systemctl reload nginx
EOF
      ;;
    2)
      m06_wb_exec git01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur git01"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
garder_reparations
restaurer_fichiers
gitlab-ctl hup nginx >/dev/null
EOF
      ;;
    3)
      m06_wb_exec_invite "${_M06_VMID[runner01]}" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur runner01 (agent QEMU)"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
garder_reparations
restaurer_fichiers
update-ca-certificates >/dev/null 2>&1
systemctl restart gitlab-runner
EOF
      ;;
    4)
      # Par l'agent QEMU : avec l'horloge décalée, les certificats SSH sont refusés.
      m06_wb_exec_invite "${_M06_VMID[runner01]}" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur runner01 (agent QEMU) : horloge à vérifier"
f="$WB_DIR/M06-E37.horloge"
[ -f "$f" ] || exit 0
ecart=$(( $(date +%s) - $(cat "$f") ))
if [ "$ecart" -gt 864000 ]; then
  # Toujours en avance de plus de 10 jours : on revient en arrière (approximation), puis chrony affine.
  date -s "@$(( $(date +%s) - 45 * 86400 ))" >/dev/null
  journal "annulation : horloge reculée de 45 jours"
else
  journal "annulation : horloge déjà corrigée (réparation)"
fi
systemctl start chrony
sleep 5
chronyc makestep >/dev/null 2>&1 || true
rm -f "$f"
EOF
      ;;
  esac
}

_e37_injecter() {
  _e37_precondition || return 1
  m06_essayer E37 4 "$1"
}

panne_E37_v1() { _e37_injecter 1; }
panne_E37_v2() { _e37_injecter 2; }
panne_E37_v3() { _e37_injecter 3; }
panne_E37_v4() { _e37_injecter 4; }

verifier_E37() {
  case "${WB_VAR:-0}" in
    1) [[ "$(m06_curl_code "$_E37_NBX" "${_M06_IP[nbx01]}")" != 0 ]] ;;
    2) [[ "$(m06_curl_code "$_E37_GIT" "${_M06_IP[git01]}")" != 0 ]] ;;
    3 | 4) [[ "$(_e37_runner_curl)" =~ ^[1-9] ]] ;;
    *) return 1 ;;
  esac
}

annuler_E37() {
  case "${WB_VAR:-}" in
    [1-4]) _e37_defaire "$WB_VAR" ;;
    *) _e37_defaire 4; _e37_defaire 3; _e37_defaire 2; _e37_defaire 1 ;;
  esac
  m06_fermer_ssh runner01 git01 nbx01
}

resume_E37() {
  case "${WB_VAR:-0}" in
    1) echo "Les scripts et l'inventaire Ansible refusent le certificat de NetBox ; le navigateur de Claire l'accepte." ;;
    2) echo "GitLab : certificat refusé partout (navigateurs, git, runner) depuis une intervention sur git01." ;;
    *) echo "La CI est en panne : runner01 refuse les certificats du socle, GitLab s'ouvre pourtant normalement." ;;
  esac
}

symptome_E37() {
  local -a l
  case "${WB_VAR:-0}" in
    1) l=("Mon script de synchronisation et l'inventaire Ansible NetBox échouent depuis ce matin :"
      "« certificate verify failed: unable to get local issuer certificate » sur nbx01."
      "Pourtant Claire ouvre NetBox dans son navigateur sans aucun avertissement. Le certificat"
      "a été renouvelé cette nuit, comme d'habitude.") ;;
    2) l=("Plus personne n'accède à GitLab proprement : le navigateur affiche un avertissement de"
      "sécurité, git push répond « server certificate verification failed », les jobs sont en"
      "attente. InfoGér a fait hier soir une « restauration de la configuration » sur git01.") ;;
    *) l=("Tous les jobs de CI sont en échec ou restent en attente depuis la nuit : « x509:"
      "certificate … » dans les journaux du runner. GitLab s'ouvre pourtant normalement depuis"
      "adm01 et depuis mon poste, et personne n'a touché à son certificat.") ;;
  esac
  wb_symptome "Ticket INC-3343 — De : Julien Petit" "${l[@]}" "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 06 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 06 E37 4 "$@"; }
fi
