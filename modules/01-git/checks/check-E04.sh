# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E04.sh — M01-E04 : GitLab CE sur git01 avec une PKI provisoire.
# Lancé depuis adm01. Lecture seule : configuration Proxmox (alias pve01), DNS, git01 (alias
# git01, admin + sudo -n), certificat présenté sur le port 443, fichiers de ~/pki-provisoire.

title "M01-E04 — Installer GitLab CE sur git01 avec une PKI provisoire"
require_cmd openssl curl dig git

_m01_pki="$HOME/pki-provisoire"
_m01_fqdn="git01.par1.medisphere.internal"
_m01_ip="10.10.20.12"

# Empreinte SHA-256 d'un certificat PEM (partie hexadécimale seule)
_m01_empreinte() { openssl x509 -noout -fingerprint -sha256 -in "$1" 2>/dev/null | cut -d= -f2; }
# Certificat présenté par git01 sur le port 443 (PEM sur la sortie standard)
_m01_cert_servi() {
  openssl s_client -connect "$_m01_fqdn:443" -servername "$_m01_fqdn" </dev/null 2>/dev/null \
    | openssl x509 2>/dev/null
}
# Durée de validité d'un certificat PEM lu sur l'entrée standard, en jours
_m01_duree() {
  local pem debut fin
  pem="$(cat)"
  debut="$(openssl x509 -noout -startdate <<<"$pem" | cut -d= -f2)"
  fin="$(openssl x509 -noout -enddate <<<"$pem" | cut -d= -f2)"
  echo $(( ($(date -d "$fin" +%s) - $(date -d "$debut" +%s)) / 86400 ))
}
# Propriété d'une VM dans les ressources du cluster (même méthode que M00-E12)
_m01_vm() {
  printf "pvesh get /cluster/resources --type vm --output-format json | perl -MJSON::PP -0777 -ne 'exit(!grep { \$_->{vmid} == %d && (\$_->{%s} // q{}) eq q{%s} } @{decode_json(\$_)})'" "$1" "$2" "$3"
}

# --- 1. PKI provisoire sur adm01 ----------------------------------------------------------
title "1/5 PKI provisoire (adm01)"
check_output "dossier pki-provisoire en mode 700" '^700$' stat -c %a "$_m01_pki"
check_output "ca.key en mode 600" '^600$' stat -c %a "$_m01_pki/ca.key"
check_output "ca.crt : sujet « MédiSphère CA provisoire »" 'CA provisoire' \
  openssl x509 -in "$_m01_pki/ca.crt" -noout -subject -nameopt oneline,-esc_msb
check_cmd "ca.crt : certificat d'autorité (CA:TRUE, extension critique)" \
  bash -c 'e=$(openssl x509 -in "$1" -noout -ext basicConstraints 2>/dev/null); grep -q critical <<<"$e" && grep -q "CA:TRUE" <<<"$e"' \
  _ "$_m01_pki/ca.crt"
check_cmd "ca.key correspond à ca.crt" \
  bash -c '[ "$(openssl pkey -in "$1" -pubout 2>/dev/null)" = "$(openssl x509 -in "$2" -noout -pubkey 2>/dev/null)" ]' \
  _ "$_m01_pki/ca.key" "$_m01_pki/ca.crt"
check_cmd "racine installée dans le magasin de adm01 (identique à ca.crt)" \
  cmp -s /usr/local/share/ca-certificates/medisphere-provisoire.crt "$_m01_pki/ca.crt"
check_cmd "racine prise en compte par update-ca-certificates sur adm01" \
  test -e /etc/ssl/certs/medisphere-provisoire.pem
check_cmd "aucun fichier de clé privée (*.key) suivi dans le dépôt $WB_DEPOT" \
  bash -c '! git -C "$1" ls-files | grep -Eq "\.key$"' _ "${WB_DEPOT:-$HOME/medisphere}"
_m01_fp_ca="$(_m01_empreinte "$_m01_pki/ca.crt")"

# --- 2. La VM 1004 ----------------------------------------------------------------------
title "2/5 VM 1004 git01"
check_ssh "la VM 1004 s'appelle git01" "$WB_PVE_HOST" "$(_m01_vm 1004 name git01)"
check_ssh "git01 est dans le pool lab" "$WB_PVE_HOST" "$(_m01_vm 1004 pool lab)"
check_ssh "git01 est démarrée" "$WB_PVE_HOST" "$(_m01_vm 1004 status running)"
check_ssh "git01 est un clone complet (aucune dépendance au template)" "$WB_PVE_HOST" \
  "qm config 1004 | grep -E '^scsi0: ' | grep -vq 'base-9000'"
