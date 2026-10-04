# shellcheck shell=bash
# fake-pve.bash — faux Proxmox en mémoire pour les tests bats de ms-snapshot (M02-E27).
# Aucun accès réseau : remplace pve_api (même signature que lib/ms-commun.sh :
# MÉTHODE /CHEMIN [clé=valeur...]). pve_wait_task (de la bibliothèque) l'utilise aussi.
#
# État dans $FAKE_PVE (répertoire temporaire du test) :
#   ressources.json    réponse de GET /cluster/resources
#   snap-<VMID>        un instantané par ligne : « nom<TAB>snaptime »
#   lock-<VMID>        s'il existe, son contenu est le verrou de la VM (ex. « snapshot »)
#   echec-creation     s'il existe, la tâche de création se termine en erreur
#   ecritures.log      une ligne par requête d'écriture reçue (POST, PUT, DELETE)

fake_pve_init() {
  FAKE_PVE="$BATS_TEST_TMPDIR/pve"
  mkdir -p "$FAKE_PVE"
  : >"$FAKE_PVE/ecritures.log"
  export MS_LOCK_DIR="$BATS_TEST_TMPDIR/verrous" MS_PVE_POLL=0
}

# fake_vm VMID [POOL] [TEMPLATE] — déclare une VM QEMU dans l'inventaire
fake_vm() {
  local f="$FAKE_PVE/ressources.json"
  [[ -s "$f" ]] || echo '[]' >"$f"
  jq --argjson id "$1" --arg pool "${2:-lab}" --argjson t "${3:-0}" \
    '. + [{vmid: $id, node: "pve01", type: "qemu", pool: $pool, template: $t, name: "vm\($id)"}]' \
    "$f" >"$f.tmp" && mv "$f.tmp" "$f"
  touch "$FAKE_PVE/snap-$1"
}

# fake_snap VMID NOM [SNAPTIME] — ajoute un instantané. Sans SNAPTIME : déduit du nom
# (…-AAAAMMJJ-HHMMSS), sinon il y a deux jours.
fake_snap() {
  local t="${3:-}"
  if [[ -z "$t" && "$2" =~ -([0-9]{8})-([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
    t="$(date -d "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}" +%s)"
  fi
  printf '%s\t%s\n' "$2" "${t:-$(($(date +%s) - 172800))}" >>"$FAKE_PVE/snap-$1"
}

# fake_noms VMID — noms des instantanés de la VM, triés
fake_noms() { cut -f1 "$FAKE_PVE/snap-$1" | sort; }

pve_api() {
  local methode="$1" chemin="$2" donnees="${3:-}" vmid nom
  if [[ "$methode" != GET ]]; then
    echo "$methode $chemin $donnees" >>"$FAKE_PVE/ecritures.log"
  fi
  case "$methode $chemin" in
    "GET /cluster/resources"*)
      cat "$FAKE_PVE/ressources.json"
      ;;
    "GET /nodes/"*"/tasks/"*"/status")
      if [[ "$chemin" == *ECHEC* ]]; then
        echo '{"status":"stopped","exitstatus":"snapshot feature is not available"}'
      else
        echo '{"status":"stopped","exitstatus":"OK"}'
      fi
      ;;
    "GET /nodes/"*"/qemu/"*"/config")
      vmid="$(cut -d/ -f5 <<<"$chemin")"
      if [[ -f "$FAKE_PVE/lock-$vmid" ]]; then
        jq -cn --arg l "$(<"$FAKE_PVE/lock-$vmid")" '{lock: $l, name: "x"}'
      else
        echo '{"name":"x"}'
      fi
      ;;
    "GET /nodes/"*"/qemu/"*"/snapshot")
      vmid="$(cut -d/ -f5 <<<"$chemin")"
      jq -cRn '[inputs | split("\t") | {name: .[0], snaptime: (.[1] | tonumber)}]
               + [{name: "current", description: "You are here!"}]' "$FAKE_PVE/snap-$vmid"
      ;;
    "POST /nodes/"*"/qemu/"*"/snapshot")
      vmid="$(cut -d/ -f5 <<<"$chemin")"
      nom="${donnees#snapname=}"
      if [[ -f "$FAKE_PVE/echec-creation" ]]; then
        echo "\"UPID:pve01:000ECHEC:00000000:00000000:qmsnapshot:$vmid:test@pve!t:\""
        return 0
      fi
      if cut -f1 "$FAKE_PVE/snap-$vmid" | grep -qx -- "$nom"; then
        echo "snapshot name '$nom' already used" >&2
        return 1
      fi
      printf '%s\t%s\n' "$nom" "$(date +%s)" >>"$FAKE_PVE/snap-$vmid"
      echo "\"UPID:pve01:00000001:00000000:00000000:qmsnapshot:$vmid:test@pve!t:\""
      ;;
    "DELETE /nodes/"*"/qemu/"*"/snapshot/"*)
      vmid="$(cut -d/ -f5 <<<"$chemin")"
      nom="${chemin##*/}"
      awk -F'\t' -v n="$nom" '$1 != n' "$FAKE_PVE/snap-$vmid" >"$FAKE_PVE/snap-$vmid.tmp"
      mv "$FAKE_PVE/snap-$vmid.tmp" "$FAKE_PVE/snap-$vmid"
      echo "\"UPID:pve01:00000002:00000000:00000000:qmdelsnapshot:$vmid:test@pve!t:\""
      ;;
    *)
      echo "fake-pve : requête non prévue : $methode $chemin" >&2
      return 1
      ;;
  esac
}
