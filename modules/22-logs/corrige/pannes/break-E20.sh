# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions yq et jq entre apostrophes
# break-E20.sh — M22-E20 « Panne : Loki refuse les écritures »
#
# Variantes :
#   1. commit de Lucas (loki/values.yaml) : surcharge du locataire mediagenda ingestion_rate_mb 0.0001 et
#      ingestion_burst_size_mb 0.0002 (« 100 Mo par jour, converti ») : 104 octets/s, rafale de 209 octets,
#      donc presque chaque lot d'Alloy est refusé (429 « ingestion rate limit exceeded »). Sans effet si
#      MédiAgenda ne journalise rien ;
#   2. Secret loki-objstore « mis à jour après une rotation » avec une clé secrète périmée, puis loki-0
#      redémarré : le RGW refuse (SignatureDoesNotMatch / InvalidAccessKeyId), les vidages de chunks et
#      les lectures du stockage échouent (5xx). Sans effet si aucune clé de nom « *secret* » dans le Secret ;
#   3. commit de Lucas : max_global_streams_per_user du locataire plateforme ramené sous le nombre de flux
#      actifs, puis déploiement témoin « journal-temoin » dans wb-pannes (nouveau flux) : 429 « maximum
#      active stream limit exceeded » pour tout NOUVEAU flux de la plateforme.
# Jamais de rétention raccourcie, aucune donnée supprimée (l'ingester garde les chunks non vidés dans
# son WAL et réessaie). Le Secret d'origine est sauvegardé (600) dans ~/.local/state/workbook/k8s/M22-E20/.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m22-commun.sh
source "$WB_ROOT/modules/22-logs/corrige/pannes/_m22-commun.sh"

_E20_ANNOT=medisphere.internal/rotation
_E20_ANNOT_VAL="2026-10-lucas"

# _e20_empreinte CLÉ — empreinte de la valeur (encodée) d'une clé du Secret loki-objstore, jamais la valeur.
_e20_empreinte() {
  wb_kubectl -n "$_M22_NS" get secret loki-objstore -o json 2>/dev/null | jq -r --arg k "$1" '.data[$k] // ""' | sha256sum | cut -d' ' -f1
}

_e20_rejets() { m22_metrique "^loki_discarded_samples_total\\{.*reason=\"$1\".*tenant=\"$2\""; }

# Les rejets d'une raison et d'un locataire ont augmenté depuis l'injection.
_e20_rejets_en_hausse() {
  local avant
  avant="$(m22_lire E20 "rejets-$1-$2")"
  (($(_e20_rejets "$1" "$2") > ${avant:-0}))
}

# Variante 3 : le ConfigMap loki-runtime porte la limite injectée.
_e20_limite_chargee() {
  m22_runtime | L="$(m22_lire E20 limite)" yq -e '.overrides.plateforme.max_global_streams_per_user == env(L)' >/dev/null 2>&1
}

_e20_v1_effective() { _e20_rejets_en_hausse rate_limited mediagenda; }
_e20_v3_effective() { _e20_rejets_en_hausse stream_limit plateforme; }

# Variante 2 : erreurs d'accès au RGW dans le journal de loki-0 depuis le redémarrage, ou /ready KO.
_e20_v2_effective() {
  m22_loki_pret || return 0
  wb_kubectl -n "$_M22_NS" logs loki-0 -c loki --since=10m 2>/dev/null |
    grep -Eq 'SignatureDoesNotMatch|InvalidAccessKeyId|AccessDenied|403 Forbidden|status code: 403'
}

