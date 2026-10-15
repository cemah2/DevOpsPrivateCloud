# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M16-E39 « Panne : la sauvegarde Velero échoue »
#
# Après l'injection, la panne lance une sauvegarde Velero de wb-essais (Backup temoin-AAAAMMJJ-HHMM,
# volumes par Kopia, TTL 24 h), qui échoue. Côté s3-01, rien n'est touché. Variantes :
#   1. identifiants S3 : la clé secrète (aws_secret_access_key) du fichier d'identifiants de Velero
#      est remplacée (« rotation » faite d'un seul côté) ;
#   2. compartiment : l'emplacement de sauvegarde vise « velero-k8s-par01 » au lieu de
#      « velero-k8s-par1 » ;
#   3. CA : le caCert de l'emplacement est remplacé par celui d'une autre autorité ;
#   4. node-agent absent d'un nœud : le DaemonSet node-agent reçoit une affinité qui exclut le
#      travailleur du témoin temoin-rbd → la sauvegarde de son volume échoue.
# Sauvegardes : Secret, BackupStorageLocation, DaemonSet (wb_k8s_sauver, fichiers 600). La sauvegarde
# de test reste (TTL 24 h, supprimée ensuite par Velero lui-même).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m16-commun.sh
source "$WB_ROOT/modules/16-kubernetes-stockage/corrige/pannes/_m16-commun.sh"

_E39_FAUX_BUCKET=velero-k8s-par01

# _e39_secret — « nom clé » du Secret d'identifiants : spec.credential de l'emplacement, sinon le
# Secret monté sur /credentials dans le Deployment velero (chart officiel : clé « cloud »).
_e39_secret() {
  local bsl="$1" c
  c="$(m16_k get backupstoragelocations.velero.io "$bsl" -n velero -o json | jq -r '.spec.credential | select(. != null) | "\(.name) \(.key)"')"
  if [[ -z "$c" ]]; then
    c="$(m16_k get deployment velero -n velero -o json | jq -r '
      (.spec.template.spec.containers[] | select(.name == "velero") | .volumeMounts[]? | select(.mountPath == "/credentials") | .name) as $v
      | .spec.template.spec.volumes[] | select(.name == $v) | .secret.secretName // empty' | head -n1)"
    [[ -n "$c" ]] && c="$c cloud"
  fi
  printf '%s\n' "$c"
}

_e39_sans_agent() {
  [[ -z "$(m16_k get pods -n velero -l name=node-agent --field-selector "spec.nodeName=$1" -o name)" ]]
}

_e39_indisponible() { [[ "$(m16_bsl_phase "$1")" == Unavailable ]]; }

_m16E39_une() {
  local n="$1" bsl s k contenu neuf ca x
  bsl="$(m16_lire E39 bsl)"
  case "$n" in
    1)
      read -r s k <<<"$(_e39_secret "$bsl")"
      [[ -n "${s:-}" && -n "${k:-}" ]] || return 10
      contenu="$(m16_k get secret "$s" -n velero -o json | jq -r --arg k "$k" '.data[$k] // empty' | base64 -d 2>/dev/null)"
      grep -q '^aws_secret_access_key' <<<"$contenu" || return 10
      m16_sauver secret "$s" velero
      neuf="$(sed -E "s|^(aws_secret_access_key[[:space:]]*=[[:space:]]*).*|\1$(head -c 30 /dev/urandom | base64 -w0 | tr -dc 'A-Za-z0-9' | head -c 40)|" <<<"$contenu")"
      wb_kubectl patch secret "$s" -n velero --type merge \
        -p "$(jq -cn --arg k "$k" --arg v "$neuf" '{stringData: {($k): $v}}')" >/dev/null 2>&1 || return 1
      m16_ecrire E39 secret "$s $k"
      m16_ecrire E39 empreinte "$(printf '%s' "$neuf" | sha256sum | cut -d' ' -f1)"
      # Velero relit le fichier monté (propagation par kubelet en une minute environ).
      m16_attendre 240 _e39_indisponible "$bsl" || { _e39_defaire 1; return 10; }
      ;;
    2)
      [[ "$(m16_k get backupstoragelocations.velero.io "$bsl" -n velero -o jsonpath='{.spec.objectStorage.bucket}')" == velero-k8s-par1 ]] || return 10
      m16_sauver backupstoragelocations.velero.io "$bsl" velero
      wb_kubectl patch backupstoragelocations.velero.io "$bsl" -n velero --type merge \
        -p "{\"spec\":{\"objectStorage\":{\"bucket\":\"$_E39_FAUX_BUCKET\"}}}" >/dev/null 2>&1 || return 1
      m16_attendre 180 _e39_indisponible "$bsl" || { _e39_defaire 2; return 10; }
      ;;
    3)
      [[ -n "$(m16_k get backupstoragelocations.velero.io "$bsl" -n velero -o jsonpath='{.spec.objectStorage.caCert}')" ]] || return 10
      ca="$(m16_ca_bidon | base64 -w0)"
      [[ -n "$ca" ]] || return 1
      m16_sauver backupstoragelocations.velero.io "$bsl" velero
      wb_kubectl patch backupstoragelocations.velero.io "$bsl" -n velero --type merge \
        -p "{\"spec\":{\"objectStorage\":{\"caCert\":\"$ca\"}}}" >/dev/null 2>&1 || return 1
      m16_ecrire E39 ca_posee "$(printf '%s' "$ca" | sha256sum | cut -d' ' -f1)"
      m16_attendre 180 _e39_indisponible "$bsl" || { _e39_defaire 3; return 10; }
      ;;
    4)
      x="$(m16_noeud_du_pod "$_M16_NS_T" app.kubernetes.io/name=temoin-rbd)"
      [[ -n "$x" ]] || return 10
      m16_existe daemonset node-agent velero || return 10
      m16_ecrire E39 noeud "$x"
      m16_sauver daemonset node-agent velero
      wb_kubectl patch daemonset node-agent -n velero --type json -p "$(jq -cn --arg x "$x" '[{op: "add",
          path: "/spec/template/spec/affinity",
          value: {nodeAffinity: {requiredDuringSchedulingIgnoredDuringExecution: {nodeSelectorTerms: [
            {matchExpressions: [{key: "kubernetes.io/hostname", operator: "NotIn", values: [$x]}]}]}}}}]')" >/dev/null 2>&1 || return 1
      m16_attendre 120 _e39_sans_agent "$x" || { _e39_defaire 4; return 1; }
      ;;
  esac
  m16_ecrire E39 posee "$n"
  m16_journal E39 "variante $n posée"
}

