# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants entre apostrophes
# break-E21.sh — M29-E21 « Panne : Terratest laisse des VMs derrière lui »
#
# Crée sur pve01 deux petites VMs ARRÊTÉES, sans disque, VMID 2298 et 2299 (plage Terratest), nommées
# tt-<hexa>, dans le sous-pool lab/terratest (là où le test de M29-E08 les met), sur le VNet vsandbox,
# avec la note que pose le test, et, pour chacune, un état local orphelin du test sur adm01, à
# l'emplacement où CopyTerraformFolderToTemp le laisse
# (/tmp/TestVmDebian<n>/vm-debian/test/fixtures/vm/terraform.tfstate). Aucune entrée NetBox n'est créée
# (le script n'a pas de jeton d'écriture NetBox) : un vrai test interrompu laisserait aussi l'adresse
# allouée, RB-293 le traite. Variantes :
#   1. test interrompu par le délai de go test (panique : aucun defer) : étiquettes env-m29 + terratest,
#      l'une des VMs en démarrage automatique (onboot) : au prochain redémarrage de pve01, 1 Go de pris ;
#   2. même chose, mais étiquette « terratest » absente (le test de Lucas ne la posait plus) : un
#      nettoyage par étiquette ne les voit pas ;
#   3. destruction en échec : les deux VMs ont « protection: 1 » (la fixture du test ne force pas
#      protection = false), « tofu destroy » du test a échoué.
# Rien d'autre n'est touché sur pve01 : refus si 2298 ou 2299 existe déjà. L'annulation ne détruit que
# des VMs qui portent encore le nom et la date de création notés à l'injection.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m29-commun.sh
source "$WB_ROOT/modules/29-tests-resilience/corrige/pannes/_m29-commun.sh"

_E21_VMIDS=(2298 2299)
_E21_TMP="${WB_M29_TERRATEST_TMP:-/tmp}"

_e21_libres() {
  local v
  for v in "${_E21_VMIDS[@]}"; do
    remote "$WB_PVE_HOST" "qm status $v" </dev/null >/dev/null 2>&1 && return 1
  done
  return 0
}

_e21_sain() {
  m29_outils ssh || return 1
  if ! _e21_libres; then
    echo "Une VM occupe déjà 2298 ou 2299 sur $WB_PVE_HOST (Terratest en cours, ou reste d'un essai) :" >&2
    echo "termine ou nettoie d'abord (lab/bin/check 29 21)." >&2
    return 1
  fi
  remote "$WB_PVE_HOST" "pvesh get /pools --output-format json" </dev/null 2>/dev/null |
    jq -e 'any(.[]; .poolid == "lab/terratest")' >/dev/null 2>&1 ||
    { echo "Sous-pool « lab/terratest » introuvable sur $WB_PVE_HOST : fais d'abord M29-E08." >&2; return 1; }
}

# _e21_etat FICHIER NOM VMID — état OpenTofu (format 4) minimal de la fixture test/fixtures/vm (M29-E08) :
# une VM, créée par le module « vm » (le dossier vm-debian lui-même).
_e21_etat() {
  jq -n --arg n "$2" --argjson v "$3" --arg lin "$(cat /proc/sys/kernel/random/uuid)" '{
    version: 4, terraform_version: "1.13.4", serial: 7, lineage: $lin, outputs: {},
    resources: [
      {module: "module.vm", mode: "managed", type: "proxmox_virtual_environment_vm", name: "vm",
       provider: "provider[\"registry.opentofu.org/bpg/proxmox\"]",
       instances: [{schema_version: 0, attributes: {id: ($v | tostring), vm_id: $v, name: $n, node_name: "pve01",
         pool_id: "lab/terratest", tags: ["env-m29", "terratest"], started: false}}]}
    ]}' >"$1"
}

_m29E21_une() {
  local n="$1" n1 n2 tags prot onboot1 dossier
  n1="tt-$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
  n2="tt-$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
  case "$n" in
    1) tags="env-m29;terratest"; prot=0; onboot1=1 ;;
    2) tags="env-m29"; prot=0; onboot1=0 ;;
    3) tags="env-m29;terratest"; prot=1; onboot1=0 ;;
  esac
  wb_exec "$WB_PVE_HOST" V1=2298 V2=2299 N1="$n1" N2="$n2" TAGS="$tags" PROT="$prot" ONBOOT1="$onboot1" <<'EOF' || return 1
for v in "$V1" "$V2"; do
  if qm status "$v" >/dev/null 2>&1; then echo "VM $v déjà présente" >&2; exit 1; fi
done
NOTE="Terratest M29-E08 (poste) : VM jetable, détruite par le test. Orpheline ? RB-293."
qm create "$V1" --name "$N1" --memory 1024 --cores 1 --ostype l26 --net0 virtio,bridge=vsandbox \
  --tags "$TAGS" --pool lab/terratest --onboot "$ONBOOT1" --protection "$PROT" --description "$NOTE" >/dev/null || exit 1
