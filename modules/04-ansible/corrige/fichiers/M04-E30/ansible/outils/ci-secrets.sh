# shellcheck shell=bash
# outils/ci-secrets.sh — prépare l'accès au socle d'un job CI (M04-E27, révisé en M04-E30)
#
# Sourcé dans before_script (« . outils/ci-secrets.sh ») par les jobs qui se connectent au socle.
# Entrées : variables CI PROTÉGÉES de type fichier (leur valeur est un CHEMIN) :
#   ANSIBLE_CI_SSH_KEY   clé privée ed25519 « ansible-ci » (autorisée avec from=10.10.20.15)
#   VAULT_PASS_LAB       mot de passe Vault de l'identité « lab » (tous les jobs du socle)
#   VAULT_PASS_CRITIQUE  identité « critique » : portée d'environnement lab/socle, absente
#                        ailleurs (check-socle de MR) — c'est voulu
# Depuis E30, Ansible lit les mots de passe Vault par outils/vault-pass-client.sh (ansible.cfg),
# qui consulte VAULT_PASS_<IDENTITÉ> : plus besoin de remplacer vault_identity_list ici.
# Nettoyage : after_script supprime « $CI_PROJECT_DIR/.ci-cle-ssh ».

_ci_manquants=()
for _ci_v in ANSIBLE_CI_SSH_KEY VAULT_PASS_LAB; do
  if [[ -z "${!_ci_v:-}" || ! -s "${!_ci_v}" ]]; then
    _ci_manquants+=("$_ci_v")
  fi
done
if ((${#_ci_manquants[@]} > 0)); then
  echo "Secrets CI absents : ${_ci_manquants[*]}." >&2
  echo "Ils sont protégés : ce job ne s'exécute que sur main, sur une branche conf/*, ou dans une MR issue de conf/*." >&2
  unset _ci_manquants _ci_v
  return 1
fi
unset _ci_manquants _ci_v

# Fichiers des variables CI : le script client refuse un mot de passe lisible par d'autres.
chmod 600 "$VAULT_PASS_LAB"
if [[ -n "${VAULT_PASS_CRITIQUE:-}" && -f "$VAULT_PASS_CRITIQUE" ]]; then
  chmod 600 "$VAULT_PASS_CRITIQUE"
else
  echo "Identité Vault « critique » non fournie à ce job (normal hors environnement lab/socle)."
fi

# ssh refuse une clé lisible par d'autres et une clé sans saut de ligne final : copie en 600.
ANSIBLE_PRIVATE_KEY_FILE="$CI_PROJECT_DIR/.ci-cle-ssh"
rm -f "$ANSIBLE_PRIVATE_KEY_FILE"
(umask 077 && : >"$ANSIBLE_PRIVATE_KEY_FILE")
{
  cat "$ANSIBLE_CI_SSH_KEY"
  if [[ -n "$(tail -c 1 "$ANSIBLE_CI_SSH_KEY")" ]]; then echo; fi
} >>"$ANSIBLE_PRIVATE_KEY_FILE"
export ANSIBLE_PRIVATE_KEY_FILE
