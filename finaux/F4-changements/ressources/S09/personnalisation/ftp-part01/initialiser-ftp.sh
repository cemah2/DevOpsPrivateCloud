#!/bin/bash
# initialiser-ftp.sh — exécuté DANS l'image de ftp-part01 par virt-customize (F4-S09), hors ligne.
# Comptes des partenaires (mots de passe aléatoires, inconnus : « transmis aux partenaires »),
# dossiers de dépôt et quelques mois de dépôts FICTIFS (références de rendez-vous, sans nom).
set -euo pipefail
# PAM de vsftpd exige un shell listé dans /etc/shells (pam_shells) : contournement d'InfoGér.
grep -qx /usr/sbin/nologin /etc/shells || echo /usr/sbin/nologin >> /etc/shells
for p in partenaire-labo partenaire-radio; do
  id "$p" >/dev/null 2>&1 || useradd --system --create-home --home-dir "/srv/depot/$p" --shell /usr/sbin/nologin "$p"
  printf '%s:%s\n' "$p" "$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')" | chpasswd
  install -d -o "$p" -g "$p" -m 0750 "/srv/depot/$p/entrant" "/srv/depot/$p/archive"
done
# Dépôts fictifs : un fichier par jour ouvré sur 120 jours, contenu déterministe.
for j in $(seq 1 120); do
  d="$(date -d "-$j days" +%F)"
  [ "$(date -d "$d" +%u)" -le 5 ] || continue
  for p in partenaire-labo partenaire-radio; do
    f="/srv/depot/$p/entrant/${p#partenaire-}-$d.csv"
    {
      echo "reference_rdv;type;statut;date"
      for k in 1 2 3; do echo "$(( (j * 37 + k * 11) % 2600 + 101 ));${p#partenaire-};disponible;$d"; done
    } > "$f"
    touch -d "$d 18:30" "$f"
    chown "$p:$p" "$f"
    chmod 0640 "$f"
  done
done
/usr/local/sbin/archiver-depots
