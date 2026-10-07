# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # « $ANSIBLE_VAULT » est un littéral (en-tête des fichiers chiffrés)
# break-E38.sh — M04-E38 « Panne : Decryption failed »
#
# Tout se passe sur adm01 (rien sur les hôtes du socle). La chaîne de déchiffrement est celle de
# M04-E12/E30 : vault_identity_list → (script client outils/vault-pass-client.sh →) fichier
# ~/.config/workbook/ansible-vault-lab.pass ou, à défaut, ansible-vault.pass. Variantes :
#   1. rotation à moitié faite : le fichier de mot de passe de l'identité lab contient un NOUVEAU
#      mot de passe, l'ancien a été rangé dans <fichier>.ancien-AAAAMMJJ, mais aucun fichier
#      chiffré n'a été rechiffré (rekey) ;
#   2. droits du fichier de mot de passe « harmonisés » par Lucas : 644 si un script client le
#      lit (le script refuse un fichier lisible par d'autres), 700 si Ansible le lit directement
#      (un fichier exécutable est EXÉCUTÉ comme un script) ;
#   3. en-tête de group_vars/all/vault.yml réétiqueté (« classé » par Lucas) : identité critique
#      si elle est déclarée, sinon prod ; vault_id_match = True ajouté s'il manquait : seul le
#      secret de cette étiquette est essayé, il ne convient pas (ou n'existe pas) ;
#   4. group_vars/all/vault.yml rechiffré (ansible-vault rekey) avec un mot de passe que Lucas a
#      gardé pour lui (« test de rotation ») : la copie de travail diffère du dépôt.
# Sauvegardes : ~/.local/state/workbook/M04-E38/ (fichier de mot de passe, ansible.cfg, vault.yml).
# Annulation : seuls les fichiers encore dans l'état posé par la panne sont rétablis ; le fichier
# ansible-vault.pass.ancien-* n'est retiré que s'il est intact.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m04-commun.sh
source "$WB_ROOT/modules/04-ansible/corrige/pannes/_m04-commun.sh"

# _e38_fichier_mdp — fichier de mot de passe effectivement lu pour l'identité lab.
_e38_fichier_mdp() {
  if [[ -e "$_M04_CFG/ansible-vault-lab.pass" ]]; then
    printf '%s\n' "$_M04_CFG/ansible-vault-lab.pass"
  else
    printf '%s\n' "$_M04_VAULT_PASS"
  fi
}

# _e38_identites — valeur effective de vault_identity_list (texte de ansible-config dump).
_e38_identites() {
  local d
  d="$(m04_ansible ansible-config dump --only-changed 2>/dev/null)" || true
  sed -n 's/^DEFAULT_VAULT_IDENTITY_LIST([^)]*) = //p' <<<"$d"
}

_e38_dechiffre() {
  m04_ansible ansible-vault view "$_M04_VAULT_FICHIER" >/dev/null 2>&1
}

_e38_precondition() {
  m04_prerequis || return 1
  [[ -f "$(_e38_fichier_mdp)" ]] || { wb_avert "$(_e38_fichier_mdp) absent (M04-E12)"; return 1; }
  [[ -f "$_M04_SRC/$_M04_VAULT_FICHIER" ]] || { wb_avert "$_M04_VAULT_FICHIER absent (M04-E12)"; return 1; }
  _e38_dechiffre || { wb_avert "le coffre ne se déchiffre déjà pas avant la panne : lab/bin/check 04 38"; return 1; }
}

# _e38_mdp — mot de passe aléatoire (jamais affiché)
_e38_mdp() {
  local s
  s="$(head -c 30 /dev/urandom | base64 -w0 | tr -d '/+=')"
  printf '%s\n' "${s:0:28}"
}