_e39_defaire() {
  local bsl s k x
  bsl="$(m16_lire E39 bsl)"
  case "$1" in
    1)
      read -r s k <<<"$(m16_lire E39 secret)"
      [[ -n "${s:-}" ]] || return 0
      if [[ "$(m16_k get secret "$s" -n velero -o json | jq -r --arg k "$k" '.data[$k] // empty' | base64 -d 2>/dev/null | sha256sum | cut -d' ' -f1)" \
        == "$(m16_lire E39 empreinte)" ]]; then
        m16_restaurer secret "$s" velero
      else
        rm -f -- "$(_m16_fichier secret "$s" velero)"
      fi ;;
    2)
      [[ -n "$bsl" ]] || return 0
      if [[ "$(m16_k get backupstoragelocations.velero.io "$bsl" -n velero -o jsonpath='{.spec.objectStorage.bucket}')" == "$_E39_FAUX_BUCKET" ]]; then
        m16_restaurer backupstoragelocations.velero.io "$bsl" velero
      else
        rm -f -- "$(_m16_fichier backupstoragelocations.velero.io "$bsl" velero)"
      fi ;;
    3)
      [[ -n "$bsl" ]] || return 0
      if [[ "$(m16_k get backupstoragelocations.velero.io "$bsl" -n velero -o jsonpath='{.spec.objectStorage.caCert}' | sha256sum | cut -d' ' -f1)" \
        == "$(m16_lire E39 ca_posee)" ]]; then
        m16_restaurer backupstoragelocations.velero.io "$bsl" velero
      else
        rm -f -- "$(_m16_fichier backupstoragelocations.velero.io "$bsl" velero)"
      fi ;;
    4)
      x="$(m16_lire E39 noeud)"
      [[ -n "$x" ]] || return 0
      if m16_k get daemonset node-agent -n velero -o json \
        | jq -e --arg x "$x" '[.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[]?.matchExpressions[]? | select(.operator == "NotIn" and (.values | index($x)))] | length > 0' >/dev/null 2>&1; then
        m16_restaurer daemonset node-agent velero
      else
        rm -f -- "$(_m16_fichier daemonset node-agent velero)"
      fi ;;
  esac
}

_e39_injecter() {
  local bsl
  m16_preparer || return 1
  bsl="$(m16_bsl)"
  [[ -n "$bsl" ]] || { wb_avert "aucun emplacement de sauvegarde Velero (M16-E16)"; return 1; }
  [[ "$(m16_bsl_phase "$bsl")" == Available ]] || { wb_avert "l'emplacement Velero $bsl n'est pas Available avant la panne"; return 1; }
  m16_ecrire E39 bsl "$bsl"
  m16_horodater E39
  m16_essayer E39 4 "$1" || return 1
  m16_ecrire E39 sauvegarde "temoin-$(date +%Y%m%d-%H%M)"
  m16_creer_sauvegarde "$(m16_lire E39 sauvegarde)" || true
}

panne_E39_v1() { _e39_injecter 1; }
panne_E39_v2() { _e39_injecter 2; }
panne_E39_v3() { _e39_injecter 3; }
panne_E39_v4() { _e39_injecter 4; }

verifier_E39() {
  local x
  case "$WB_VAR" in
    4) x="$(m16_lire E39 noeud)"
       _e39_sans_agent "$x" ;;
    *) _e39_indisponible "$(m16_lire E39 bsl)" ;;
  esac
}

annuler_E39() {
  case "${WB_VAR:-}" in
    1 | 2 | 3 | 4) _e39_defaire "$WB_VAR" ;;
    *) _e39_defaire 4; _e39_defaire 3; _e39_defaire 2; _e39_defaire 1 ;;
  esac
  m16_journal E39 "annulation"
  m16_effacer_etat E39
}

resume_E39() {
  echo "La sauvegarde Velero de wb-essais ($(m16_lire E39 sauvegarde)) n'aboutit pas."
}

symptome_E39() {
  wb_symptome "Ticket INC-4345 — De : Nadia Roussel" \
    "La sauvegarde Velero de contrôle de wb-essais lancée ce matin ($(m16_lire E39 sauvegarde)) n'a pas" \
    "abouti. Sans sauvegarde valide, je ne peux pas valider le changement de ce soir sur la recette." \
    "Lucas a « fait le ménage dans la configuration de Velero » hier. Remets les sauvegardes en état," \
    "relance une sauvegarde de wb-essais (volumes compris) et montre-moi qu'elle est complète." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 16 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 16 E39 4 "$@"; }
fi
