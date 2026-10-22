# shellcheck shell=bash
# shellcheck disable=SC2016  # motifs bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E44.sh — M26-E44 « Sous le capot : eBPF, LSM et chaîne d'admission » : compte rendu présent,
# structuré, commité, sans secret, et qui cite des faits relevés (programmes eBPF, hooks LSM, auditID).
# Lecture seule.
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E44 — Sous le capot : eBPF, LSM et chaîne d'admission"
require_cmd git

_m26_e44_cr="$_m26x_depot/docs/securite/durcissement/analyses/sous-le-capot-ebpf-lsm-admission.md"
check_cmd "compte rendu présent (docs/securite/durcissement/analyses/sous-le-capot-ebpf-lsm-admission.md)" test -s "$_m26_e44_cr"
check_output "section sur les programmes eBPF (bpftool, Falco/Tetragon/Cilium)" '^#+ .*(eBPF|bpftool)' cat "$_m26_e44_cr"
check_output "section sur les LSM (hooks, ordre, AppArmor/SELinux/BPF-LSM)" '^#+ .*LSM' cat "$_m26_e44_cr"
check_output "section sur la chaîne d'admission (authn → authz → mutation → validation → persistance)" '^#+ .*[Aa]dmission' cat "$_m26_e44_cr"
check_output "section « Réponses aux questions »" '^#+ .*[Rr][ée]ponses' cat "$_m26_e44_cr"
check_cmd "notions citées : bpftool prog, hook, CEL, webhook, auditID, seccomp" \
  bash -c 'for m in "bpftool prog" hook CEL webhook auditID seccomp; do grep -qi -- "$m" "$1" || exit 1; done' _ "$_m26_e44_cr"
check_cmd "chiffres relevés : au moins un identifiant de programme eBPF et un ordre de la chaîne" \
  bash -c 'grep -Eq "prog(ram)? +(ID|id)? *[0-9]+|id +[0-9]+:" "$1" && grep -Eqi "mutat|validat" "$1"' _ "$_m26_e44_cr"
check_cmd "compte rendu commité, sans modification en attente" \
  _m26x_doc_commite "docs/securite/durcissement/analyses/sous-le-capot-ebpf-lsm-admission.md"
check_cmd "aucun secret recopié dans le compte rendu" \
  bash -c '! grep -Eqi "PRIVATE KEY|glpat-|eyJhbGciOi|BAO_SECRET|X-Vault-Token" "$1"' _ "$_m26_e44_cr"
