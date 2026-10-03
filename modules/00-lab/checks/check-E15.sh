# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E15.sh — M00-E15 : Outiller le poste d'administration adm01
# À lancer depuis adm01, avec l'agent SSH chargé. Lecture seule.

title "M00-E15 — Outiller le poste d'administration adm01"

# --- Poste et clé ---
check_output "ce script tourne sur adm01" '^adm01$' hostname -s
check_cmd "clé privée ~/.ssh/id_ed25519 présente" test -s "$HOME/.ssh/id_ed25519"
check_output "la clé est de type ED25519" 'ED25519' ssh-keygen -l -f "$HOME/.ssh/id_ed25519.pub"
check_output "clé privée lisible par son seul propriétaire (600)" '^600$' stat -c %a "$HOME/.ssh/id_ed25519"
check_cmd "clé privée protégée par une phrase de passe" \
  bash -c "test -s \"\$HOME/.ssh/id_ed25519\" && ! ssh-keygen -y -P '' -f \"\$HOME/.ssh/id_ed25519\""
check_cmd "un agent SSH détient au moins une clé" ssh-add -l

# --- Configuration SSH (effective, telle que ssh la calcule) ---
check_output "alias pve01 : utilisateur root" '^user root$' ssh -G pve01
check_output "alias pbs01 : utilisateur root" '^user root$' ssh -G pbs01
check_output "alias pbs01 : cible 10.20.10.10" '^hostname 10\.20\.10\.10$' ssh -G pbs01
check_output "alias gw01 : utilisateur admin" '^user admin$' ssh -G gw01
check_output "alias dns01 : utilisateur admin" '^user admin$' ssh -G dns01

# --- Connexions sans interaction (mode batch, comme les scripts) ---
check_ssh "pve01 : connexion SSH en root sans interaction" pve01 'test "$(id -u)" -eq 0'
check_ssh "gw01 : connexion SSH et sudo sans interaction" gw01 'sudo -n true'
check_ssh "dns01 : connexion SSH et sudo sans interaction" dns01 'sudo -n true'

# --- Outils ---
for t in git curl jq dig tcpdump mtr tmux shellcheck; do
  check_cmd "outil présent : $t" bash -c "command -v $t || test -x /usr/sbin/$t"
done
check_cmd "python3 peut créer un environnement virtuel (python3-venv)" python3 -c 'import ensurepip'

# --- Dépôt du workbook et configuration locale ---
check_cmd "le dépôt du workbook est un clone git" git -C "$ROOT" rev-parse --is-inside-work-tree
check_cmd "lab/lab.env présent" test -f "$ROOT/lab/lab.env"
check_cmd "lab.env : WB_PVE_HOST ne vaut plus localhost" test "$WB_PVE_HOST" != localhost
check_cmd "lab.env : WB_PBS_LAN renseignée (adresse LAN de hp01)" test -n "${WB_PBS_LAN:-}"
