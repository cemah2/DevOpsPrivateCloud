# shellcheck shell=bash
# charger-acces.sh — accès OpenTofu de la session courante sur adm01 (M05-E27).
#
# À SOURCER depuis la racine de plateforme/infra (ou n'importe où) :
#   . outils/charger-acces.sh
# Charge, depuis ~/.config/workbook/ (fichiers en 600 uniquement) :
#   pve-tofu.env            PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN (M05-E03)
#   s3-tofu.env             AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_PROFILE (M05-E10, E11)
#   tofu-chiffrement.pass   phrase de chiffrement → TF_ENCRYPTION (fournisseur « pbkdf2 etat »)
# N'affiche jamais un secret. Retourne 1 (sans quitter ton shell) si quelque chose manque.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "charger-acces : à sourcer (« . outils/charger-acces.sh »), pas à exécuter" >&2
  exit 2
fi

_ca_dossier="$HOME/.config/workbook"

_ca_lisible_600() {
  [[ -r "$1" ]] || { echo "charger-acces : $1 introuvable ou illisible" >&2; return 1; }
  [[ "$(stat -c %a "$1")" == "600" ]] || { echo "charger-acces : $1 doit être en 600 (chmod 600)" >&2; return 1; }
}

_ca_charger() {
  local f phrase
  for f in pve-tofu.env s3-tofu.env; do
    _ca_lisible_600 "$_ca_dossier/$f" || return 1
    set -a
    # shellcheck source=/dev/null
    . "$_ca_dossier/$f"
    set +a
  done

  _ca_lisible_600 "$_ca_dossier/tofu-chiffrement.pass" || return 1
  phrase="$(tr -d '\n' < "$_ca_dossier/tofu-chiffrement.pass")"
  # La phrase est insérée dans du HCL : on n'accepte que ce que produit « openssl rand -hex 32 »
  # (ou de la base64) — ni guillemet, ni barre oblique inverse, ni « $ », ni « % ».
  if [[ ${#phrase} -lt 16 || ! "$phrase" =~ ^[A-Za-z0-9+/=._-]+$ ]]; then
    echo "charger-acces : phrase de chiffrement trop courte ou caractères non admis" >&2
    return 1
  fi
  # Guillemets VOULUS (le contenu est du HCL, pas du shell) :
  # shellcheck disable=SC2089,SC2090
  printf -v TF_ENCRYPTION 'key_provider "pbkdf2" "etat" { passphrase = "%s" }' "$phrase"
  # shellcheck disable=SC2090
  export TF_ENCRYPTION
  echo "charger-acces : accès Proxmox ($PROXMOX_VE_ENDPOINT), S3 (${AWS_PROFILE:-sans profil}) et chiffrement chargés."
}

_ca_charger
_ca_rc=$?
unset -f _ca_charger _ca_lisible_600
unset _ca_dossier
return "$_ca_rc"
