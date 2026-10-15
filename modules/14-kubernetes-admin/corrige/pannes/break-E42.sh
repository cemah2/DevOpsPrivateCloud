# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M14-E42 « Panne : le DNS du cluster ne répond plus »
#
# Cible : CoreDNS (kube-system) ou le témoin agenda (wb-pannes). Variantes :
#   1. déploiement coredns ramené à 0 réplica (« économie de ressources ») ;
#   2. Corefile cassé (directive inconnue « cache_ttl 30 ») puis pods coredns supprimés : les nouveaux
#      pods ne démarrent plus (CrashLoopBackOff) ;
#   3. « forward . » du Corefile vers un résolveur qui n'existe pas (10.10.20.250) : les noms internes
#      (*.cluster.local) répondent, plus aucun nom MédiSphère ni Internet ;
#   4. agenda en « dnsPolicy: Default » : ses pods résolvent avec le résolveur du nœud et ne trouvent
#      plus les Services « postgres » et « valkey » (agenda n'est plus prêt).
# Pas de NetworkPolicy (elles arrivent au module 15). CoreDNS est corrigé par « patch » et « scale »,
# jamais supprimé ni recréé. Annulation : seulement si la marque de la panne est encore en place.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m14-commun.sh
source "$WB_ROOT/modules/14-kubernetes-admin/corrige/pannes/_m14-commun.sh"

_E42_FAUX=10.10.20.250

_e42_corefile() { wb_kubectl -n kube-system get configmap coredns -o json 2>/dev/null | jq -r '.data.Corefile // empty'; }
_e42_poser_corefile() {
  jq -n --arg c "$1" '{data: {Corefile: $c}}' | wb_kubectl -n kube-system patch configmap coredns --type merge --patch-file /dev/stdin >/dev/null
}
# _e42_resout NOM — la sonde DNS des témoins résout NOM.
_e42_resout() { wb_kubectl -n "$_M14_NS" exec deploy/sonde-dns -- nslookup "$1" >/dev/null 2>&1; }
_e42_externe_ko() { _e42_resout kubernetes.default.svc.cluster.local && ! _e42_resout registry.par1.medisphere.internal; }
_e42_tout_ko() { ! _e42_resout kubernetes.default.svc.cluster.local; }
_e42_agenda_ko() { m14_nouveau_pod_etat E42 agenda '[.status.conditions[]? | select(.type == "Ready" and .status == "False")] | length > 0'; }

_m14E42_une() {
  local n="$1" c d neuf
  m14_debut E42
  case "$n" in
    1)
      c="$(wb_kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.replicas}' 2>/dev/null)"
      [[ "${c:-0}" -ge 1 ]] || return 10
      m14_ecrire E42 replicas "$c"
      wb_kubectl -n kube-system annotate deploy coredns --overwrite \
        medisphere.internal/ticket="IG-2251 : économie de ressources" >/dev/null || return 1
      wb_kubectl -n kube-system scale deploy coredns --replicas=0 >/dev/null || return 1
      m14_attendre 90 _e42_tout_ko || { _e42_defaire 1; return 10; }
      ;;
    2 | 3)
      c="$(_e42_corefile)"
      [[ -n "$c" ]] || return 1
      d="$(m14_etat E42)"
      [[ -e "$d/Corefile.orig" ]] && return 10
      printf '%s\n' "$c" >"$d/Corefile.orig"
      if [[ "$n" == 2 ]]; then
        grep -q '^[[:space:]]*cache ' <<<"$c" || return 10
        neuf="$(sed '0,/^\([[:space:]]*\)cache \(.*\)$/s//\1cache_ttl 30\n\1cache \2/' <<<"$c")"
      else
        grep -q '^[[:space:]]*forward \. ' <<<"$c" || return 10
        neuf="$(sed -E "0,/^([[:space:]]*)forward \. [^{]*/s//\1forward . $_E42_FAUX /" <<<"$c")"
      fi
      [[ "$neuf" != "$c" ]] || return 10
      printf '%s\n' "$neuf" >"$d/Corefile.panne"
      _e42_poser_corefile "$neuf" || return 1
      if [[ "$n" == 2 ]]; then
        wb_kubectl -n kube-system delete pod -l k8s-app=kube-dns --wait=false >/dev/null 2>&1 || true
        m14_attendre 120 _e42_tout_ko || { _e42_defaire 2; return 10; }
      else
        # Le greffon reload de CoreDNS relit le Corefile (propagation du ConfigMap : jusqu'à ~90 s).
        m14_attendre 180 _e42_externe_ko || { _e42_defaire 3; return 10; }
      fi
      ;;
    4)
      m14_sauver_objet E42 deployment agenda "$_M14_NS"
      wb_kubectl -n "$_M14_NS" patch deploy agenda --type merge \
        -p '{"spec":{"template":{"spec":{"dnsPolicy":"Default"}}}}' >/dev/null || return 1
      m14_attendre 120 _e42_agenda_ko || { _e42_defaire 4; return 10; }
      ;;
  esac
  m14_journal E42 "variante $n posée"
}

