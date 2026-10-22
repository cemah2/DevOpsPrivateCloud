# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # LogQL, jq et code Python entre apostrophes
# break-E23.sh — M22-E23 « Astreinte : enquête par les journaux »
#
# 1. L'incident à enquêter (« des rendez-vous ont disparu en recette ») :
#    - un compte de service témoin wb-pannes/outillage-recette reçoit, dans mediagenda-recette, un Role
#      et un RoleBinding « outillage-recette » (lecture des pods, exec) — « outil de purge des données de
#      test » de Lucas ;
#    - quatre rendez-vous de démonstration (praticien dr-demo-recette, patients « Démo client N »,
#      factices) sont créés dans la recette par un exec dans un pod mediagenda AVEC TON IDENTITÉ (c'est
#      « Julien qui prépare sa démo ») ;
#    - une minute plus tard, ces quatre rendez-vous — et eux seuls — sont supprimés par un exec dans un
#      pod mediagenda AVEC L'IDENTITÉ DU COMPTE DE SERVICE (jeton de 10 min, kubeconfig temporaire sans
#      certificat client) : MédiAgenda journalise « rendez-vous supprimé » (client 127.0.0.1), le journal
#      d'audit garde l'exec du compte de service.
#    Aucun rendez-vous existant n'est touché : seuls ceux que la panne a créés sont supprimés.
#    Les preuves doivent être dans Loki (locataires mediagenda ET audit) avant la suite, sinon rien.
# 2. UNE panne de M22-E19 à M22-E22 (variante au hasard) est injectée ensuite : elle gêne l'enquête
#    (collecte, écriture, requêtes ou locataire) sans effacer les preuves déjà reçues.
#   --variante N (1 à 4) force la panne enchaînée : 1 = E19, 2 = E20, 3 = E21, 4 = E22.
#   --annuler  annule la panne enchaînée et retire le Role, le RoleBinding et le compte de service.

_WB_E23_DIR="$(dirname "${BASH_SOURCE[0]}")"
WB_PANNES_LIB=1
# shellcheck source=break-E19.sh
source "$_WB_E23_DIR/break-E19.sh"
# shellcheck source=break-E20.sh
source "$_WB_E23_DIR/break-E20.sh"
# shellcheck source=break-E21.sh
source "$_WB_E23_DIR/break-E21.sh"
# shellcheck source=break-E22.sh
source "$_WB_E23_DIR/break-E22.sh"
unset WB_PANNES_LIB

_E23_NS_APP=mediagenda-recette
_E23_SA=outillage-recette
_E23_ETIQ=medisphere.internal/ticket=DEV-2323
declare -A _E23_NB=([E19]=4 [E20]=3 [E21]=3 [E22]=3)
_E23_LISTE=(E19 E20 E21 E22)

# _e23_pod — pod mediagenda prêt de la recette et son conteneur applicatif : « pod conteneur ».
_e23_pod() {
  wb_kubectl -n "$_E23_NS_APP" get pods -l app.kubernetes.io/name=mediagenda -o json 2>/dev/null | jq -r '
    [.items[] | select(.status.phase == "Running")
      | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))
      | {p: .metadata.name, c: ([.spec.containers[] | select(.image | test("mediagenda"))][0].name)}
      | select(.c != null)][0] | select(. != null) | "\(.p) \(.c)"'
}

_e23_objets() {
  cat <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $_E23_SA
  namespace: $_M22_PANNES
  labels: {medisphere.internal/ticket: DEV-2323}
  annotations: {medisphere.internal/description: "Outil de purge des données de test de la recette (Lucas)"}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $_E23_SA
  namespace: $_E23_NS_APP
  labels: {medisphere.internal/ticket: DEV-2323}
rules:
  - apiGroups: [""]
    resources: [pods]
    verbs: [get, list]
  - apiGroups: [""]
    resources: [pods/exec]
    verbs: [get, create]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $_E23_SA
  namespace: $_E23_NS_APP
  labels: {medisphere.internal/ticket: DEV-2323}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: $_E23_SA}
