# shellcheck shell=bash
# outils/ci-secrets.sh — prépare l'accès au socle d'un job CI (M04-E27)
#
# Sourcé dans before_script (« . outils/ci-secrets.sh ») par les jobs qui se connectent au socle.
# Entrées : variables CI PROTÉGÉES de type fichier (leur valeur est un CHEMIN) :
#   ANSIBLE_CI_SSH_KEY   clé privée ed25519 « ansible-ci » (autorisée avec from=10.10.20.15)
#   VAULT_PASS_LAB       mot de passe de l'identité Vault « lab »
# Sorties (exportées pour ansible-playbook, elles remplacent les valeurs de ansible.cfg) :
#   ANSIBLE_PRIVATE_KEY_FILE, ANSIBLE_VAULT_IDENTITY_LIST
# Une variable protégée est simplement ABSENTE (vide) hors des références protégées : on le
# dit clairement au lieu de laisser ssh ou ansible-vault échouer de façon obscure.
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

# ssh refuse une clé lisible par d'autres (« UNPROTECTED PRIVATE KEY FILE ») et une clé sans
# saut de ligne final (« invalid format ») : on en fait une copie en 600, terminée par \n.
ANSIBLE_PRIVATE_KEY_FILE="$CI_PROJECT_DIR/.ci-cle-ssh"
# Fichier créé vide en 600 AVANT d'y écrire : la clé n'existe jamais, même un instant, en 644.
rm -f "$ANSIBLE_PRIVATE_KEY_FILE"
(umask 077 && : >"$ANSIBLE_PRIVATE_KEY_FILE")
{
  cat "$ANSIBLE_CI_SSH_KEY"
  # $(…) retire un \n final : si la sortie n'est pas vide, le dernier caractère n'en était pas un.
  if [[ -n "$(tail -c 1 "$ANSIBLE_CI_SSH_KEY")" ]]; then echo; fi
} >>"$ANSIBLE_PRIVATE_KEY_FILE"
export ANSIBLE_PRIVATE_KEY_FILE

# ansible.cfg désigne le fichier de adm01 (~/.config/workbook/ansible-vault.pass), absent ici.
export ANSIBLE_VAULT_IDENTITY_LIST="lab@${VAULT_PASS_LAB}"
