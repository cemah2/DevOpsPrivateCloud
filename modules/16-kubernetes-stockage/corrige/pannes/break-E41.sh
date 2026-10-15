# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M16-E41 « Panne : l'archivage des WAL est bloqué »
#
# Cible : l'ObjectStore cnpg-s3 (plugin Barman Cloud) utilisé par mediagenda-db (mediagenda-recette)
# comme archiveur de WAL. Côté s3-01, rien n'est touché. Variantes :
#   1. identifiants du plugin : la clé secrète du Secret désigné par
#      .spec.configuration.s3Credentials.secretAccessKey est remplacée ;
#   2. compartiment : .spec.configuration.destinationPath vise « cnpg-k8s-par1-wal » au lieu de
#      « cnpg-k8s-par1 » (le compte cnpg n'a aucun droit sur ce nom) ;
#   3. CA : .spec.configuration.endpointCA pointe vers un nouveau Secret « cnpg-s3-ca-2026 » qui
#      contient le certificat d'une autre autorité (« renouvellement de la CA » mal fait).
# Après injection, la panne force un changement de segment WAL (pg_switch_wal) pour que l'échec
# soit immédiat. Sauvegardes : ObjectStore et Secret (wb_k8s_sauver, 600). Aucun WAL n'est perdu :
# PostgreSQL garde les segments non archivés dans pg_wal tant que l'archivage échoue.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m16-commun.sh
source "$WB_ROOT/modules/16-kubernetes-stockage/corrige/pannes/_m16-commun.sh"

_E41_OS=cnpg-s3
_E41_CA_SECRET=cnpg-s3-ca-2026

_e41_os() { m16_json objectstores.barmancloud.cnpg.io "$_E41_OS" "$_M16_NS_DB"; }

# _e41_echec — le dernier échec d'archivage est plus récent que le dernier succès.
_e41_echec() {
  m16_psql "select coalesce(last_failed_time > coalesce(last_archived_time, 'epoch'::timestamptz), false) from pg_stat_archiver" \
    | grep -qx t
}

_e41_basculer_wal() {
  m16_psql "select txid_current(); select pg_switch_wal();" >/dev/null 2>&1 || true
}

_m16E41_une() {
  local n="$1" j s k faux ca dp
  j="$(_e41_os)"
  [[ -n "$j" ]] || return 1
  case "$n" in
    1)
      s="$(jq -r '.spec.configuration.s3Credentials.secretAccessKey.name // empty' <<<"$j")"
      k="$(jq -r '.spec.configuration.s3Credentials.secretAccessKey.key // empty' <<<"$j")"
      [[ -n "$s" && -n "$k" ]] || return 10
      m16_sauver secret "$s" "$_M16_NS_DB"
      faux="$(head -c 30 /dev/urandom | base64 -w0 | tr -dc 'A-Za-z0-9' | head -c 40)"
      wb_kubectl patch secret "$s" -n "$_M16_NS_DB" --type merge \
        -p "$(jq -cn --arg k "$k" --arg v "$faux" '{stringData: {($k): $v}}')" >/dev/null 2>&1 || return 1
      m16_ecrire E41 secret "$s $k"
      m16_ecrire E41 empreinte "$(printf '%s' "$faux" | sha256sum | cut -d' ' -f1)"
      ;;
    2)
      dp="$(jq -r '.spec.configuration.destinationPath // empty' <<<"$j")"
      [[ "$dp" == s3://cnpg-k8s-par1/* || "$dp" == s3://cnpg-k8s-par1 ]] || return 10
      m16_sauver objectstores.barmancloud.cnpg.io "$_E41_OS" "$_M16_NS_DB"
      dp="${dp/s3:\/\/cnpg-k8s-par1/s3://cnpg-k8s-par1-wal}"
      wb_kubectl patch objectstores.barmancloud.cnpg.io "$_E41_OS" -n "$_M16_NS_DB" --type merge \
        -p "$(jq -cn --arg d "$dp" '{spec: {configuration: {destinationPath: $d}}}')" >/dev/null 2>&1 || return 1
      m16_ecrire E41 chemin "$dp"
      ;;
    3)
      [[ -n "$(jq -r '.spec.configuration.endpointCA.name // empty' <<<"$j")" ]] || return 10
      m16_existe secret "$_E41_CA_SECRET" "$_M16_NS_DB" && return 10
      ca="$(m16_ca_bidon)"
      [[ -n "$ca" ]] || return 1
      m16_sauver objectstores.barmancloud.cnpg.io "$_E41_OS" "$_M16_NS_DB"
      m16_sauver secret "$_E41_CA_SECRET" "$_M16_NS_DB"
      wb_kubectl create secret generic "$_E41_CA_SECRET" -n "$_M16_NS_DB" --from-literal=ca.crt="$ca" >/dev/null 2>&1 || return 1
      wb_kubectl patch objectstores.barmancloud.cnpg.io "$_E41_OS" -n "$_M16_NS_DB" --type merge \
        -p "{\"spec\":{\"configuration\":{\"endpointCA\":{\"name\":\"$_E41_CA_SECRET\",\"key\":\"ca.crt\"}}}}" >/dev/null 2>&1 \
        || { _e41_defaire 3; return 1; }
      ;;
  esac
  m16_ecrire E41 posee "$n"
  sleep 20
  _e41_basculer_wal
  m16_attendre 150 _e41_echec || { _e41_defaire "$n"; return 10; }
  m16_journal E41 "variante $n posée"
}

