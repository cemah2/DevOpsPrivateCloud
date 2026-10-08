#!/usr/bin/env bats
# Tests de bin/ms-capacite-cluster (M09-E31). pve_api est remplacée par une fonction qui répond
# selon des variables d'état : aucun accès réseau.
# shellcheck disable=SC2329,SC2317,SC2034
# shellcheck source-path=SCRIPTDIR

setup() {
  # shellcheck source=../../bin/ms-capacite-cluster
  source "$BATS_TEST_DIRNAME/../../bin/ms-capacite-cluster"
  export MS_CONF="$BATS_TEST_TMPDIR/cap.conf"
  cat >"$MS_CONF" <<'FIN'
MS_HV_NOEUDS=(hv01.par1.medisphere.internal hv02.par1.medisphere.internal)
MS_CAP_RESERVE_HOTE_MIO=1536
MS_CAP_RESERVE_CEPH_MIO=3072
MS_CAP_RESERVE_ZFS_MIO=1024
MS_CAP_MARGE_PCT=10
MS_CAP_POOLS_BALLON=(recette)
FIN
  # Trois nœuds de 12 Gio : capacité 5990 Mio chacun ((12288 − 5632) × 0,9), N+1 = 11980 Mio.
  G=1073741824
  M=1048576
  VMS='[{"vmid":120,"node":"hv01","type":"qemu","template":0,"pool":"prod","maxmem":2147483648},
        {"vmid":123,"node":"hv02","type":"qemu","template":0,"pool":"recette","maxmem":2147483648},
        {"vmid":199,"node":"hv01","type":"qemu","template":1,"pool":"recette","maxmem":2147483648}]'
  BALLON=1024
  API_MORTE=0
  pve_api() {
    ((API_MORTE)) && return 1
    case "$2 ${3:-}" in
      "/cluster/resources type=node")
        printf '[{"node":"hv01","maxmem":%s},{"node":"hv02","maxmem":%s},{"node":"hv03","maxmem":%s}]\n' $((12 * G)) $((12 * G)) $((12 * G)) ;;
      "/cluster/resources type=vm") echo "$VMS" ;;
      /nodes/*/qemu/*/config*) printf '{"memory":"2048","balloon":%s}\n' "$BALLON" ;;
      *) return 1 ;;
    esac
  }
}

@test "rapport : 2048 (prod) + 1024 (plancher de ballon en recette), template ignoré" {
  run main
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Capacité N+1 : 11980 Mio"* ]]
  [[ "$output" == *"mémoire engagée : 3072 Mio"* ]]
}

@test "sans plancher de ballon, la VM de recette compte pour toute sa mémoire" {
  BALLON=0
  run main
  [[ "$output" == *"mémoire engagée : 4096 Mio"* ]]
}

@test "demande qui entre → 0 ; demande trop grosse → 1" {
  run main --demande 1x512
  [[ "$status" -eq 0 ]]
  [[ "$output" == OUI* || "$output" == *"OUI :"* ]]
  run main --demande 20x2048
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"NON :"* ]]
}

@test "dépassement déjà présent → 1 sans demande" {
  VMS='[{"vmid":120,"node":"hv01","type":"qemu","template":0,"pool":"prod","maxmem":13958643712}]'
  run main
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"DÉPASSEMENT"* ]]
}

@test "API injoignable : contrôle impossible (1), jamais un « oui »" {
  API_MORTE=1
  run main --demande 1x512
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"contrôle impossible"* ]]
}

@test "usage : demande mal formée ou option inconnue → 2" {
  run main --demande vingt
  [[ "$status" -eq 2 ]]
  run main --demande 0x2048
  [[ "$status" -eq 2 ]]
  run main --nimporte-quoi
  [[ "$status" -eq 2 ]]
}