_mE38_une() {
  local n="$1" f="$_M04_SRC/$_M04_VAULT_FICHIER" mdp ancien ids etiquette
  mdp="$(_e38_fichier_mdp)"
  case "$n" in
    1)
      ancien="$mdp.ancien-$(date -d yesterday +%Y%m%d)"
      [[ -e "$ancien" ]] && return 10
      m04_sauver E38 "$mdp" || return 1
      m04_sauver E38 "$ancien" || return 1
      cp -a "$mdp" "$ancien" || return 1
      (umask 077 && _e38_mdp >"$mdp") || return 1
      touch -d '-1 day' "$ancien"
      m04_noter E38 "$mdp"
      m04_noter E38 "$ancien"
      m04_journal E38 "nouveau mot de passe dans ${mdp##*/}, ancien rangé dans ${ancien##*/}, aucun rekey"
      ;;
    2)
      m04_sauver E38 "$mdp" || return 1
      if [[ "$(_e38_identites)" == *"lab@"*"-client"* ]]; then
        chmod 644 "$mdp"
      else
        chmod 700 "$mdp"
      fi
      m04_noter E38 "$mdp"
      m04_journal E38 "${mdp##*/} : droits passés à $(stat -c %a "$mdp")"
      ;;
    3)
      head -n 1 "$f" | grep -q '^\$ANSIBLE_VAULT;' || return 10
      ids="$(_e38_identites)"
      if [[ "$ids" == *"critique@"* ]]; then etiquette=critique; else etiquette=prod; fi
      m04_sauver E38 "$f" || return 1
      if ! grep -Eqi '^[[:space:]]*vault_id_match[[:space:]]*[=:][[:space:]]*(true|yes|1)' "$_M04_SRC/ansible.cfg"; then
        m04_sauver E38 "$_M04_SRC/ansible.cfg" || return 1
        m04_ini_set "$_M04_SRC/ansible.cfg" defaults vault_id_match True \
          "SEC-584 : chaque fichier chiffré n'est déchiffré que par le secret de son identifiant" || return 1
        m04_noter E38 "$_M04_SRC/ansible.cfg"
      fi
      # En-tête 1.2 avec une autre étiquette (le corps chiffré ne dépend pas de l'étiquette).
      sed -i -E "1s/^\\\$ANSIBLE_VAULT;1\.[12];AES256(;.*)?\$/\$ANSIBLE_VAULT;1.2;AES256;${etiquette}/" "$f"
      m04_noter E38 "$f"
      m04_journal E38 "en-tête de vault.yml étiqueté ${etiquette} (vault_id_match actif)"
      ;;
    4)
      local t rc=0
      m04_sauver E38 "$f" || return 1
      t="$(mktemp)"
      (umask 077 && _e38_mdp >"$t")
      m04_ansible ansible-vault rekey --new-vault-password-file "$t" "$_M04_VAULT_FICHIER" >/dev/null 2>&1 || rc=$?
      rm -f -- "$t"
      ((rc == 0)) || { m04_restaurer E38; return 1; }
      m04_noter E38 "$f"
      m04_journal E38 "vault.yml rechiffré avec un mot de passe inconnu (jeté)"
      ;;
  esac
  if _e38_dechiffre; then
    m04_restaurer E38
    return 10
  fi
}

_e38_injecter() {
  _e38_precondition || return 1
  m04_instantane E38
  m04_essayer E38 4 "$1"
}

panne_E38_v1() { _e38_injecter 1; }
panne_E38_v2() { _e38_injecter 2; }
panne_E38_v3() { _e38_injecter 3; }
panne_E38_v4() { _e38_injecter 4; }

verifier_E38() { ! _e38_dechiffre; }

annuler_E38() { m04_restaurer E38; }

resume_E38() {
  echo "Les playbooks s'arrêtent dès le chargement de l'inventaire sur une erreur du coffre Ansible (Vault)."
}

symptome_E38() {
  wb_symptome "Ticket INC-3144 — De : Julien Petit" \
    "Plus aucun playbook ne passe depuis adm01 : tout s'arrête avant la première tâche, sur" \
    "une erreur du coffre (« Decryption failed » chez moi ; Karim dit avoir eu un message" \
    "différent hier soir, il ne l'a pas noté). Même « ansible-inventory --graph » échoue." \
    "Lucas a « fait un peu de ménage dans les secrets » cette semaine, mais il est en congé." \
    "Il me faut les playbooks pour 16 h, SANS affaiblir la protection des secrets." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 04 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 04 E38 4 "$@"; }
fi
