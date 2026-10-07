# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur pve01
# check-E42.sh — M04-E42 « Panne : Molecule échoue avant même de tester » : ce dont la création des
# instances dépend est en place (image current, agent, droits de clonage, VMID libres), Molecule
# est disponible, et un job molecule a réussi depuis. Lecture seule.

# shellcheck source=_m04-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-expert.sh"

title "M04-E42 — Les instances Molecule peuvent être créées"
require_cmd ssh jq curl

_m04_e42_tpl='pvesh get /cluster/resources --type vm --output-format json | perl -MJSON::PP -0777 -ne '"'"'for (@{decode_json($_)}) { my %t = map { $_ => 1 } split /[;,]/, ($_->{tags} // ""); print "$_->{vmid}\n" if $_->{template} && $t{gold} && $t{debian13} && $t{current} }'"'"

_m04_e42_job_molecule() {
  gitlab_api "projects/plateforme%2Fansible/jobs?scope%5B%5D=success&per_page=100" \
    | jq -e 'any(.[]; .name | test("^molecule:"))' >/dev/null
}

check_ssh "pve01 : exactement une image dorée gold+debian13+current" "$WB_PVE_HOST" \
  '[ "$('"$_m04_e42_tpl"' | grep -c .)" = 1 ]'
check_ssh "pve01 : agent QEMU activé sur cette image" "$WB_PVE_HOST" \
  't=$('"$_m04_e42_tpl"' | head -n 1); [ -n "$t" ] && qm config "$t" | grep -Eq "^agent: (1|enabled=1)"'
check_ssh "pve01 : le rôle WBAnsible permet le clonage (VM.Clone)" "$WB_PVE_HOST" \
  'pveum role list --output-format json | perl -MJSON::PP -0777 -ne '"'"'for (@{decode_json($_)}) { exit(($_->{privs} // "") =~ /(^|[ ,;])VM\.Clone([ ,;]|$)/ ? 0 : 1) if $_->{roleid} eq "WBAnsible" } exit 1'"'"
check_ssh "pve01 : VMID des instances Molecule (2045-2049) libres" "$WB_PVE_HOST" \
  'for i in 2045 2046 2047 2048 2049; do qm status "$i" >/dev/null 2>&1 && exit 1; done; exit 0'
check_cmd "Molecule disponible dans l'environnement du projet" _m04x_ansible molecule --version
check_cmd "plateforme/ansible : un job molecule:<scénario> a réussi (100 derniers jobs réussis)" _m04_e42_job_molecule
check_cmd "panne M04-E42 close" _m04x_aucune_panne_active E42
