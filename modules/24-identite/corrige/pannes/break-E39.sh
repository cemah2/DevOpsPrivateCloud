# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-E39.sh — M24-E39 « Panne : les droits d'Argo CD sont faux »
#
# Argo CD est installé par Helmfile (release « argocd », valeurs composants/argocd/values.yaml de
# plateforme/k8s, M20) : il ne se réconcilie pas lui-même. Les variantes 1 à 3 modifient À LA MAIN la
# ConfigMap argocd-rbac-cm (dérive que « helmfile diff » montre) ; la 4 modifie Keycloak.
#   1. « scopes » des politiques sans « groups » ('[groups]' → '[email]') : les groupes ne servent plus,
#      chacun retombe sur policy.default (vide) : plus personne ne voit rien ;
#   2. policy.default: role:admin (« pour débloquer Julien », dit Lucas) : TOUT utilisateur authentifié
#      est administrateur d'Argo CD ; personne ne se plaint… sauf Sophie, qui l'a vu ;
#   3. nom de groupe faux dans policy.csv (g, plateforme-admins → g, plateforme-admin) : les
#      administrateurs perdent leurs droits, les autres groupes ne voient rien changer ;
#   4. mappeur « groups » de la portée « groupes » (Keycloak) avec le chemin complet : la revendication
#      devient « /plateforme-admins » ; aucune ligne de policy.csv ne correspond (et Grafana, Harbor,
#      kube-apiserver sont touchés de la même façon).
# Les objets d'argocd sont sauvegardés avant (JSON) ; restaurés seulement s'ils portent la marque.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m24-commun.sh
source "$WB_ROOT/modules/24-identite/corrige/pannes/_m24-commun.sh"

_e39_rbac() { m24_kubectl -n argocd get configmap argocd-rbac-cm -o json 2>/dev/null; }

# _e39_patch 'JSON de fusion' — modifie argocd-rbac-cm (fusion sur .data).
_e39_patch() { m24_kubectl -n argocd patch configmap argocd-rbac-cm --type merge -p "$1" >/dev/null; }

# _e39_mappeur — mappeur « groups » de la portée « groupes » (JSON) ; « portée|mappeur » dans _E39_IDS.
_e39_mappeur() {
  local pid
  pid="$(m24_kc_portee_uuid groupes)"
  [[ -n "$pid" ]] || return 1
  m24_kc GET "client-scopes/$pid/protocol-mappers/models" 2>/dev/null |
    jq -c --arg p "$pid" '[.[] | select(.protocolMapper == "oidc-group-membership-mapper")][0] // empty | . + {"_portee": $p}'
}

_m24E39_une() {
  local n="$1" r d csv m
  if ((n <= 3)); then
    r="$(_e39_rbac)" || return 10
    [[ -n "$r" ]] || return 10
    m24_kc_sauver E39 rbac "$r"
  fi
  m24_ecrire E39 variante "$n"
  case "$n" in
    1)
      d="$(jq -r '.data.scopes // ""' <<<"$r")"
      [[ "$d" == *groups* ]] || return 10
      _e39_patch '{"data":{"scopes":"[email]"}}' || return 1
      ;;
    2)
      [[ "$(jq -r '.data["policy.default"] // ""' <<<"$r")" != "role:admin" ]] || return 10
      _e39_patch '{"data":{"policy.default":"role:admin"}}' || return 1
      ;;
    3)
      csv="$(jq -r '.data["policy.csv"] // ""' <<<"$r")"
      grep -Eq '^[[:space:]]*g,[[:space:]]*plateforme-admins,' <<<"$csv" || return 10
      csv="$(sed -E 's/^([[:space:]]*g,[[:space:]]*)plateforme-admins,/\1plateforme-admin,/' <<<"$csv")"
      _e39_patch "$(jq -nc --arg c "$csv" '{data: {"policy.csv": $c}}')" || return 1
      ;;
    4)
      m="$(_e39_mappeur)" || m=""
      [[ -n "$m" ]] || return 10
      [[ "$(jq -r '.config["full.path"] // "false"' <<<"$m")" == false ]] || return 10
      m24_kc_sauver E39 mappeur "$m"
      m24_kc_json PUT "client-scopes/$(jq -r ._portee <<<"$m")/protocol-mappers/models/$(jq -r .id <<<"$m")" \
        "$(jq -c 'del(._portee) | .config["full.path"] = "true"' <<<"$m")" >/dev/null || return 1
      ;;
  esac
  m24_journal E39 "variante $n posée"
}

