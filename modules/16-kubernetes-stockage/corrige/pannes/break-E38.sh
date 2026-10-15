# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M16-E38 « Panne : Ceph refuse de créer les volumes »
#
# Après l'injection, la panne demande un volume de test (PVC temoin-e38, 1 Gio, ceph-rbd, et un pod
# qui l'utilise, dans wb-essais) : le PVC reste Pending sur des erreurs de provisionnement.
# Côté ceph-par1, la panne ne touche QUE les objets du consommateur Kubernetes. Variantes :
#   1. droits cephx de client.k8s « réalignés sur la documentation » : pool=k8s-rbd remplacé par
#      pool=kubernetes dans les droits osd et mgr (les autres droits sont conservés) ;
#   2. quota du pool k8s-rbd fixé à son occupation actuelle (max_bytes) → POOL_FULL : plus aucune
#      création ni écriture dans le pool (les volumes existants attendent, sans perte) ;
#   3. clé de client.k8s renouvelée avec le type aes256k (« ceph auth rotate ») : les Secrets de
#      ceph-csi portent l'ancienne clé, et le client noyau 6.12 ne sait pas utiliser ce type.
# ⚠️ Variantes 1 et 3 : les volumes DÉJÀ montés gardent leur session, mais la perdent au
# renouvellement de leurs titres cephx (de l'ordre de l'heure) : au-delà du temps cible, annuler.
# Sauvegardes sur le nœud admin de ceph-par1 (root, 600) : /var/lib/workbook/M16-E38.* (droits
# d'origine, quota d'origine, trousseau d'origine pour la variante 3) ; empreinte de la clé posée.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m16-commun.sh
source "$WB_ROOT/modules/16-kubernetes-stockage/corrige/pannes/_m16-commun.sh"

_e38_temoin() {
  wb_kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: temoin-e38
  namespace: $_M16_NS_T
  labels: {app.kubernetes.io/name: temoin-e38}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: $_M16_SC_RBD
  resources: {requests: {storage: 1Gi}}
---
apiVersion: v1
kind: Pod
metadata:
  name: temoin-e38
  namespace: $_M16_NS_T
  labels: {app.kubernetes.io/name: temoin-e38}
spec:
  terminationGracePeriodSeconds: 5
  securityContext: {runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, fsGroup: 65534, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: app
      image: $_M16_IMAGE
      command: ["sh", "-c", "date > /donnees/demarrage && exec sleep 2147483647"]
      resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 32Mi}}
      securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
      volumeMounts: [{name: donnees, mountPath: /donnees}]
  volumes:
    - name: donnees
      persistentVolumeClaim: {claimName: temoin-e38}
EOF
}

_e38_supprimer_temoin() {
  wb_kubectl delete pod temoin-e38 -n "$_M16_NS_T" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
  wb_kubectl delete pvc temoin-e38 -n "$_M16_NS_T" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

_m16E38_une() {
  local n="$1" rc=0 h
  case "$n" in
    1)
      m16_ceph_exec I="$_M16_CEPH_ID" P="$_M16_POOL" >/dev/null 2>&1 <<'EOF' || rc=$?
j="$(ceph_ auth get "$I" -f json)" || exit 1
f="$WB_DIR/$WB_EX.caps.json"
[ -f "$f" ] || printf '%s' "$j" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[0]["caps"]))' > "$f"
chmod 600 "$f"
grep -q "pool=$P" "$f" || exit 10
args="$(python3 - "$f" "$P" <<'PY'
import json, shlex, sys
caps = json.load(open(sys.argv[1]))
p = sys.argv[2]
out = []
for k, v in caps.items():
    if k in ("osd", "mgr"):
        v = v.replace("pool=" + p, "pool=kubernetes")
    out += [k, v]
print(" ".join(shlex.quote(x) for x in out))
PY
)" || exit 1
ceph_sh "ceph --connect-timeout 20 auth caps $I $args" >/dev/null || exit 1
journal "droits de $I : pool=$P remplacé par pool=kubernetes (osd, mgr)"
EOF
      ((rc == 0)) || return "$rc"
      ;;
    2)
      m16_ceph_exec P="$_M16_POOL" >/dev/null 2>&1 <<'EOF' || rc=$?
