# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E07.sh — M04-E07 : Templates Jinja2
# À lancer depuis adm01. Lecture seule : contenu de /etc/motd et du fait local sur chaque
# hôte, faits relus par le module setup (sans élévation), playbook en --check.
# Après M04-E10 (rôle base), le playbook n'existe plus : ses contrôles sont ignorés, seul
# l'état des hôtes (que le rôle doit maintenir) reste vérifié.

# shellcheck source=_m04-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-decouverte.sh"

title "M04-E07 — Templates Jinja2"
require_cmd git jq curl

_m04_pb="playbooks/identite-hotes.yml"
if _m04_role_base_en_place; then
  skip "contrôles du playbook $_m04_pb et de son template" "repris et remplacés par le rôle base en M04-E10"
else
  check_cmd "$_m04_pb publié sur main" _m04_fichier_main "$_m04_pb"
  check_cmd "template du message d'accueil publié (playbooks/templates/motd.j2)" \
    _m04_fichier_main playbooks/templates/motd.j2
  check_cmd "le motd passe par le module template (pas de copy avec du contenu en dur)" \
    _m04_contient "$_m04_pb" 'ansible\.builtin\.template:'
fi

# --- Résultat sur les hôtes -----------------------------------------------------------------
_m04_setup="$(_m04_json ansible socle -m ansible.builtin.setup -a 'filter=ansible_local')"
for _m04_paire in gw01:routeur adm01:bastion dns01:dns git01:gitlab runner01:runner; do
  _m04_h="${_m04_paire%%:*}"
  _m04_r="${_m04_paire#*:}"
  check_ssh_output "$_m04_h : /etc/motd donne le FQDN de l'hôte" "$_m04_h" "$_m04_h\\.par1\\.medisphere\\.internal" \
    'cat /etc/motd'
  check_ssh_output "$_m04_h : /etc/motd donne son rôle (ligne « Rôle : $_m04_r »)" "$_m04_h" \
    "R(ô|o)le[[:space:]]*:[[:space:]]*$_m04_r([^a-z_]|\$)" 'cat /etc/motd'
  check_ssh_output "$_m04_h : /etc/motd signale qu'il est géré par Ansible" "$_m04_h" '^#.*[Aa]nsible' 'cat /etc/motd'
  check_ssh_output "$_m04_h : fait local medisphere.fact en JSON, rôle $_m04_r" "$_m04_h" "^$_m04_r\$" \
    "python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[\"role\"])' /etc/ansible/facts.d/medisphere.fact"
  check_ssh "$_m04_h : fait local non exécutable (lu comme JSON, pas exécuté)" "$_m04_h" \
    'test -f /etc/ansible/facts.d/medisphere.fact && ! test -x /etc/ansible/facts.d/medisphere.fact'
  check_output "$_m04_h : Ansible voit le fait local (ansible_local.medisphere.role)" "^$_m04_r\$" \
    _m04_resultat "$_m04_setup" "$_m04_h" '.ansible_facts.ansible_local.medisphere.role // empty'
done
check_ssh_output "gw01 : le motd du routeur rappelle de valider le pare-feu avant rechargement" gw01 'nft -c' 'cat /etc/motd'
check_ssh "dns01 : pas d'avertissement « routeur » sur un autre hôte" dns01 '! grep -q "nft -c" /etc/motd'
check_ssh_output "git01 : le motd liste les runbooks de la forge" git01 'RB-01[0-3]' 'cat /etc/motd'

# --- Idempotence --------------------------------------------------------------------------------
if _m04_role_base_en_place; then
  skip "idempotence de $_m04_pb" "l'idempotence du rôle base est vérifiée par lab/bin/check 04 10"
else
  _m04_sortie="$(_m04_simuler "$_m04_pb")"
  for _m04_h in $_M04_SOCLE; do
    check_cmd "--check sur $_m04_h : aucun changement, aucun échec (rien qui varie à chaque passage)" \
      _m04_recap "$_m04_sortie" "$_m04_h"
  done
fi
