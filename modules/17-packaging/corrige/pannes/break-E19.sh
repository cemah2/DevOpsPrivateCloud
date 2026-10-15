# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E19.sh — M17-E19 « Panne : la release est bloquée »
#
# Variantes :
#   1. release « mediagenda » de mediagenda-dev : une révision N+1 en « pending-upgrade » est écrite
#      au-dessus de la dernière révision « deployed » N, comme le laisse un « helm upgrade » interrompu
#      (même chart, mêmes valeurs, description « Preparing upgrade ») → « another operation … in progress » ;
#   2. release « mediagenda » de mediagenda-dev : le Secret de la dernière révision « deployed » N est
#      rendu illisible (contenu tronqué) ; Helm ne le voit plus, recalcule N comme révision suivante et
#      se heurte au Secret existant → « release: already exists » (exige N ≥ 2, sinon variante 1) ;
#   3. release « metrics-server » de kube-system : comme la variante 1 (bloque « helmfile apply »).
# Aucun objet applicatif n'est modifié : seuls les Secrets de release. Sauvegardes : wb_k8s_sauver et
# ~/.local/state/workbook/M17-E19/. Annulation : supprime la révision « pending-upgrade » écrite si elle
# est toujours dans cet état ; remet le Secret d'origine s'il est toujours illisible.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m17-commun.sh
source "$WB_ROOT/modules/17-packaging/corrige/pannes/_m17-commun.sh"

_e19_cible() {
  case "$1" in
    3) echo "kube-system metrics-server" ;;
    *) echo "mediagenda-dev mediagenda" ;;
  esac
}

# _e19_bloquer ESPACE RELEASE — écrit la révision N+1 en pending-upgrade.
_e19_bloquer() {
  local ns="$1" rel="$2" sec n json
  sec="$(m17_rel_derniere "$ns" "$rel" deployed)"
  [[ -n "$sec" ]] || return 10
  json="$(m17_rel_decoder "$ns" "$sec")"
  n="$(jq -r '.version' <<<"$json" 2>/dev/null)"
  [[ "$n" =~ ^[0-9]+$ ]] || return 10
  n=$((n + 1))
  # La révision N+1 ne doit pas exister (sinon l'état n'est pas celui attendu).
  wb_kubectl get secret "sh.helm.release.v1.${rel}.v${n}" -n "$ns" >/dev/null 2>&1 && return 10
  wb_k8s_sauver secret "sh.helm.release.v1.${rel}.v${n}" "$ns"
  jq --argjson n "$n" --arg t "$(date -u -d '-14 hours' +%Y-%m-%dT%H:%M:%S.000000000Z)" '
      .version = $n
      | .info.status = "pending-upgrade"
      | .info.description = "Preparing upgrade"
      | .info.last_deployed = $t
      | del(.info.notes)' <<<"$json" | m17_rel_creer "$ns" "$rel" "$n" pending-upgrade || return 1
  m17_ecrire E19 cible "bloquer $ns $rel $n"
  m17_journal E19 "révision $n de $ns/$rel écrite en pending-upgrade"
}

# _e19_corrompre ESPACE RELEASE — rend illisible la dernière révision deployed (si N ≥ 2).
_e19_corrompre() {
  local ns="$1" rel="$2" sec n
  sec="$(m17_rel_derniere "$ns" "$rel" deployed)"
  [[ -n "$sec" ]] || return 10
  n="${sec##*.v}"
  [[ "$n" =~ ^[0-9]+$ ]] && ((n >= 2)) || return 10
  # Révisions contiguës : la révision N-1 doit exister et se lire (sinon Helm écrirait dans le trou).
  m17_rel_lisible "$ns" "sh.helm.release.v1.${rel}.v$((n - 1))" || return 10
  wb_k8s_sauver secret "$sec" "$ns"
  # Début d'un flux gzip valide, puis plus rien : ce que laisse une écriture tronquée.
  wb_kubectl patch secret "$sec" -n "$ns" --type merge \
    -p "{\"data\":{\"release\":\"$(printf 'H4sIAAAAAAAC/+R9a3PbSJLgd/0KhPdu' | base64 -w0)\"}}" >/dev/null || return 1
  m17_ecrire E19 cible "corrompre $ns $rel $n"
  m17_journal E19 "Secret $sec de $ns rendu illisible (sauvegardé)"
}