journal "VM $V1 ($N1) créée (arrêtée, sans disque)"
qm create "$V2" --name "$N2" --memory 1024 --cores 1 --ostype l26 --net0 virtio,bridge=vsandbox \
  --tags "$TAGS" --pool lab/terratest --onboot 0 --protection "$PROT" --description "$NOTE" >/dev/null || exit 1
journal "VM $V2 ($N2) créée (arrêtée, sans disque)"
for v in "$V1" "$V2"; do
  qm config "$v" | sed -n 's/^meta: .*ctime=\([0-9]*\).*/\1/p' > "$WB_DIR/$WB_EX.ctime-$v"
done
EOF
  m29_poser E21 vms "2298 $n1
2299 $n2"
  # Un état orphelin par test interrompu, là où CopyTerraformFolderToTemp laisse la copie du module.
  local dossiers="" v nom fixture
  for v in 2298 2299; do
    if [[ "$v" == 2298 ]]; then nom="$n1"; else nom="$n2"; fi
    dossier="$_E21_TMP/TestVmDebian$(printf '%09d' "$((RANDOM * 32768 + RANDOM))")"
    fixture="$dossier/vm-debian/test/fixtures/vm"
    mkdir -p "$fixture"
    _e21_etat "$fixture/terraform.tfstate" "$nom" "$v"
    # le reste d'une copie du module, comme le laisse CopyTerraformFolderToTemp
    printf '# copie temporaire de vm-debian (Terratest)\n' >"$dossier/vm-debian/main.tf"
    printf '# copie temporaire de la fixture (Terratest)\n' >"$fixture/main.tf"
    find "$dossier" -exec touch -d '-3 hours' {} +
    dossiers+="$dossier"$'\n'
  done
  m29_poser E21 dossier "${dossiers%$'\n'}"
  m29_journal E21 "variante $n : VMs $n1, $n2, états ${dossiers//$'\n'/ }"
}

_m29E21_defaire() {
  local v nom d
  while read -r v nom; do
    [[ -n "${nom:-}" ]] || continue
    wb_exec "$WB_PVE_HOST" V="$v" NOM="$nom" <<'EOF' || true
qm status "$V" >/dev/null 2>&1 || exit 0
cfg="$(qm config "$V")"
nom="$(printf '%s\n' "$cfg" | sed -n 's/^name: //p')"
ct="$(printf '%s\n' "$cfg" | sed -n 's/^meta: .*ctime=\([0-9]*\).*/\1/p')"
attendu="$(cat "$WB_DIR/$WB_EX.ctime-$V" 2>/dev/null || true)"
if [ "$nom" != "$NOM" ] || [ -z "$attendu" ] || [ "$ct" != "$attendu" ]; then
  journal "VM $V n'est plus celle de la panne ($nom) : laissée en place"
  exit 0
fi
qm stop "$V" >/dev/null 2>&1 || true
qm set "$V" --protection 0 >/dev/null 2>&1 || true
qm destroy "$V" --purge 1 --destroy-unreferenced-disks 1 >/dev/null && journal "VM $V ($NOM) détruite"
rm -f "$WB_DIR/$WB_EX.ctime-$V"
EOF
  done < <(m29_lire E21 vms)
  while IFS= read -r d; do
    if [[ -n "$d" && "$d" == "$_E21_TMP"/TestVmDebian* && -d "$d" ]]; then rm -rf -- "$d"; fi
  done < <(m29_lire E21 dossier)
  m29_oublier E21 vms
  m29_oublier E21 dossier
}

panne_E21_v1() { _e21_sain && m29_essayer E21 3 1; }
panne_E21_v2() { _e21_sain && m29_essayer E21 3 2; }
panne_E21_v3() { _e21_sain && m29_essayer E21 3 3; }

verifier_E21() {
  local v nom d
  while read -r v nom; do
    [[ -n "${nom:-}" ]] || continue
    remote "$WB_PVE_HOST" "qm config $v" </dev/null 2>/dev/null | grep -q "^name: $nom\$" || return 1
  done < <(m29_lire E21 vms)
  while IFS= read -r d; do
    [[ -f "$d/vm-debian/test/fixtures/vm/terraform.tfstate" ]] || return 1
  done < <(m29_lire E21 dossier)
}

annuler_E21() {
  _m29E21_defaire
  m29_journal E21 "annulation"
}

resume_E21() {
  echo "Le pipeline Terratest de vm-debian échoue par intermittence et pve01 porte des VMs tt- que personne ne reconnaît."
}

symptome_E21() {
  wb_symptome "Ticket INC-5621 — De : Karim Benali" \
    "Le pipeline Terratest de vm-debian échoue une fois sur deux depuis hier (« VM already exists »" \
    "ou création refusée), alors que personne n'a touché au module. En regardant pve01, je vois" \
    "des VMs tt-… arrêtées que personne ne reconnaît. Claire s'inquiète pour le budget mémoire" \
    "du lab au prochain redémarrage. Fais le ménage, et fais en sorte qu'on ne revive pas ça." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 29 21"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 29 E21 3 "$@"; }
fi