check_ssh "git01 : étiquettes socle et role-gitlab" "$WB_PVE_HOST" \
  "t=\$(qm config 1004 | sed -n 's/^tags: //p'); echo \";\$t;\" | grep -q ';socle;' && echo \";\$t;\" | grep -q ';role-gitlab;'"
check_ssh_output "git01 : 4 vCPU" "$WB_PVE_HOST" '^cores: 4$' "qm config 1004"
check_ssh_output "git01 : 8192 Mo de RAM" "$WB_PVE_HOST" '^memory: 8192$' "qm config 1004"
check_ssh_output "git01 : mémoire fixe (ballooning désactivé)" "$WB_PVE_HOST" '^balloon: 0$' "qm config 1004"
check_ssh_output "git01 : disque scsi0 d'au moins 60 Go" "$WB_PVE_HOST" \
  '^scsi0: .*size=(([6-9][0-9]|[1-9][0-9]{2,})G|[0-9]+T)' "qm config 1004"
check_ssh_output "git01 : net0 sur le VNet vinfra" "$WB_PVE_HOST" '^net0: .*bridge=vinfra(,|$)' "qm config 1004"
check_ssh "git01 : ipconfig0 = 10.10.20.12/24, passerelle 10.10.20.1" "$WB_PVE_HOST" \
  "qm config 1004 | grep -E '^ipconfig0: ' | grep -E 'ip=10\.10\.20\.12/24(,|\$)' | grep -Eq 'gw=10\.10\.20\.1(,|\$)'"
check_ssh_output "git01 démarre avec pve01 (onboot)" "$WB_PVE_HOST" '^onboot: 1' "qm config 1004"
check_ssh "git01 démarre après dns01 (ordre de démarrage)" "$WB_PVE_HOST" \
  'o() { qm config "$1" | sed -nE "s/^startup:.*order=([0-9]+).*/\1/p"; }; g=$(o 1004); d=$(o 1002); [ -n "$g" ] && [ -n "$d" ] && [ "$g" -gt "$d" ]'

# --- 3. Intégration au socle --------------------------------------------------------------
title "3/5 Intégration au socle"
check_dns "DNS : $_m01_fqdn → $_m01_ip" "$_m01_fqdn" A '^10\.10\.20\.12$' 10.10.20.10
check_dns "DNS : inverse de $_m01_ip → $_m01_fqdn" 12.20.10.10.in-addr.arpa PTR \
  '^git01\.par1\.medisphere\.internal\.$' 10.10.20.10
check_ssh "alias SSH git01 : connexion et sudo -n" git01 "sudo -n true"
check_ssh_output "git01 : nom complet $_m01_fqdn" git01 '^git01\.par1\.medisphere\.internal$' "hostname -f"
check_ssh_output "git01 : synchronisé sur 10.10.20.1 (chrony)" git01 \
  '^\^\*[[:space:]]+10\.10\.20\.1[[:space:]]' "sudo -n chronyc -n sources"
check_ssh_output "git01 : swap actif" git01 '.' "swapon --show --noheadings"
check_ssh_output "git01 : vm.swappiness = 10" git01 '^10$' "sysctl -n vm.swappiness"
check_ssh_output "git01 : racine provisoire dans le magasin système" git01 "^${_m01_fp_ca:-absente}\$" \
  "openssl x509 -noout -fingerprint -sha256 -in /usr/local/share/ca-certificates/medisphere-provisoire.crt | cut -d= -f2"
check_ssh_output "git01 : racine provisoire dans /etc/gitlab/trusted-certs/" git01 "^${_m01_fp_ca:-absente}\$" \
  'for f in /etc/gitlab/trusted-certs/*.crt; do openssl x509 -noout -fingerprint -sha256 -in "$f" | cut -d= -f2; done'

# --- 4. GitLab ------------------------------------------------------------------------------
title "4/5 GitLab sur git01"
check_ssh_output "paquet gitlab-ce 19.x (19.3 ou plus récent) installé" git01 '^19\.([3-9]|[1-9][0-9])\.' \
  'dpkg-query -W -f "\${Version}" gitlab-ce'
