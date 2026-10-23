#!/usr/bin/env bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# tests/ms-revue-acces/lancer.sh — tests de ms-revue-acces sans service réel (F6-S03, SEC-3603).
# Faux ldapsearch, kubectl et yq (dossier faux/) ; les systèmes sans faux sont ignorés (--ignorer).
set -euo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTIL="$ICI/../../bin/ms-revue-acces"
export PATH="$ICI/faux:$PATH" MS_REVUE_ENV=/nonexistent KUBECONFIG=/dev/null IPA_BIND_DN=faux IPA_BIND_PASSWORD=faux
IGN=keycloak,gitlab,proxmox,openbao,harbor,grafana
echecs=0
attendu() {
  local d="$1" c="$2" r=0
  shift 2
  "$@" >/dev/null 2>&1 || r=$?
  if [[ "$r" == "$c" ]]; then echo "ok    $d"; else echo "ÉCHEC $d (code $r, attendu $c)"; echecs=$((echecs + 1)); fi
}
verifie() { # verifie "description" 'filtre jq' — sur le JSON de la revue simulée
  if jq -e "$2" >/dev/null 2>&1 <<<"$R"; then echo "ok    $1"; else echo "ÉCHEC $1"; echecs=$((echecs + 1)); fi
}
attendu "usage : option inconnue → 2" 2 "$OUTIL" --tout
attendu "systèmes sans identité non ignorés → 1" 1 env -u IPA_BIND_DN "$OUTIL" --ignorer "$IGN"
attendu "orphelins présents → 1" 1 "$OUTIL" --ignorer "$IGN"
R="$("$OUTIL" --json --ignorer "$IGN" 2>/dev/null || true)"
verifie "désactivée encore membre d'un groupe → orphelin" '.a_traiter[] | select(.systeme == "annuaire" and .compte == "marc.vidal") | .statut == "orphelin"'
verifie "désactivée sans groupe → pas à traiter dans l'annuaire" '[.a_traiter[] | select(.systeme == "annuaire" and .compte == "yanis.perrin")] | length == 0'
verifie "liaison RBAC d'une personne désactivée → orphelin" '.a_traiter[] | select(.systeme == "kubernetes" and .compte == "yanis.perrin") | .statut == "orphelin"'
verifie "compte de service à cluster-admin non déclaré → à justifier" '.a_traiter[] | select(.compte == "sa:mediagenda-recette/outil-diagnostic") | .statut == "a-justifier"'
verifie "groupe non déclaré dans Argo CD → à justifier" '.a_traiter[] | select(.systeme == "argocd" and .compte == "ext-axiomdev") | .statut == "a-justifier"'
verifie "groupe déclaré → declare" '.comptes[] | select(.systeme == "kubernetes" and .compte == "plateforme-admins") | .statut == "declare"'
verifie "personne active → personne" '.comptes[] | select(.systeme == "kubernetes" and .compte == "karim.benali") | .statut == "personne"'
verifie "compte local déclaré d'Argo CD → declare" '.comptes[] | select(.systeme == "argocd" and .compte == "ci-lecture") | .statut == "declare"'
verifie "systèmes ignorés listés" '(.systemes_non_verifies | length) == 6'
M="$("$OUTIL" --ignorer "$IGN" 2>/dev/null || true)"
if grep -q '^| kubernetes | `yanis.perrin`' <<<"$M"; then echo "ok    sortie Markdown : ligne à traiter"; else echo "ÉCHEC sortie Markdown"; echecs=$((echecs + 1)); fi
((echecs == 0)) || { echo "$echecs test(s) en échec"; exit 1; }
echo "tous les tests passent"