_e20_temoin() {
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: journal-temoin
  namespace: $_M22_PANNES
  labels: {app.kubernetes.io/name: journal-temoin, medisphere.internal/ticket: PLAT-2320}
spec:
  replicas: 1
  selector: {matchLabels: {app.kubernetes.io/name: journal-temoin}}
  template:
    metadata: {labels: {app.kubernetes.io/name: journal-temoin}}
    spec:
      securityContext: {runAsNonRoot: true, runAsUser: 65534, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: temoin
          image: $_M22_REGISTRE/dockerhub/library/busybox:1.37
          command: ["/bin/sh", "-c", "while true; do echo \"journal-temoin \$(date -Iseconds) tout va bien\"; sleep 5; done"]
          resources: {requests: {cpu: 5m, memory: 8Mi}, limits: {cpu: 20m, memory: 16Mi}}
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
EOF
}

_m22E20_une() {
  local n="$1" rc=0 actifs limite s cle
  case "$n" in
    1)
      m22_poser E20 rejets-rate_limited-mediagenda "$(_e20_rejets rate_limited mediagenda)"
      # MédiAgenda doit journaliser un peu, sinon la limite ne mord sur rien.
      if (($(m22_nb_lignes mediagenda '{namespace=~"mediagenda-.+"}' 5m) < 5)); then return 10; fi
      _m22_transformer() {
        local f
        f="$(mktemp)"
        cat >"$f"
        yq -e '.loki.runtimeConfig.overrides' "$f" >/dev/null 2>&1 || { rm -f "$f"; return 10; }
        yq '.loki.runtimeConfig.overrides.mediagenda.ingestion_rate_mb = 0.0001 | .loki.runtimeConfig.overrides.mediagenda.ingestion_burst_size_mb = 0.0002' "$f"
        rm -f "$f"
      }
      m22_git_modifier E20 "$_M22_F_LOKI" "chore(loki): plafond d'ingestion de MédiAgenda (M22-E20)

Julien voulait plafonner MédiAgenda à 100 Mo par jour : 0.0001, j'ai converti. -- Lucas" || return $?
      m22_attendre 420 _e20_v1_effective || return 10
      ;;
    2)
      s="$(wb_kubectl -n "$_M22_NS" get secret loki-objstore -o json 2>/dev/null)" || return 10
      cle="$(jq -r '[.data | keys[] | select(test("secret"; "i"))][0] // empty' <<<"$s")"
      [[ -n "$cle" ]] || return 10
      m22_poser E20 cle "$cle"
      wb_k8s_sauver secret loki-objstore "$_M22_NS" || true
      chmod 700 "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/$WB_EX" 2>/dev/null || true
      chmod 600 "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/$WB_EX"/*.yaml 2>/dev/null || true
      [[ -s "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/$WB_EX/${_M22_NS}_secret_loki-objstore.yaml" ]] || return 1
      # Clé « périmée » : la vraie, dont les quatre derniers caractères sont permutés.
      jq --arg k "$cle" --arg a "$_E20_ANNOT" --arg v "$_E20_ANNOT_VAL" '
        (.data[$k] | @base64d) as $s
        | .data[$k] = (($s[0:-4] + ($s[-4:] | explode | reverse | implode)) | @base64)
        | .metadata.annotations[$a] = $v
        | del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.managedFields)' <<<"$s" |
        wb_kubectl replace -f - >/dev/null || return 1
      m22_poser E20 empreinte-secret "$(_e20_empreinte "$cle")"
      m22_journal E20 "clé $cle de loki-objstore remplacée, loki-0 redémarré"
      wb_kubectl -n "$_M22_NS" delete pod loki-0 --wait=false >/dev/null || return 1
      sleep 60
      m22_attendre 240 _e20_v2_effective || return 10
      ;;
    3)
      m22_poser E20 rejets-stream_limit-plateforme "$(_e20_rejets stream_limit plateforme)"
      _e20_temoin | wb_kubectl apply --dry-run=server -f - >/dev/null 2>&1 || return 10
      actifs="$(m22_metrique '^loki_ingester_memory_streams\{.*tenant="plateforme"')"
      ((actifs > 20)) || return 10
      limite=$((actifs * 8 / 10))
      _m22_transformer() {
        local f
        f="$(mktemp)"
        cat >"$f"
        yq -e '.loki.runtimeConfig.overrides' "$f" >/dev/null 2>&1 || { rm -f "$f"; return 10; }
        L="$limite" yq '.loki.runtimeConfig.overrides.plateforme.max_global_streams_per_user = env(L)' "$f"
        rm -f "$f"
      }
      m22_git_modifier E20 "$_M22_F_LOKI" "chore(loki): limite de flux de la plateforme au plus juste (M22-E20)

On a $actifs flux, inutile d'en autoriser 10 000. -- Lucas" || return $?
      # Attendre que la surcharge soit rechargée (le ConfigMap porte la nouvelle limite), puis un nouveau flux.
      m22_poser E20 limite "$limite"
      m22_attendre 420 _e20_limite_chargee || return 1
      sleep 30
      _e20_temoin | wb_kubectl apply -f - >/dev/null || return 1
      m22_journal E20 "déploiement journal-temoin créé dans $_M22_PANNES"
      m22_attendre 240 _e20_v3_effective || return 10
      ;;
  esac
  m22_journal E20 "variante $n posée"
}

_e20_defaire() {
  local n="$1" cle emp
  case "$n" in
    1 | 3)
      m22_git_annuler E20 || true
      [[ "$n" == 3 ]] && wb_kubectl -n "$_M22_PANNES" delete deployment journal-temoin --ignore-not-found >/dev/null 2>&1 || true
      ;;
    2)
      cle="$(m22_lire E20 cle)"
      emp="$(m22_lire E20 empreinte-secret)"
      if [[ -n "$cle" && -n "$emp" ]] &&
        [[ "$(_e20_empreinte "$cle")" == "$emp" ]]; then
        wb_k8s_restaurer || wb_avert "Secret loki-objstore non restauré (copie dans ~/.local/state/workbook/k8s/$WB_EX/)"
        wb_kubectl -n "$_M22_NS" delete pod loki-0 --wait=false >/dev/null 2>&1 || true
        m22_journal E20 "annulation : Secret loki-objstore restauré, loki-0 redémarré"
      else
        rm -rf -- "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/$WB_EX" 2>/dev/null || true
      fi
      m22_oublier E20 cle
      m22_oublier E20 empreinte-secret
      ;;
  esac
}

panne_E20_v1() { m22_preparer && m22_essayer E20 3 1; }
panne_E20_v2() { m22_preparer && m22_essayer E20 3 2; }
panne_E20_v3() { m22_preparer && m22_essayer E20 3 3; }

verifier_E20() {
  case "$WB_VAR" in
    1) _e20_v1_effective ;;
    2) _e20_v2_effective ;;
    3) _e20_v3_effective ;;
    *) return 1 ;;
  esac
}

annuler_E20() {
  case "${WB_VAR:-}" in
    [1-3]) _e20_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3; do _e20_defaire "$v"; done ;;
  esac
  m22_oublier E20 rejets-rate_limited-mediagenda
  m22_oublier E20 rejets-stream_limit-plateforme
  m22_oublier E20 limite
  m22_journal E20 "annulation"
}

resume_E20() {
  case "${WB_VAR:-}" in
    2) echo "Loki renvoie des erreurs 500 sur les journaux de plus de quelques heures et se plaint de son stockage." ;;
    3) echo "Les journaux des nouveaux déploiements de la plateforme (dont journal-temoin, wb-pannes) n'arrivent pas dans Loki." ;;
    *) echo "Les journaux de MédiAgenda n'arrivent presque plus dans Loki ; Alloy signale des refus de Loki." ;;
  esac
}

symptome_E20() {
  case "${WB_VAR:-}" in
    2)
      wb_symptome "Ticket INC-4920 — De : Nadia Roussel" \
        "Depuis le redémarrage de Loki ce matin, Grafana renvoie des erreurs 500 dès que je" \
        "remonte à hier, et le pod loki-0 écrit des erreurs de stockage en continu. Lucas a fait" \
        "la rotation trimestrielle des identifiants du RGW hier soir, « tout s'est bien passé »." \
        "Rétablis Loki sans perdre les journaux reçus depuis ce matin." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 22 20"
      ;;
    3)
      wb_symptome "Ticket INC-4920 — De : Karim Benali" \
        "J'ai déployé un petit témoin dans wb-pannes (journal-temoin, une ligne toutes les 5 s) :" \
        "kubectl logs montre ses lignes, Loki n'en a aucune. Les journaux des pods qui tournent" \
        "depuis longtemps, eux, arrivent. Alloy se plaint de refus de Loki." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 22 20"
      ;;
    *)
      wb_symptome "Ticket INC-4920 — De : Julien Petit" \
        "Les journaux de MédiAgenda n'arrivent presque plus dans Grafana depuis ce matin :" \
        "kubectl logs les montre, Loki n'en garde qu'une poignée. Les autres équipes ne voient" \
        "rien d'anormal. Je n'ai rien changé côté application." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 22 20"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 22 E20 3 "$@"; }
fi