_e41_defaire() {
  local s k
  case "$1" in
    1)
      read -r s k <<<"$(m16_lire E41 secret)"
      [[ -n "${s:-}" ]] || return 0
      if [[ "$(m16_k get secret "$s" -n "$_M16_NS_DB" -o json | jq -r --arg k "$k" '.data[$k] // empty' | base64 -d 2>/dev/null | sha256sum | cut -d' ' -f1)" \
        == "$(m16_lire E41 empreinte)" ]]; then
        m16_restaurer secret "$s" "$_M16_NS_DB"
      else
        rm -f -- "$(_m16_fichier secret "$s" "$_M16_NS_DB")"
      fi ;;
    2)
      [[ -n "$(m16_lire E41 chemin)" ]] || return 0
      if [[ "$(_e41_os | jq -r '.spec.configuration.destinationPath // empty')" == "$(m16_lire E41 chemin)" ]]; then
        m16_restaurer objectstores.barmancloud.cnpg.io "$_E41_OS" "$_M16_NS_DB"
      else
        rm -f -- "$(_m16_fichier objectstores.barmancloud.cnpg.io "$_E41_OS" "$_M16_NS_DB")"
      fi ;;
    3)
      if [[ "$(_e41_os | jq -r '.spec.configuration.endpointCA.name // empty')" == "$_E41_CA_SECRET" ]]; then
        m16_restaurer objectstores.barmancloud.cnpg.io "$_E41_OS" "$_M16_NS_DB"
      else
        rm -f -- "$(_m16_fichier objectstores.barmancloud.cnpg.io "$_E41_OS" "$_M16_NS_DB")"
      fi
      # Le Secret créé par la panne disparaît dans tous les cas (ABSENT avant la panne).
      m16_restaurer secret "$_E41_CA_SECRET" "$_M16_NS_DB" ;;
  esac
}

_e41_injecter() {
  if [[ -z "${_M16_ASTREINTE:-}" ]]; then
    m16_sain_csi || return 1
  fi
  m16_cnpg_sain || { wb_avert "$_M16_CLUSTER n'est pas sain : lab/bin/check 16 19"; return 1; }
  [[ -n "$(_e41_os)" ]] || { wb_avert "ObjectStore $_E41_OS absent de $_M16_NS_DB (M16-E19)"; return 1; }
  if [[ -z "${_M16_ASTREINTE:-}" ]] && _e41_echec; then
    wb_avert "l'archivage des WAL de $_M16_CLUSTER échoue déjà avant la panne : lab/bin/check 16 19"
    return 1
  fi
  m16_horodater E41
  m16_essayer E41 3 "$1"
}

panne_E41_v1() { _e41_injecter 1; }
panne_E41_v2() { _e41_injecter 2; }
panne_E41_v3() { _e41_injecter 3; }

verifier_E41() { _e41_echec; }

annuler_E41() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e41_defaire "$WB_VAR" ;;
    *) _e41_defaire 3; _e41_defaire 2; _e41_defaire 1 ;;
  esac
  _e41_basculer_wal
  m16_journal E41 "annulation"
  m16_effacer_etat E41
}

resume_E41() {
  echo "Les WAL de mediagenda-db ne partent plus vers s3-01 : la restauration à un instant donné n'est plus garantie."
}

symptome_E41() {
  wb_symptome "Ticket INC-4347 — De : Sophie Laurent" \
    "Contrôle HDS de ce matin : pour mediagenda-db (mediagenda-recette), le dernier WAL archivé date" \
    "de plus d'une heure alors que la base reçoit des écritures. Notre engagement de restauration à" \
    "un instant donné (RB-162, politique de sauvegarde) n'est plus tenu. Remets l'archivage en marche," \
    "prouve qu'aucun WAL n'a été perdu entre-temps et dis-moi jusqu'où on aurait pu restaurer pendant" \
    "la panne." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 16 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 16 E41 3 "$@"; }
fi
