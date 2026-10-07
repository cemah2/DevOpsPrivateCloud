#!/usr/bin/env bash
# preparer-snippets-tofu.sh — ce dont OpenTofu a besoin sur pve01 pour gérer des snippets
# cloud-init (M05-E19). À lancer en root sur pve01. Rejouable.
#
# Pourquoi tout ça ? Proxmox n'accepte pas l'envoi de snippets par son API (seulement les ISO,
# modèles de conteneurs et images à importer) : le provider bpg/proxmox les écrit par SSH,
# avec « sudo /usr/bin/tee <fichier> ». Il lui faut donc :
#   1. un stockage dédié aux snippets d'OpenTofu (tofu-snippets) : le provider lit le chemin
#      d'un stockage par GET /storage/<id>, qui exige Datastore.Allocate ; et une VM ne peut
#      référencer un snippet (cicustom) qu'avec ce même privilège. Sur un stockage DÉDIÉ, ce
#      privilège ne donne rien d'autre : sur hdd-bulk, il permettrait de supprimer n'importe
#      quel volume (ISO, sauvegardes locales, disque de données de s3-01 !) ;
#   2. un compte Linux sans privilège, wb-tofu, joignable en SSH depuis adm01 seulement ;
#   3. un sudo limité à ce que le provider exécute : « pvesm apiinfo » (test de sudo) et
#      « tee » vers le dossier des snippets, rien d'autre (jamais qm ni pvesm en entier).
#      La règle « tee » est une EXPRESSION RÉGULIÈRE ancrée (^…$, sudo >= 1.9.10) : avec un
#      motif glob (…/snippets/[a-zA-Z0-9_][a-zA-Z0-9_.-]*, forme de la documentation du
#      provider), le « * » de sudoers couvre aussi les espaces et les « / » : « sudo tee
#      …/snippets/ab /etc/sudoers.d/x » ou « …/snippets/ab/../../../etc/shadow » seraient
#      acceptés, et wb-tofu deviendrait root. Le script le vérifie à la fin (sudo -l).
#
# Variables : CLE_PUBLIQUE (obligatoire, clé de admin@adm01), DOSSIER (/mnt/hdd-bulk/tofu-snippets)
set -euo pipefail

CLE_PUBLIQUE="${CLE_PUBLIQUE:?CLE_PUBLIQUE=\"ssh-ed25519 AAAA… admin@adm01\" attendu}"
DOSSIER="${DOSSIER:-/mnt/hdd-bulk/tofu-snippets}"
STOCKAGE=tofu-snippets
COMPTE=wb-tofu
UTILISATEUR_PVE=wb-tofu@pve
JETON=tofu

# --- 1. Stockage dédié ------------------------------------------------------------------
mountpoint -q /mnt/hdd-bulk || { echo "/mnt/hdd-bulk n'est pas monté : arrêt." >&2; exit 1; }
install -d -m 0755 "$DOSSIER" "$DOSSIER/snippets"
if ! pvesm status --storage "$STOCKAGE" >/dev/null 2>&1; then
  # is_mountpoint : stockage « hors ligne » si /mnt/hdd-bulk n'est pas monté (jamais
  # d'écriture sur le disque système à la place du HDD).
  pvesm add dir "$STOCKAGE" --path "$DOSSIER" --content snippets --is_mountpoint /mnt/hdd-bulk
fi
pvesm status --storage "$STOCKAGE"

# --- 2. Compte Linux wb-tofu, clé de adm01 restreinte ---------------------------------------
id "$COMPTE" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$COMPTE"
install -d -m 0700 -o "$COMPTE" -g "$COMPTE" "/home/$COMPTE/.ssh"
printf 'from="10.10.10.10",no-agent-forwarding,no-port-forwarding,no-X11-forwarding %s\n' "$CLE_PUBLIQUE" \
  > "/home/$COMPTE/.ssh/authorized_keys"
chown "$COMPTE:$COMPTE" "/home/$COMPTE/.ssh/authorized_keys"
chmod 0600 "/home/$COMPTE/.ssh/authorized_keys"

# --- 3. sudo minimal (fichier validé avant installation, puis éprouvé) -----------------------
command -v visudo >/dev/null || { echo "sudo absent de pve01 : apt install sudo, puis relance." >&2; exit 1; }
tmp="$(mktemp)"
cat > "$tmp" <<SUDO
# /etc/sudoers.d/wb-tofu — OpenTofu (provider bpg/proxmox) : écriture des snippets (M05-E19)
# Test de disponibilité de sudo par le provider (lecture seule)
$COMPTE ALL=(root) NOPASSWD: /usr/sbin/pvesm apiinfo
# Écriture d'un snippet dans le stockage dédié, et nulle part ailleurs. Expression régulière
# ancrée (sudo >= 1.9.10) : UN seul argument, un nom de fichier sans espace ni « / ».
# Jamais de glob ici : le « * » de sudoers accepte espaces et « / » (élévation vers root).
$COMPTE ALL=(root) NOPASSWD: /usr/bin/tee ^$DOSSIER/snippets/[A-Za-z0-9_][A-Za-z0-9_.-]*\$
SUDO
visudo -cf "$tmp"
install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/wb-tofu
rm -f "$tmp"

# Épreuve de la règle (sudo -l en root : lecture seule, rien n'est exécuté).
autorise() { sudo -l -U "$COMPTE" "$@" >/dev/null 2>&1; }
autorise /usr/bin/tee "$DOSSIER/snippets/essai-0123456789ab.yaml" \
  || { echo "ÉCHEC : la règle refuse l'écriture d'un snippet légitime." >&2; exit 1; }
for interdit in "$DOSSIER/snippets/ab /etc/sudoers.d/x" "$DOSSIER/snippets/ab/../../../../etc/shadow" \
  "-a $DOSSIER/snippets/ab" "/etc/passwd"; do
  # shellcheck disable=SC2086 # découpage voulu : chaque cas est une liste d'arguments
  if autorise /usr/bin/tee $interdit; then
    echo "DANGER : sudo accepte « tee $interdit » : règle retirée." >&2
    rm -f /etc/sudoers.d/wb-tofu
    exit 1
  fi
done
echo "sudoers de $COMPTE : écriture des snippets seule, éprouvée."

# --- 4. Droits Proxmox sur le seul stockage dédié (utilisateur ET jeton, privsep) -----------
if pvesh get /access/roles/WBTofuSnippets >/dev/null 2>&1; then
  pveum role modify WBTofuSnippets --privs "Datastore.Allocate Datastore.AllocateSpace Datastore.Audit"
else
  pveum role add WBTofuSnippets --privs "Datastore.Allocate Datastore.AllocateSpace Datastore.Audit"
fi
pveum acl modify "/storage/$STOCKAGE" --users "$UTILISATEUR_PVE" --roles WBTofuSnippets
pveum acl modify "/storage/$STOCKAGE" --tokens "$UTILISATEUR_PVE!$JETON" --roles WBTofuSnippets
pveum user token permissions "$UTILISATEUR_PVE" "$JETON" --path "/storage/$STOCKAGE"