q="$(ceph_ osd pool get-quota "$P" -f json)" || exit 1
f="$WB_DIR/$WB_EX.quota.json"
[ -f "$f" ] || printf '%s' "$q" > "$f"
u="$(ceph_ df detail -f json | python3 -c "import json,sys; d=json.load(sys.stdin); print([x for x in d['pools'] if x['name']=='$P'][0]['stats']['stored'])")" || exit 1
[ "${u:-0}" -gt 1048576 ] 2>/dev/null || exit 10
ceph_ osd pool set-quota "$P" max_bytes "$u" >/dev/null || exit 1
printf '%s\n' "$u" > "$WB_DIR/$WB_EX.quota.pose"
journal "quota max_bytes du pool $P fixé à $u (occupation actuelle)"
EOF
      ((rc == 0)) || return "$rc"
      m16_attendre 90 _e38_pool_plein || { _e38_defaire 2; return 10; }
      ;;
    3)
      m16_ceph_exec I="$_M16_CEPH_ID" >/dev/null 2>&1 <<'EOF' || rc=$?
f="$WB_DIR/$WB_EX.keyring"
if [ ! -f "$f" ]; then
  ( umask 077; ceph_sh "ceph --connect-timeout 20 auth get $I" > "$f" ) || { rm -f "$f"; exit 1; }
fi
grep -q 'key = ' "$f" || { rm -f "$f"; exit 1; }
# Commande de la procédure CVE-2025-30156 (Ceph 20.2.4) ; sans elle, variante impossible.
ceph_sh "ceph --connect-timeout 20 auth rotate --key-type=aes256k $I" >/dev/null 2>&1 || { rm -f "$f"; exit 10; }
journal "clé de $I renouvelée en type aes256k (trousseau d'origine : $f)"
EOF
      ((rc == 0)) || return "$rc"
      h="$(m16_hachage_cle)"
      [[ -n "$h" ]] || return 1
      m16_ecrire E38 cle_posee "$h"
      ;;
  esac
  m16_ecrire E38 posee "$n"
  m16_journal E38 "variante $n posée"
}

_e38_pool_plein() {
  m16_ceph health detail -f json 2>/dev/null | jq -e --arg p "$_M16_POOL" \
    '.checks.POOL_FULL.detail // [] | any(.message | contains($p))' >/dev/null 2>&1
}

_e38_defaire() {
  case "$1" in
    1)
      m16_ceph_exec I="$_M16_CEPH_ID" >/dev/null 2>&1 <<'EOF' || wb_avert "annulation : droits de client.k8s non rétablis"
f="$WB_DIR/$WB_EX.caps.json"
[ -f "$f" ] || exit 0
cur="$(ceph_ auth get "$I" -f json | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[0]["caps"]))')" || exit 1
# Seulement si les droits portent encore la marque de la panne.
if printf '%s' "$cur" | grep -q 'pool=kubernetes'; then
  args="$(python3 -c 'import json,shlex,sys; c=json.load(open(sys.argv[1])); print(" ".join(shlex.quote(x) for k,v in c.items() for x in (k,v)))' "$f")"
  ceph_sh "ceph --connect-timeout 20 auth caps $I $args" >/dev/null || exit 1
  journal "droits de $I rétablis"
fi
rm -f "$f"
EOF
      ;;
    2)
      m16_ceph_exec P="$_M16_POOL" >/dev/null 2>&1 <<'EOF' || wb_avert "annulation : quota du pool k8s-rbd non rétabli"
f="$WB_DIR/$WB_EX.quota.json"; fp="$WB_DIR/$WB_EX.quota.pose"
[ -f "$f" ] && [ -f "$fp" ] || exit 0
cur="$(ceph_ osd pool get-quota "$P" -f json | python3 -c 'import json,sys; print(json.load(sys.stdin)["quota_max_bytes"])')"
if [ "$cur" = "$(cat "$fp")" ]; then
  orig="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["quota_max_bytes"])' "$f")"
  ceph_ osd pool set-quota "$P" max_bytes "${orig:-0}" >/dev/null || exit 1
  journal "quota du pool $P rétabli ($orig)"
fi
rm -f "$f" "$fp"
EOF
      ;;
    3)
      local h a
      h="$(m16_lire E38 cle_posee)"
      [[ -n "$h" ]] || return 0
      a="$(m16_hachage_cle)"
      # Ceph injoignable : on ne sait pas si la clé posée est encore là ; on garde tout pour réessayer.
      if [[ -z "$a" ]]; then
        wb_avert "annulation : clé de $_M16_CEPH_ID illisible ; trousseau d'origine conservé sur $_M16_CEPH_ADMIN (/var/lib/workbook/M16-E38.keyring), relance lab/bin/break 16 38 --annuler"
        return 1
      fi
      if [[ "$a" == "$h" ]]; then
        m16_ceph_exec I="$_M16_CEPH_ID" >/dev/null 2>&1 <<'EOF' || wb_avert "annulation : trousseau d'origine de client.k8s non réimporté"