verifier_E39() {
  local r
  r="$(_e39_rbac)" || r=""
  case "$WB_VAR" in
    1) jq -e '.data.scopes == "[email]"' >/dev/null 2>&1 <<<"$r" ;;
    2) jq -e '.data["policy.default"] == "role:admin"' >/dev/null 2>&1 <<<"$r" ;;
    3) jq -r '.data["policy.csv"] // ""' <<<"$r" | grep -Eq '^[[:space:]]*g,[[:space:]]*plateforme-admin,' ;;
    4) _e39_mappeur | jq -e '.config["full.path"] == "true"' >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

panne_E39_v1() { m24_sain_keycloak && m24_essayer E39 4 1; }
panne_E39_v2() { m24_sain_keycloak && m24_essayer E39 4 2; }
panne_E39_v3() { m24_sain_keycloak && m24_essayer E39 4 3; }
panne_E39_v4() { m24_sain_keycloak && m24_essayer E39 4 4; }

annuler_E39() {
  local v r s m csv
  v="$(m24_lire E39 variante)"
  r="$(_e39_rbac 2>/dev/null || true)"
  s="$(m24_kc_sauve E39 rbac 2>/dev/null || true)"
  case "$v" in
    1)
      if [[ -n "$s" ]] && jq -e '.data.scopes == "[email]"' >/dev/null 2>&1 <<<"$r"; then
        _e39_patch "$(jq -c '{data: {scopes: (.data.scopes // "[groups]")}}' <<<"$s")" 2>/dev/null || wb_avert "scopes d'argocd-rbac-cm non rétablis"
      fi
      ;;
    2)
      if [[ -n "$s" ]] && jq -e '.data["policy.default"] == "role:admin"' >/dev/null 2>&1 <<<"$r"; then
        _e39_patch "$(jq -c '{data: {"policy.default": (.data["policy.default"] // "")}}' <<<"$s")" 2>/dev/null || wb_avert "policy.default non rétabli"
      fi
      ;;
    3)
      csv="$(jq -r '.data["policy.csv"] // ""' <<<"$r" 2>/dev/null || true)"
      if grep -Eq '^[[:space:]]*g,[[:space:]]*plateforme-admin,' <<<"$csv"; then
        csv="$(sed -E 's/^([[:space:]]*g,[[:space:]]*)plateforme-admin,/\1plateforme-admins,/' <<<"$csv")"
        _e39_patch "$(jq -nc --arg c "$csv" '{data: {"policy.csv": $c}}')" 2>/dev/null || wb_avert "policy.csv non rétabli"
      fi
      ;;
    4)
      m="$(_e39_mappeur 2>/dev/null || true)"
      if [[ -n "$m" ]] && jq -e '.config["full.path"] == "true"' >/dev/null 2>&1 <<<"$m"; then
        m24_kc_json PUT "client-scopes/$(jq -r ._portee <<<"$m")/protocol-mappers/models/$(jq -r .id <<<"$m")" \
          "$(jq -c 'del(._portee) | .config["full.path"] = "false"' <<<"$m")" >/dev/null 2>&1 || wb_avert "mappeur groups non rétabli"
      fi
      ;;
  esac
  m24_oublier E39 variante
  m24_kc_oublier E39 rbac
  m24_kc_oublier E39 mappeur
  m24_journal E39 "annulation"
}

resume_E39() { echo "Les droits d'Argo CD ne correspondent plus aux groupes de l'annuaire."; }

symptome_E39() {
  local qui detail
  case "$WB_VAR" in
    1) qui="Julien Petit"; detail="Je me connecte à Argo CD par le SSO, et je ne vois plus AUCUNE application. Karim non plus." ;;
    2) qui="Sophie Laurent"; detail="Nadia (support, lecture seule) vient de me montrer qu'elle a un bouton « Delete » actif sur mediagenda-prod dans Argo CD. Ce n'est pas normal." ;;
    3) qui="Karim Benali"; detail="Je n'ai plus que la lecture dans Argo CD : impossible de synchroniser plateforme. Julien, lui, synchronise ses applications comme d'habitude." ;;
    *) qui="Julien Petit"; detail="Je ne vois plus mes applications dans Argo CD. Et Nadia me dit que Grafana lui refuse l'entrée depuis ce matin." ;;
  esac
  wb_symptome "Ticket INC-5139 — De : $qui" \
    "$detail" \
    "Lucas a « aidé » quelqu'un sur Argo CD hier en fin de journée." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 24 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 24 E39 4 "$@"; }
fi