check_ssh "paquet gitlab-ce bloqué (apt-mark hold)" git01 "apt-mark showhold | grep -qx gitlab-ce"
check_ssh "gitlab.rb : external_url en https://$_m01_fqdn" git01 \
  "sudo -n grep -Eq '^[[:space:]]*external_url[[:space:]]+.https://git01\.par1\.medisphere\.internal/?.' /etc/gitlab/gitlab.rb"
check_ssh "gitlab.rb : Let's Encrypt désactivé explicitement" git01 \
  "sudo -n grep -Eq '^[[:space:]]*letsencrypt\[.enable.\][[:space:]]*=[[:space:]]*false' /etc/gitlab/gitlab.rb"
check_ssh_output "gitlab.rb : accessible à root seul (600)" git01 '^600 root$' "sudo -n stat -c '%a %U' /etc/gitlab/gitlab.rb"
check_ssh_output "clé privée TLS en 600" git01 '^600$' "sudo -n stat -c %a /etc/gitlab/ssl/$_m01_fqdn.key"
check_ssh "tous les services de gitlab-ctl sont en marche" git01 \
  's=$(sudo -n gitlab-ctl status) && grep -q "^run: puma:" <<<"$s" && ! grep -qv "^run:" <<<"$s"'
check_ssh "supervision embarquée arrêtée (ni prometheus, ni alertmanager, ni node-exporter)" git01 \
  's=$(sudo -n gitlab-ctl status) && ! grep -Eq "^[a-z]+: (prometheus|alertmanager|node-exporter):" <<<"$s"'
check_ssh "Puma en mode simple (aucun processus « cluster worker »)" git01 \
  'pgrep -f "puma .*gitlab" >/dev/null && ! pgrep -f "puma: cluster worker" >/dev/null'

# --- 5. HTTPS vu depuis adm01 --------------------------------------------------------------
title "5/5 HTTPS depuis adm01"
check_http "page de connexion en HTTPS, certificat vérifié par le magasin système" \
  "https://$_m01_fqdn/users/sign_in" 200
check_cmd "chaîne présentée valide jusqu'à la CA provisoire" \
  bash -c 'openssl s_client -connect "$1:443" -servername "$1" -CAfile "$2" -verify_return_error </dev/null >/dev/null 2>&1' \
  _ "$_m01_fqdn" "$_m01_pki/ca.crt"
_m01_servi="$(_m01_cert_servi)"
check_output "certificat servi : SAN DNS git01.par1.medisphere.internal" 'DNS:git01\.par1\.medisphere\.internal' \
  openssl x509 -noout -ext subjectAltName <<<"$_m01_servi"
check_output "certificat servi : SAN DNS git01 (nom court)" 'DNS:git01(,|$)' \
  openssl x509 -noout -ext subjectAltName <<<"$_m01_servi"
check_output "certificat servi : SAN IP 10.10.20.12" 'IP Address:10\.10\.20\.12' \
  openssl x509 -noout -ext subjectAltName <<<"$_m01_servi"
check_output "certificat servi : usage serverAuth" 'TLS Web Server Authentication' \
  openssl x509 -noout -ext extendedKeyUsage <<<"$_m01_servi"
check_cmd "certificat servi : validité de 397 jours au plus" \
  bash -c 'n=$(cat); [ -n "$n" ] && [ "$n" -gt 0 ] && [ "$n" -le 397 ]' <<<"$(_m01_duree <<<"$_m01_servi" 2>/dev/null)"

# --- Documentation ------------------------------------------------------------------------
_m01_depot="${WB_DEPOT:-$HOME/medisphere}"
check_cmd "inventaire.md (commité) mentionne git01 et 10.10.20.12" \
  bash -c 'f=$(git -C "$1" show HEAD:docs/socle/inventaire.md 2>/dev/null) && grep -q "git01" <<<"$f" && grep -q "10\.10\.20\.12" <<<"$f"' \
  _ "$_m01_depot"
check_cmd "matrice-flux.md (commité) mentionne git01" \
  bash -c 'git -C "$1" show HEAD:docs/socle/matrice-flux.md 2>/dev/null | grep -q "git01"' _ "$_m01_depot"