f="$WB_DIR/$WB_EX.keyring"
[ -f "$f" ] || exit 1
if command -v ceph >/dev/null 2>&1 && [ -r /etc/ceph/ceph.client.admin.keyring ]; then
  timeout 120 ceph --connect-timeout 20 auth import -i "$f" >/dev/null 2>&1 || exit 1
else
  timeout 180 cephadm shell --mount "$f:/tmp/m16-e38.keyring" -- \
    ceph --connect-timeout 20 auth import -i /tmp/m16-e38.keyring >/dev/null 2>&1 </dev/null || exit 1
fi
journal "trousseau d'origine de $I réimporté"
EOF
        # Le trousseau d'origine n'est effacé qu'une fois la clé posée par la panne disparue de Ceph
        # (réimport réussi) : sinon il reste la seule copie de la valeur attendue par les volumes montés.
        if [[ "$(m16_hachage_cle)" == "$h" ]]; then
          wb_avert "annulation : la clé posée par la panne est toujours celle de $_M16_CEPH_ID ; trousseau d'origine conservé sur $_M16_CEPH_ADMIN (/var/lib/workbook/M16-E38.keyring), relance lab/bin/break 16 38 --annuler"
          return 1
        fi
      fi
      m16_ceph_exec >/dev/null 2>&1 <<'EOF' || true
rm -f "$WB_DIR/$WB_EX.keyring"
EOF
      ;;
  esac
}

_e38_injecter() {
  # Une annulation précédente de la variante 3 a échoué (clé non remise) : on ne repose rien ; le
  # retour d'échec fait relancer l'annulation par lab/bin/break, qui réessaie de remettre la clé.
  if [[ -n "$(m16_lire E38 cle_posee)" ]]; then
    wb_avert "la clé de $_M16_CEPH_ID posée par une injection précédente n'a pas été remise : nouvelle tentative d'annulation"
    return 1
  fi
  m16_preparer || return 1
  m16_ceph status -f json 2>/dev/null | jq -e '.health.status != "HEALTH_ERR"' >/dev/null 2>&1 \
    || { wb_avert "ceph-par1 ne répond pas ou est en HEALTH_ERR depuis $_M16_CEPH_ADMIN"; return 1; }
  m16_existe pvc temoin-e38 "$_M16_NS_T" && _e38_supprimer_temoin
  m16_horodater E38
  m16_essayer E38 3 "$1" || return 1
  _e38_temoin
}

panne_E38_v1() { _e38_injecter 1; }
panne_E38_v2() { _e38_injecter 2; }
panne_E38_v3() { _e38_injecter 3; }

verifier_E38() {
  sleep 60
  [[ "$(m16_k get pvc temoin-e38 -n "$_M16_NS_T" -o jsonpath='{.status.phase}')" == Pending ]]
}

annuler_E38() {
  local ok=0
  case "${WB_VAR:-}" in
    1 | 2) _e38_defaire "$WB_VAR" ;;
    3) _e38_defaire 3 || ok=1 ;;
    *) _e38_defaire 3 || ok=1; _e38_defaire 2; _e38_defaire 1 ;;
  esac
  _e38_supprimer_temoin
  # État local gardé si la clé n'a pas pu être remise : un nouvel --annuler réessaiera.
  if ((ok == 0)); then
    m16_journal E38 "annulation"
    m16_effacer_etat E38
  else
    m16_journal E38 "annulation incomplète (clé de client.k8s), état conservé"
  fi
}

resume_E38() {
  echo "Plus aucun nouveau volume ceph-rbd ne se crée (PVC de test temoin-e38 Pending dans wb-essais)."
}

symptome_E38() {
  wb_symptome "Ticket INC-4344 — De : Karim Benali" \
    "Depuis la maintenance de Lucas sur ceph-par1 cette nuit, aucun nouveau volume ceph-rbd ne se" \
    "crée : mon PVC de test temoin-e38 (wb-essais) reste Pending, et les événements parlent d'erreurs" \
    "de provisionnement. Lucas jure n'avoir touché « qu'aux réglages de Kubernetes côté Ceph »." \
    "Rétablis la création des volumes, et vérifie que les volumes déjà montés ne sont pas menacés." \
    "" \
    "Temps cible : 45 min (au-delà de 1 h, annule : lab/bin/break 16 38 --annuler)." \
    "Contrôle : lab/bin/check 16 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 16 E38 3 "$@"; }
fi
