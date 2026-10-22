#!/usr/bin/env bash
# =============================================================================
# outils/pare-feu-hote.sh — plateforme/k8s (M26-E27, SEC-2727, RB-264) : état et mode du pare-feu
# d'hôte de Cilium sur UN nœud, depuis adm01.
#
# Usage : outils/pare-feu-hote.sh etat     NŒUD   point de terminaison d'hôte, audit, application
#         outils/pare-feu-hote.sh audit    NŒUD   passe l'hôte en mode AUDIT (rien n'est jeté)
#         outils/pare-feu-hote.sh applique NŒUD   sort du mode audit (la politique s'APPLIQUE)
#         outils/pare-feu-hote.sh verdicts NŒUD [DURÉE]   verdicts « audit » récents vers l'hôte (défaut 1h)
#
# Rappels (documentation « Host Firewall ») :
#   - le mode audit est porté par l'AGENT du nœud et ne survit pas à son redémarrage : après un
#     redémarrage de cilium-agent, le nœud APPLIQUE immédiatement les politiques qui le sélectionnent ;
#   - « applique » refuse si le nœud n'est pas étiqueté medisphere.internal/pare-feu-hote=oui (aucune
#     politique ne le sélectionnerait : passer « en application » ne voudrait rien dire) ou si des
#     verdicts « audit » existent sur la dernière heure (tampon local de Hubble de l'agent) ;
#   - sans API (nœud coupé) : console Proxmox, puis RB-264 §3 (crictl exec dans cilium-agent).
# Contexte kubectl : CONTEXTE (défaut k8s-par1), jamais le contexte courant par accident.
# =============================================================================
set -Eeuo pipefail

CONTEXTE="${CONTEXTE:-k8s-par1}"
ETIQUETTE=medisphere.internal/pare-feu-hote
usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

action="${1:-}"
noeud="${2:-}"
duree="${3:-1h}"
[[ -n "$action" && -n "$noeud" ]] || usage
[[ "$noeud" =~ ^k8s-(cp|w)0[1-9]$ ]] || { echo "nœud inconnu : $noeud" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq manquant" >&2; exit 1; }

k() { kubectl --context "$CONTEXTE" "$@"; }

pod="$(k -n kube-system get pods -l k8s-app=cilium --field-selector "spec.nodeName=$noeud" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "$pod" ]] || { echo "pas d'agent Cilium sur $noeud (API joignable ? RB-264 §3)" >&2; exit 1; }
agent() { k -n kube-system exec "$pod" -c cilium-agent -- "$@"; }

# Le point de terminaison d'hôte est celui dont l'identité vaut 1 (reserved:host).
id="$(agent cilium-dbg endpoint list -o json | jq -r '.[] | select(.status.identity.id == 1) | .id' | head -n 1)"
[[ "$id" =~ ^[0-9]+$ ]] || { echo "point de terminaison d'hôte introuvable sur $noeud" >&2; exit 1; }

mode_audit() { agent cilium-dbg endpoint config "$id" | awk '$1 == "PolicyAuditMode" { print $NF }'; }

verdicts_audit() {
  # Flux VERS l'hôte (identité 1) que la politique aurait refusés, dans le tampon local de Hubble.
  agent hubble observe --since "$duree" --verdict AUDIT --to-identity 1 -o compact 2>/dev/null || true
}

etiquete() {
  [[ "$(k get node "$noeud" -o jsonpath="{.metadata.labels.medisphere\.internal/pare-feu-hote}")" == oui ]]
}

case "$action" in
  etat)
    echo "nœud            : $noeud (agent $pod, point de terminaison d'hôte $id)"
    echo "étiquette       : $(etiquete && echo "$ETIQUETTE=oui" || echo 'absente (aucune politique d'"'"'hôte ne s'"'"'applique)')"
    echo "mode audit      : $(mode_audit)"
    echo "application     : $(agent cilium-dbg endpoint get "$id" -o json \
      | jq -r '.[0].status.policy.realized."policy-enabled" // "inconnue"') (ingress/both = politique active)"
    agent cilium-dbg status | grep -E '^Host firewall' || true
    ;;
  audit)
    agent cilium-dbg endpoint config "$id" PolicyAuditMode=Enabled
    echo "$noeud : mode audit = $(mode_audit) (perdu au prochain redémarrage de l'agent)"
    ;;
  applique)
    etiquete || { echo "$noeud n'est pas étiqueté $ETIQUETTE=oui : rien à appliquer (cluster/noeuds.yaml)" >&2; exit 1; }
    v="$(verdicts_audit)"
    if [[ -n "$v" ]]; then
      echo "Verdicts « audit » sur $duree : la politique aurait refusé ces flux. Corrige-la d'abord :" >&2
      printf '%s\n' "$v" | tail -n 20 >&2
      exit 1
    fi
    agent cilium-dbg endpoint config "$id" PolicyAuditMode=Disabled
    echo "$noeud : mode audit = $(mode_audit) ; la politique d'hôte S'APPLIQUE."
    echo "Contrôles : kubectl get nodes ; kubectl logs d'un pod du nœud ; cibles Prometheus du nœud ; BGP ; ssh."
    ;;
  verdicts)
    verdicts_audit
    ;;
  *) usage ;;
esac
