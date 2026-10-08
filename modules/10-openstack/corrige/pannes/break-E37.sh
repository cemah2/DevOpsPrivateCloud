# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M10-E37 « Panne : l'instance ignore sa configuration »
#
# Préparation : pile sonde m10-e37-* (réseau 172.30.37.0/24, routeur, groupe de sécurité, port, IP
# flottante) ; une instance témoin m10-e37-temoin doit recevoir sa clé SSH par les métadonnées
# (connexion par clé réussie) AVANT l'injection, puis elle est supprimée (le port reste).
# Variantes :
#   1. calculs : conteneur neutron_ovn_metadata_agent arrêté sur oscmp01 et oscmp02 ;
#   2. calculs : metadata_proxy_shared_secret de neutron_ovn_metadata_agent.ini (fichier généré par
#      Kolla, modifié hors du code) différent de celui de nova-metadata → nova répond 403 ;
#   3. osctl01 : conteneur nova_metadata arrêté (HAProxy n'a plus de serveur pour le port 8775).
# Constat : une nouvelle instance m10-e37-sonde, créée APRÈS l'injection sur le même port, répond au
# ping et ouvre son port 22, mais refuse la clé (cloud-init n'a pas obtenu ses métadonnées).
# Sauvegardes : /var/lib/workbook/M10-E37.* sur les hôtes touchés. --annuler rétablit ce qui est
# encore cassé ET supprime la pile sonde.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m10-commun.sh
source "$WB_ROOT/modules/10-openstack/corrige/pannes/_m10-commun.sh"

_e37_precondition() {
  local ip
  m10_prerequis || return 1
  m10_pile_detruire E37
  echo "Création de la pile de test et d'une instance témoin (3 à 5 minutes)…"
  if ! m10_pile_creer E37 || ! m10_pile_serveur E37 m10-e37-temoin; then
    wb_avert "impossible de créer la pile de test (quotas du projet plateforme ?)"
    return 1
  fi
  ip="$(m10_lire E37 fip)"
  if ! m10_attendre 300 m10_ssh_sonde "$ip"; then
    wb_avert "l'instance témoin ($ip) n'accepte pas la clé avant la panne : métadonnées ou réseau déjà malades (lab/bin/check 10 18)"
    return 1
  fi
  m10_osp server delete --wait m10-e37-temoin >/dev/null 2>&1 || return 1
  m10_oublier_hote "$ip"
}

_mE37_une() {
  local n="$1" rc=0 h
  case "$n" in
    1)
      for h in "${_M10_CMP[@]}"; do
        m10_exec "$h" >/dev/null <<'EOF' || rc=$?
ctr_arreter neutron_ovn_metadata_agent
EOF
        ((rc == 0)) || break
      done
      ;;
    2)
      for h in "${_M10_CMP[@]}"; do
        m10_exec "$h" >/dev/null <<'EOF' || rc=$?
f=/etc/kolla/neutron-ovn-metadata-agent/neutron_ovn_metadata_agent.ini
[ -f "$f" ] || exit 10
neuf="$(python3 -c 'import secrets; print(secrets.token_hex(20))')"
subst "$f" '^(metadata_proxy_shared_secret[ \t]*=[ \t]*)\S+' "\\g<1>$neuf" || exit $?
ctr_redemarrer neutron_ovn_metadata_agent || exit 1
journal "$f : metadata_proxy_shared_secret remplacé, neutron_ovn_metadata_agent redémarré"
EOF
        ((rc == 0)) || break
      done
      ;;
    3)
      m10_exec "$_M10_CTL" >/dev/null <<'EOF' || rc=$?
ctr_arreter nova_metadata
EOF
      ;;
  esac
  ((rc == 0)) || return "$rc"
  sleep 5
  if ! _e37_constat; then
    _e37_defaire "$n"
    m10_osp server delete --wait m10-e37-sonde >/dev/null 2>&1 || true
    return 10
  fi
}

# _e37_constat — nouvelle instance : port 22 ouvert (système démarré) mais clé refusée.
_e37_constat() {
  local ip
  ip="$(m10_lire E37 fip)"
  echo "Création de l'instance de test après la panne (jusqu'à 7 minutes)…"
  m10_osp server delete --wait m10-e37-sonde >/dev/null 2>&1 || true
  m10_pile_serveur E37 m10-e37-sonde || return 1
  # cloud-init attend les métadonnées avant de laisser démarrer sshd : délai long.
  m10_attendre 420 m10_port22 "$ip" || return 1
  sleep 20
  ! m10_ssh_sonde "$ip"
}

_e37_defaire() {
  local h
  case "$1" in
    1 | 2)
      for h in "${_M10_CMP[@]}"; do
        m10_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (agent de métadonnées)"
if [ -n "$(defaire_subst)" ]; then ctr_redemarrer neutron_ovn_metadata_agent; fi
ctr_relancer_arretes
EOF
      done
      ;;
    3)
      m10_exec "$_M10_CTL" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur osctl01 (nova_metadata)"
ctr_relancer_arretes
EOF
      ;;
  esac
}

_e37_injecter() {
  _e37_precondition || return 1
  m10_essayer E37 3 "$1"
}

panne_E37_v1() { _e37_injecter 1; }
panne_E37_v2() { _e37_injecter 2; }
panne_E37_v3() { _e37_injecter 3; }

verifier_E37() {
  # Le constat a été fait par _e37_constat ; on revérifie que la sonde refuse toujours la clé.
  local ip
  ip="$(m10_lire E37 fip)"
  m10_port22 "$ip" && ! m10_ssh_sonde "$ip"
}

annuler_E37() {
  case "${WB_VAR:-}" in
    1 | 2) _e37_defaire 1 ;;
    3) _e37_defaire 3 ;;
    *) _e37_defaire 1; _e37_defaire 3 ;;
  esac
  m10_pile_detruire E37
}

resume_E37() {
  echo "Les nouvelles instances démarrent mais ignorent leur configuration (pas de clé SSH, nom d'hôte par défaut) : m10-e37-sonde, $(m10_lire E37 fip)."
}

symptome_E37() {
  wb_symptome "Ticket INC-3743 — De : Julien Petit" \
    "Les instances créées depuis ce matin démarrent (ACTIVE, ping OK) mais n'appliquent pas" \
    "leur configuration : ma clé SSH est refusée (« Permission denied (publickey) »), le nom" \
    "d'hôte n'est pas le bon et mon script user-data ne s'est pas exécuté. Les instances plus" \
    "anciennes vont bien. Pour reproduire : m10-e37-sonde (projet plateforme), IP flottante" \
    "$(m10_lire E37 fip), utilisateur debian, clé ~/.local/state/workbook/M10-sonde/id_ed25519." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 10 37 (avant --annuler, qui supprime la sonde)"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 10 E37 3 "$@"; }
fi