_mE19_une() {
  local v="$1" ns rel
  read -r ns rel <<<"$(_e19_cible "$v")"
  m17_rel_saine "$ns" "$rel" || return 10
  case "$v" in
    1 | 3) _e19_bloquer "$ns" "$rel" ;;
    2) _e19_corrompre "$ns" "$rel" ;;
  esac
}

_e19_injecter() {
  m17_outils kubectl helm jq gzip base64 || return 1
  m17_essayer E19 3 "$1"
}

panne_E19_v1() { _e19_injecter 1; }
panne_E19_v2() { _e19_injecter 2; }
panne_E19_v3() { _e19_injecter 3; }

verifier_E19() {
  local action ns rel n max
  read -r action ns rel n <<<"$(m17_lire E19 cible)"
  [[ -n "${n:-}" ]] || return 1
  case "$action" in
    bloquer) [[ "$(m17_rel_statut "$ns" "$rel")" == pending-upgrade ]] ;;
    corrompre)
      max="$(m17_helm history "$rel" -n "$ns" -o json 2>/dev/null | jq '[.[].revision] | max // 0')"
      [[ "$max" =~ ^[0-9]+$ ]] && ((max < n))
      ;;
    *) return 1 ;;
  esac
}

annuler_E19() {
  local action ns rel n sec sauvegarde st
  read -r action ns rel n <<<"$(m17_lire E19 cible)"
  if [[ -n "${n:-}" ]]; then
    sec="sh.helm.release.v1.${rel}.v${n}"
    case "$action" in
      bloquer)
        st="$(wb_kubectl get secret "$sec" -n "$ns" -o jsonpath='{.metadata.labels.status}' 2>/dev/null || true)"
        if [[ "$st" == pending-upgrade ]]; then
          wb_kubectl delete secret "$sec" -n "$ns" --ignore-not-found >/dev/null 2>&1 || wb_avert "annulation : $sec non supprimé"
          m17_journal E19 "annulation : $sec supprimé"
        fi
        ;;
      corrompre)
        sauvegarde="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/$WB_EX/${ns}_secret_${sec}.yaml"
        if wb_kubectl get secret "$sec" -n "$ns" >/dev/null 2>&1 && ! m17_rel_lisible "$ns" "$sec" && [[ -s "$sauvegarde" ]] \
           && ! head -n1 "$sauvegarde" | grep -q '^ABSENT'; then
          wb_kubectl replace --force -f "$sauvegarde" >/dev/null 2>&1 || wb_avert "annulation : $sec non restauré"
          m17_journal E19 "annulation : $sec restauré"
        fi
        ;;
    esac
  fi
  rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/$WB_EX"
  m17_oublier E19 cible
}

resume_E19() {
  case "${WB_VAR:-}" in
    2) echo "Le « helm upgrade » du dev échoue avec « release: already exists » et l'historique a perdu une révision." ;;
    3) echo "« helmfile apply » échoue sur metrics-server : une autre opération serait en cours." ;;
    *) echo "Le « helm upgrade » du dev échoue : une autre opération serait en cours depuis hier soir." ;;
  esac
}

symptome_E19() {
  case "${WB_VAR:-}" in
    2)
      wb_symptome "Ticket INC-4419 — De : Nadia Roussel (pour Julien Petit)" \
        "Julien ne peut plus monter le dev. « helm upgrade mediagenda … -n mediagenda-dev » répond :" \
        "  Error: UPGRADE FAILED: release: already exists" \
        "Et « helm history » ne montre plus la dernière montée qu'il avait faite, alors que la" \
        "nouvelle version tourne bien. Personne n'a désinstallé quoi que ce soit." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 17 19"
      ;;
    3)
      wb_symptome "Ticket INC-4419 — De : Nadia Roussel (pour Karim Benali)" \
        "Le « helmfile apply » de plateforme/k8s échoue sur metrics-server :" \
        "  Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress" \
        "Le job de CI de cette nuit avait été annulé à la main parce qu'il « tournait depuis trop" \
        "longtemps ». Depuis, plus rien ne passe sur ce composant." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 17 19"
      ;;
    *)
      wb_symptome "Ticket INC-4419 — De : Nadia Roussel (pour Julien Petit)" \
        "Hier soir, le VPN de Julien a coupé pendant un « helm upgrade » du dev. Depuis, toute" \
        "commande sur la release répond :" \
        "  Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress" \
        "Il n'y a pourtant aucune opération en cours, ni sur son poste ni en CI." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 17 19"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 17 E19 3 "$@"; }
fi