_e42_defaire() {
  local n="$1" d c r
  case "$n" in
    1)
      r="$(m14_lire E42 replicas)"
      if [[ -n "$r" ]] && [[ "$(wb_kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.replicas}' 2>/dev/null)" == 0 ]]; then
        wb_kubectl -n kube-system scale deploy coredns --replicas="$r" >/dev/null 2>&1 || wb_avert "coredns non remis à $r réplicas"
      fi
      wb_kubectl -n kube-system annotate deploy coredns medisphere.internal/ticket- >/dev/null 2>&1 || true
      m14_oublier E42 replicas
      ;;
    2 | 3)
      d="$(m14_etat E42)"
      if [[ -f "$d/Corefile.orig" && -f "$d/Corefile.panne" ]]; then
        c="$(_e42_corefile)" || c=""
        if [[ "$c" == "$(cat "$d/Corefile.panne")" ]]; then
          _e42_poser_corefile "$(cat "$d/Corefile.orig")" || wb_avert "Corefile non rétabli (copie : $d/Corefile.orig)"
          if [[ "$n" == 2 ]]; then
            wb_kubectl -n kube-system rollout restart deploy/coredns >/dev/null 2>&1 || true
          fi
        fi
      fi
      rm -f "$d/Corefile.orig" "$d/Corefile.panne"
      ;;
    4)
      if wb_kubectl -n "$_M14_NS" get deploy agenda -o jsonpath='{.spec.template.spec.dnsPolicy}' 2>/dev/null | grep -qx Default; then
        m14_restaurer_objet E42 deployment agenda "$_M14_NS"
      else
        m14_oublier_objet E42 deployment agenda "$_M14_NS"
      fi
      ;;
  esac
}

panne_E42_v1() { m14_preparer && m14_essayer E42 4 1; }
panne_E42_v2() { m14_preparer && m14_essayer E42 4 2; }
panne_E42_v3() { m14_preparer && m14_essayer E42 4 3; }
panne_E42_v4() { m14_preparer && m14_essayer E42 4 4; }

verifier_E42() {
  case "$WB_VAR" in
    1 | 2) _e42_tout_ko ;;
    3) _e42_externe_ko ;;
    4) _e42_agenda_ko ;;
  esac
}

annuler_E42() {
  local v
  case "${WB_VAR:-}" in
    [1-4]) _e42_defaire "$WB_VAR" ;;
    *) for v in 1 2 4; do _e42_defaire "$v"; done ;;
  esac
  m14_oublier E42 debut
  m14_journal E42 "annulation"
}

resume_E42() {
  case "${WB_VAR:-}" in
    3) echo "Dans les pods, les noms MédiSphère (registry, git01…) ne se résolvent plus ; les Services internes, si." ;;
    4) echo "La nouvelle version de l'agenda de test ne trouve plus sa base : « /pret » répond 503." ;;
    *) echo "Plus aucune résolution de noms dans les pods : « nslookup kubernetes.default » échoue." ;;
  esac
}

symptome_E42() {
  case "${WB_VAR:-}" in
    4)
      wb_symptome "Ticket INC-4142 — De : Julien Petit" \
        "Après la dernière livraison de l'agenda de test (déploiement « agenda », espace wb-pannes)," \
        "les nouveaux pods ne sont jamais prêts : /pret répond 503, « postgresql: indisponible »." \
        "La base tourne pourtant, son pod est Ready. Lucas a « optimisé la résolution DNS » dans" \
        "le manifeste. Trouve ce qui ne va pas sans rien changer à la base." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 14 42"
      ;;
    *)
      wb_symptome "Ticket INC-4142 — De : Nadia Roussel" \
        "Plusieurs équipes signalent des erreurs « Name or service not known » / « no such host »" \
        "depuis leurs pods. La sonde DNS de l'espace wb-pannes (déploiement « sonde-dns ») n'est" \
        "plus prête. Les nœuds eux-mêmes résolvent normalement. InfoGér et Lucas ont tous deux" \
        "touché à la configuration du cluster cette semaine. Rétablis le DNS des pods." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 14 42"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 14 E42 4 "$@"; }
fi