subjects:
  - {kind: ServiceAccount, name: $_E23_SA, namespace: $_M22_PANNES}
EOF
}

# Code exécuté DANS le conteneur MédiAgenda (python3 de l'image) : création des rendez-vous de démo.
read -r -d '' _E23_PY_CREER <<'PY' || true
import datetime, json, os, random, urllib.request, zoneinfo
tz = zoneinfo.ZoneInfo("Europe/Paris")
port = os.environ.get("MEDIAGENDA_PORT", "8000")
d = datetime.date.today() + datetime.timedelta(days=40 + random.randint(0, 30))
while d.weekday() >= 5:
    d += datetime.timedelta(days=1)
ids = []
for i in range(4):
    debut = datetime.datetime(d.year, d.month, d.day, 9, 0, tzinfo=tz) + datetime.timedelta(minutes=30 * i)
    corps = {"patient": f"Démo client {i + 1}", "praticien": "dr-demo-recette",
             "debut": debut.isoformat(), "duree_minutes": 30, "motif": "Démonstration client"}
    req = urllib.request.Request(f"http://127.0.0.1:{port}/api/v1/rendez-vous", data=json.dumps(corps).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        ids.append(json.load(r)["id"])
print(d.isoformat(), " ".join(str(i) for i in ids))
PY

# Suppression des seuls rendez-vous créés ci-dessus (identifiants en arguments).
read -r -d '' _E23_PY_SUPPRIMER <<'PY' || true
import os, sys, urllib.request
port = os.environ.get("MEDIAGENDA_PORT", "8000")
for i in sys.argv[1:]:
    req = urllib.request.Request(f"http://127.0.0.1:{port}/api/v1/rendez-vous/{int(i)}", method="DELETE")
    urllib.request.urlopen(req, timeout=10).close()
print("ok")
PY

# _e23_kubeconfig_sa FICHIER — kubeconfig temporaire (600) : serveur et CA de l'administration, jeton
# court du compte de service, AUCUN certificat client (sinon l'API retiendrait ton identité).
_e23_kubeconfig_sa() {
  local f="$1" jeton serveur ca
  jeton="$(wb_kubectl -n "$_M22_PANNES" create token "$_E23_SA" --duration=10m 2>/dev/null)" || return 1
  serveur="$(wb_kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')" || return 1
  ca="$(wb_kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')" || return 1
  (umask 077 && jq -n --arg s "$serveur" --arg ca "$ca" --arg t "$jeton" '{
      apiVersion: "v1", kind: "Config", "current-context": "sa",
      clusters: [{name: "k8s", cluster: {server: $s, "certificate-authority-data": $ca}}],
      users: [{name: "sa", user: {token: $t}}],
      contexts: [{name: "sa", context: {cluster: "k8s", user: "sa"}}]}' >"$f")
}

_e23_preuves_mediagenda() {
  (($(m22_nb_lignes mediagenda "{namespace=\"$_E23_NS_APP\"} |= \"rendez-vous supprimé\"" 15m) >= 4))
}
# _e23_lignes_audit 'filtres de ligne' [DEPUIS] — lignes du locataire audit (sélecteurs usuels essayés).
_e23_lignes_audit() {
  local s n
  for s in '{job=~".+"}' '{node=~".+"}' '{cluster=~".+"}'; do
    n="$(m22_nb_lignes audit "$s $1" "${2:-15m}")"
    ((n > 0)) && { echo "$n"; return 0; }
  done
  echo 0
}
_e23_preuves_audit() { (($(_e23_lignes_audit "|= \"$_E23_SA\" |= \"exec\"") >= 1)); }

# _e23_incident — étape 1 ; code ≠ 0 si quelque chose manque (rien n'est alors laissé en place).
_e23_incident() {
  local pc pod ctr sortie jour ids f
  pc="$(_e23_pod)"
  [[ -n "$pc" ]] || { echo "Aucun pod mediagenda prêt dans $_E23_NS_APP : rien n'est cassé." >&2; return 1; }
  read -r pod ctr <<<"$pc"
  if (($(_e23_lignes_audit '') == 0)); then
    echo "Aucune ligne récente dans le locataire audit (lab/bin/check 22 07) : l'enquête serait impossible, rien n'est cassé." >&2
    return 1
  fi
  wb_kubectl get namespace "$_M22_PANNES" >/dev/null 2>&1 ||
    wb_kubectl create namespace "$_M22_PANNES" >/dev/null || return 1
  _e23_objets | wb_kubectl apply -f - >/dev/null || return 1
  m22_journal E23 "compte $_M22_PANNES/$_E23_SA, Role et RoleBinding $_E23_NS_APP/$_E23_SA créés"
  sortie="$(wb_kubectl -n "$_E23_NS_APP" exec "$pod" -c "$ctr" -- python3 -c "$_E23_PY_CREER" 2>/dev/null)" || {
    echo "Création des rendez-vous de démonstration impossible dans $pod : rien n'est cassé." >&2
    return 1
  }
  read -r jour ids <<<"$sortie"
  [[ "$ids" =~ ^[0-9]+( [0-9]+){3}$ ]] || return 1
  m22_poser E23 rendez-vous "$jour $ids"
  m22_journal E23 "4 rendez-vous de démonstration créés ($jour : $ids) par exec dans $pod"
  sleep 60
  f="$(m22_etat E23)/kubeconfig-sa"
  _e23_kubeconfig_sa "$f" || { rm -f "$f"; return 1; }
  # shellcheck disable=SC2086  # identifiants séparés voulus
  if ! kubectl --kubeconfig "$f" --request-timeout=20s -n "$_E23_NS_APP" exec "$pod" -c "$ctr" -- \
    python3 -c "$_E23_PY_SUPPRIMER" $ids >/dev/null 2>&1; then
    rm -f "$f"
    # Nettoyage : les rendez-vous de démonstration créés par la panne sont retirés avec ton identité.
    # shellcheck disable=SC2086
    wb_kubectl -n "$_E23_NS_APP" exec "$pod" -c "$ctr" -- python3 -c "$_E23_PY_SUPPRIMER" $ids >/dev/null 2>&1 || true
    echo "Suppression par le compte de service impossible (droits ?) : rien n'est cassé." >&2
    return 1
  fi
  rm -f "$f"
  m22_journal E23 "4 rendez-vous supprimés par exec du compte $_E23_SA dans $pod"
  if ! m22_attendre 240 _e23_preuves_mediagenda; then
    echo "Les journaux de la suppression ne sont pas arrivés dans le locataire mediagenda : rien n'est cassé." >&2
    return 1
  fi
  if ! m22_attendre 240 _e23_preuves_audit; then
    echo "L'exec du compte de service n'apparaît pas dans le locataire audit (journal d'audit, M14-E27, M22-E07) : rien n'est cassé." >&2
    return 1
  fi
}

_e23_retirer_objets() {
  wb_kubectl -n "$_E23_NS_APP" delete rolebinding,role -l "$_E23_ETIQ" --ignore-not-found >/dev/null 2>&1 || true
  wb_kubectl -n "$_M22_PANNES" delete serviceaccount -l "$_E23_ETIQ" --ignore-not-found >/dev/null 2>&1 || true
}

_e23_annuler() {
  local liste ex var
  liste="$(wb_marqueur_lire M22-E23)"
  for ex in "${_E23_LISTE[@]}"; do
    if [[ " $liste " == *" $ex:"* ]] || wb_marqueur_existe "M22-$ex"; then
      var="$(wb_marqueur_lire "M22-$ex")"
      [[ -n "$var" ]] || var="$(sed -n "s/.*$ex:\([0-9]*\).*/\1/p" <<<"$liste")"
      WB_EX="M22-$ex"
      WB_VAR="${var:-annulation}"
      "annuler_$ex" || true
      wb_marqueur_suppr "M22-$ex"
    fi
  done
  WB_EX=M22-E23
  WB_VAR=0
  _e23_retirer_objets
  rm -f -- "$(m22_etat E23)/kubeconfig-sa"
  m22_oublier E23 rendez-vous
  m22_journal E23 "annulation"
  wb_marqueur_suppr M22-E23
}

main() {
  local choix="" annuler=0
  while (($#)); do
    case "$1" in
      --variante)
        if (($# < 2)); then echo "--variante attend un numéro" >&2; return 2; fi
        choix="$2"; shift 2 ;;
      --variante=*) choix="${1#*=}"; shift ;;
      --annuler) annuler=1; shift ;;
      *) echo "Option inconnue : $1 (attendu : --variante N, --annuler)" >&2; return 2 ;;
    esac
  done

  if ((annuler)); then
    _e23_annuler
    echo "Astreinte M22-E23 annulée. Contrôle : lab/bin/check 22 23"
    return 0
  fi

  local ex
  for ex in E23 "${_E23_LISTE[@]}"; do
    if wb_marqueur_existe "M22-$ex"; then
      echo "Une panne M22-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done
  if [[ -z "$choix" ]]; then choix=$((RANDOM % 4 + 1)); fi
  if ! [[ "$choix" =~ ^[1-4]$ ]]; then
    echo "Variante invalide : $choix (1 à 4)" >&2
    return 2
  fi
  ex="${_E23_LISTE[choix - 1]}"

  echo "Injection en cours (incident, preuves, puis une panne : compte 10 à 20 minutes)…"
  WB_EX=M22-E23
  WB_VAR=0
  m22_sain || { echo "Lab des journaux pas sain avant l'astreinte : rien n'est cassé." >&2; return 1; }
  wb_marqueur_ecrire M22-E23 ""
  if ! _e23_incident; then
    _e23_annuler >/dev/null 2>&1
    return 1
  fi

  _M22_ASTREINTE=1
  local v
  v=$((RANDOM % ${_E23_NB[$ex]} + 1))
  WB_EX="M22-$ex"
  WB_VAR="$v"
  if ! "panne_${ex}_v${v}" >/dev/null || ! "verifier_$ex" 2>/dev/null; then
    wb_marqueur_ecrire "M22-$ex" "$WB_VAR"
    wb_marqueur_ecrire M22-E23 "$ex:$WB_VAR"
    unset _M22_ASTREINTE
    echo "La panne enchaînée $ex n'a pas pu être posée ou constatée : remise en état, rien n'est cassé." >&2
    _e23_annuler >/dev/null 2>&1
    return 1
  fi
  unset _M22_ASTREINTE
  wb_marqueur_ecrire "M22-$ex" "$WB_VAR"
  wb_marqueur_ecrire M22-E23 "$ex:$WB_VAR"
  local resume jour
  resume="$("resume_$ex")"
  WB_EX=M22-E23
  read -r jour _ <<<"$(m22_lire E23 rendez-vous)"

  wb_symptome "Ticket INC-4923 — De : Nadia Roussel (astreinte) — Copie : Julien Petit, Sophie Laurent" \
    "Tu es d'astreinte. Julien vient d'appeler : les quatre rendez-vous de démonstration qu'il" \
    "avait préparés en recette pour la démo client (praticien dr-demo-recette, le $jour) ont" \
    "disparu. Personne de son équipe n'y a touché. Sophie veut savoir QUI, QUAND et COMMENT," \
    "preuves à l'appui, et que cela ne puisse pas se reproduire." \
    "Pour corser le tout, l'outillage des journaux fait des siennes :" \
    "- $resume" \
    "" \
    "Rétablis d'abord ce qui t'empêche d'enquêter, puis enquête uniquement par les journaux" \
    "(Loki : locataires mediagenda et audit) ; ne touche à rien de l'équipe MédiAgenda avant" \
    "d'avoir les preuves. Rédige le post-mortem avec le modèle de l'équipe" \
    "(modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "Temps cible : 1 h 30 (enquête et rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 22 23"
}
