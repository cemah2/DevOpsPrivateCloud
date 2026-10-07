# shellcheck shell=bash
# _m03-commun.sh — fonctions partagées par les pannes M03-E19 à M03-E22.
# Sourcé par les break-EXX.sh du module 03, APRÈS lab/lib/pannes-lib.sh.
#
# Deux familles d'outils :
#   - côté adm01 : _m03_cle_adm01, _m03_vm_libre ;
#   - côté pve01 : le texte _M03_PVE_FONCTIONS, à envoyer en tête d'un script distant :
#       { printf '%s\n' "$_M03_PVE_FONCTIONS"; cat <<'EOF'
#       ...script...
#       EOF
#       } | wb_exec "$WB_PVE_HOST" VAR=valeur
#     Il fournit m03_current, m03_est_template, m03_libre, m03_attendre_agent, m03_gexec,
#     m03_detruire, m03_disque_cloudinit (root sur pve01, JSON lu avec perl JSON::PP).
#
# VMID réservés aux pannes du module (PLAN §4.8, plage M03 2030-2039 et essais 9090-9099) :
#   2036 E22 (Rocky), 2037 E21 (cloud-init), 2038-2039 E20 (clones), 9095 E20 (image de test).
# Les tests automatiques de l'apprenant (tests/tester-image.sh) utilisent 2030-2033.

# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
{
  _M03_VNET_SANDBOX=vsandbox
  _M03_STOCKAGE="${WB_STORAGE_NVME:-local-nvme}"
}

# _m03_cle_adm01 — clé publique SSH de adm01 (celle que cloud-init injecte dans les VMs).
_m03_cle_adm01() {
  local f
  for f in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
    if [[ -s "$f" ]]; then head -n 1 "$f"; return 0; fi
  done
  wb_avert "aucune clé publique SSH dans ~/.ssh (id_ed25519.pub attendue, M00-E15)"
  return 1
}

read -r -d '' _M03_PVE_FONCTIONS <<'FONCTIONS' || true
# --- fonctions M03 (pve01, root) -------------------------------------------------
m03_vms_json() { pvesh get /cluster/resources --type vm --output-format json; }

# m03_current FAMILLE — VMID du template étiqueté gold + FAMILLE + current (vide si aucun).
m03_current() {
  m03_vms_json | M03_FAMILLE="$1" perl -MJSON::PP -0777 -ne '
    for (@{decode_json($_)}) {
      next unless ($_->{template} // 0) == 1;
      my %t = map { $_ => 1 } split /[;,\s]+/, ($_->{tags} // "");
      if ($t{gold} && $t{current} && $t{$ENV{M03_FAMILLE}}) { print $_->{vmid}, "\n"; last }
    }'
}

m03_est_template() { qm config "$1" 2>/dev/null | grep -q '^template: 1'; }
m03_libre() { ! qm status "$1" >/dev/null 2>&1; }

# m03_attendre_agent VMID [secondes] — 0 dès que l'agent QEMU répond.
m03_attendre_agent() {
  local id="$1" t="${2:-240}"
  while [ "$t" -gt 0 ]; do
    qm guest cmd "$id" ping >/dev/null 2>&1 && return 0
    sleep 5; t=$((t - 5))
  done
  return 1
}

# m03_gexec VMID commande... — exécute dans la VM par l'agent ; affiche la sortie standard,
# renvoie le code de sortie de la commande (1 si l'agent ne répond pas).
m03_gexec() {
  local id="$1" j; shift
  j="$(qm guest exec "$id" --timeout 300 -- "$@" 2>/dev/null)" || return 1
  printf '%s' "$j" | perl -MJSON::PP -0777 -ne '
    my $r = decode_json($_); print $r->{"out-data"} // "";
    exit(($r->{exited} // 0) ? ($r->{exitcode} // 1) : 1)'
}

# m03_detruire VMID — arrête et détruit une VM ou un template (ressource créée par la panne).
m03_detruire() {
  local id="$1"
  m03_libre "$id" && return 0
  qm stop "$id" --skiplock 1 >/dev/null 2>&1 || true
  qm destroy "$id" --purge 1 --destroy-unreferenced-disks 1 >/dev/null 2>&1
}

# m03_disque_cloudinit VMID — nom de l'emplacement qui porte le lecteur cloud-init (ide2…).
m03_disque_cloudinit() {
  qm config "$1" | sed -nE 's/^((ide|sata|scsi)[0-9]+): .*cloudinit.*/\1/p' | head -n 1
}
# ---------------------------------------------------------------------------------
FONCTIONS
