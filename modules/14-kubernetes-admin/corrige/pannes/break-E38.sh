# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M14-E38 « Panne : CrashLoopBackOff »
#
# Cible : le déploiement témoin « agenda » (wb-pannes), modifié comme par une « nouvelle version ».
# Variantes :
#   1. variable obligatoire renommée (MEDIAGENDA_VALKEY_URL → MEDIAGENDA_CACHE_URL) : l'application
#      s'arrête aussitôt avec le code 2 et un message clair dans ses journaux ;
#   2. sonde de vivacité « harmonisée avec MédiDoc » (/healthz sur le port 8080) : le kubelet tue le
#      conteneur toutes les quelques secondes ;
#   3. limite de mémoire à 32 Mi : OOMKilled au démarrage ;
#   4. commande remplacée par un exécutable qui n'existe pas dans l'image (mediagenda-api).
# Les anciens pods restent en service (mise à jour progressive bloquée). Annulation : déploiement
# remis comme avant si la marque de la panne est encore présente.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m14-commun.sh
source "$WB_ROOT/modules/14-kubernetes-admin/corrige/pannes/_m14-commun.sh"

_e38_boucle() { m14_nouveau_pod_etat E38 agenda "$_M14_JQ_CRASH"; }

_m14E38_une() {
  local n="$1" i
  m14_debut E38
  m14_sauver_objet E38 deployment agenda "$_M14_NS"
  case "$n" in
    1)
      i="$(wb_kubectl -n "$_M14_NS" get deploy agenda -o json | jq -r '
        .spec.template.spec.containers[0].env // [] | to_entries[] | select(.value.name == "MEDIAGENDA_VALKEY_URL") | .key' | head -n 1)"
      [[ -n "$i" ]] || return 10
      wb_kubectl -n "$_M14_NS" patch deploy agenda --type json \
        -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/env/$i/name\",\"value\":\"MEDIAGENDA_CACHE_URL\"}]" >/dev/null || return 1
      ;;
    2)
      wb_kubectl -n "$_M14_NS" patch deploy agenda --type json -p '[
        {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe",
         "value":{"httpGet":{"path":"/healthz","port":8080},"periodSeconds":5,"timeoutSeconds":1,"failureThreshold":2}}]' >/dev/null || return 1
      ;;
    3)
      wb_kubectl -n "$_M14_NS" patch deploy agenda --type strategic -p \
        '{"spec":{"template":{"spec":{"containers":[{"name":"agenda","resources":{"requests":{"memory":"32Mi"},"limits":{"memory":"32Mi"}}}]}}}}' >/dev/null || return 1
      ;;
    4)
      wb_kubectl -n "$_M14_NS" patch deploy agenda --type strategic -p \
        '{"spec":{"template":{"spec":{"containers":[{"name":"agenda","command":["mediagenda-api"]}]}}}}' >/dev/null || return 1
      ;;
  esac
  m14_journal E38 "variante $n posée"
  m14_attendre 150 _e38_boucle || { _e38_defaire; return 10; }
}

# _e38_defaire — remet le déploiement s'il porte encore une des quatre marques.
_e38_defaire() {
  local d
  d="$(wb_kubectl -n "$_M14_NS" get deploy agenda -o json 2>/dev/null)" || d=""
  if jq -e '.spec.template.spec.containers[] | select(.name == "agenda")
        | ([.env[]?.name] | index("MEDIAGENDA_CACHE_URL"))
          or (.livenessProbe.httpGet.port == 8080)
          or (.resources.limits.memory == "32Mi")
          or ((.command // []) == ["mediagenda-api"])' >/dev/null 2>&1 <<<"$d"; then
    m14_restaurer_objet E38 deployment agenda "$_M14_NS"
  else
    m14_oublier_objet E38 deployment agenda "$_M14_NS"
  fi
}

panne_E38_v1() { m14_preparer && m14_essayer E38 4 1; }
panne_E38_v2() { m14_preparer && m14_essayer E38 4 2; }
panne_E38_v3() { m14_preparer && m14_essayer E38 4 3; }
panne_E38_v4() { m14_preparer && m14_essayer E38 4 4; }

verifier_E38() { _e38_boucle; }

annuler_E38() {
  _e38_defaire
  m14_oublier E38 debut
  m14_journal E38 "annulation"
}

resume_E38() { echo "La nouvelle version de l'agenda de test (wb-pannes) redémarre en boucle (CrashLoopBackOff)."; }

symptome_E38() {
  wb_symptome "Ticket INC-4138 — De : Julien Petit" \
    "Lucas a poussé hier soir une « petite mise à jour de configuration » de l'agenda de test" \
    "(déploiement « agenda », espace wb-pannes). Le nouveau pod démarre, s'arrête, redémarre…" \
    "« kubectl get pods » affiche CrashLoopBackOff et le compteur RESTARTS monte. L'ancienne" \
    "version tient encore le service. Trouve ce qui ne va pas sans deviner, corrige, et explique" \
    "à Lucas comment il aurait pu le voir avant de livrer." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 14 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 14 E38 4 "$@"; }
fi
