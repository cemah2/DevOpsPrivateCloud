# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M14-E41 « Panne : accès refusé »
#
# Variantes :
#   1. ton kubeconfig personnel (~/.kube/config, utilisateur du contexte courant) reçoit un certificat
#      client à ton nom et dans ton groupe, signé par la CA du cluster mais EXPIRÉ (émis il y a 30 jours
#      pour 7 jours, par « openssl ca » sur un nœud de contrôle) : « Unauthorized » ;
#   2. le RoleBinding qui donne des droits au groupe medisphere:mediagenda-devs dans mediagenda-dev a
#      son sujet mal orthographié (medisphere:mediagenda-dev) : Julien est « Forbidden » ;
#   3. ValidatingAdmissionPolicy « sec-volumes-locaux » (avec sa liaison, en Deny) sur wb-pannes et
#      mediagenda-* dont l'expression CEL interdit aussi emptyDir : les pods des bases jetables sont
#      refusés à la création ;
#   4. RoleBinding « sonde-api » (wb-pannes) dont le sujet ServiceAccount pointe sur l'espace default :
#      l'application qui lit l'API reçoit 403.
# Annulation : seulement si la marque de la panne est encore en place (fichier ou objet).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m14-commun.sh
source "$WB_ROOT/modules/14-kubernetes-admin/corrige/pannes/_m14-commun.sh"

_E41_KCFG="${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}"
_E41_VAP=sec-volumes-locaux

_e41_vap() {
  cat <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: sec-volumes-locaux
  annotations:
    medisphere.internal/ticket: "SEC-1541 (Lucas, pour Sophie) : interdire les volumes locaux"
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: "!has(object.spec.volumes) || object.spec.volumes.all(v, !has(v.hostPath) && !has(v.emptyDir))"
      message: "Les volumes locaux sont interdits sur les nœuds partagés (SEC-1541)."
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: sec-volumes-locaux
spec:
  policyName: sec-volumes-locaux
  validationActions: ["Deny"]
  matchResources:
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: In
          values: ["wb-pannes", "mediagenda-dev", "mediagenda-recette"]
EOF
}

# _e41_pod_essai — pod de test (emptyDir) pour constater le refus, jamais créé (dry-run=server).
_e41_pod_essai() {
  cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: essai-e41, namespace: $_M14_NS}
spec:
  securityContext: {runAsNonRoot: true, runAsUser: 65534, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: c
      image: $_M14_REGISTRE/dockerhub/library/busybox:1.37
      command: ["true"]
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
      volumeMounts: [{name: t, mountPath: /tmp}]
  volumes: [{name: t, emptyDir: {}}]
EOF
}

_e41_refus_vap() {
  local s
  s="$(_e41_pod_essai | wb_kubectl apply --dry-run=server -f - 2>&1)" && return 1
  grep -q "$_E41_VAP" <<<"$s"
}
_e41_unauthorized() {
  local s
  s="$(kubectl --kubeconfig "$_E41_KCFG" --request-timeout=15s auth whoami 2>&1)" && return 1
  grep -qi 'unauthorized\|must be logged in' <<<"$s"
}
_e41_julien_refuse() {
  [[ "$(wb_kubectl auth can-i create deployments -n mediagenda-dev --as julien.petit --as-group medisphere:mediagenda-devs 2>/dev/null)" == no ]]
}
_e41_sonde_ko() {
  wb_kubectl -n "$_M14_NS" get pods -l app.kubernetes.io/name=sonde-api -o json 2>/dev/null |
    jq -e '[.items[].status.conditions[]? | select(.type == "Ready" and .status == "False")] | length > 0' >/dev/null 2>&1
}

_m14E41_une() {
  local n="$1" d u cn grp noeud crt rb i
  case "$n" in
    1)
      [[ -f "$_E41_KCFG" ]] || return 10
      u="$(kubectl --kubeconfig "$_E41_KCFG" config view --minify -o jsonpath='{.contexts[0].context.user}' 2>/dev/null)"
      [[ -n "$u" ]] || return 10
      crt="$(kubectl --kubeconfig "$_E41_KCFG" config view --raw --minify -o jsonpath='{.users[0].user.client-certificate-data}' 2>/dev/null)"
      [[ -n "$crt" ]] || return 10 # identité sans certificat intégré : variante sans effet
      cn="$(base64 -d <<<"$crt" | openssl x509 -noout -subject -nameopt multiline 2>/dev/null | sed -n 's/^ *commonName *= *//p')"
      grp="$(base64 -d <<<"$crt" | openssl x509 -noout -subject -nameopt multiline 2>/dev/null | sed -n 's/^ *organizationName *= *//p' | head -n 1)"
      [[ -n "$cn" ]] || return 10
      noeud="${_M14_CP[0]}"
      d="$(m14_etat E41)"
      [[ -e "$d/kubeconfig.orig" ]] && return 10
      cp -p "$_E41_KCFG" "$d/kubeconfig.orig" && chmod 600 "$d/kubeconfig.orig"
      m14_wb_exec "$noeud" CN="$cn" GRP="${grp:-medisphere:plateforme-admins}" >"$d/faux.b64" <<'EOF' || { rm -f "$d/kubeconfig.orig" "$d/faux.b64"; return 1; }
t="$(mktemp -d)"
touch "$t/index.txt"; echo 1000 > "$t/serial"
cat > "$t/ca.cnf" <<CNF
[ ca ]
default_ca = wb
[ wb ]
database = $t/index.txt
serial = $t/serial
new_certs_dir = $t
certificate = /etc/kubernetes/pki/ca.crt
private_key = /etc/kubernetes/pki/ca.key
default_md = sha256
policy = pol
unique_subject = no
x509_extensions = ext
[ pol ]
organizationName = optional
commonName = supplied
[ ext ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
CNF
openssl req -new -newkey rsa:2048 -nodes -keyout "$t/k.pem" -out "$t/r.csr" -subj "/O=$GRP/CN=$CN" >/dev/null 2>&1 &&
  openssl ca -batch -notext -config "$t/ca.cnf" -in "$t/r.csr" -out "$t/c.pem" \
    -startdate "$(date -u -d '-30 days' +%Y%m%d%H%M%SZ)" -enddate "$(date -u -d '-23 days' +%Y%m%d%H%M%SZ)" >/dev/null 2>&1 || { rm -rf "$t"; exit 1; }
printf '%s %s\n' "$(base64 -w 0 "$t/c.pem")" "$(base64 -w 0 "$t/k.pem")"
rm -rf "$t"
journal "certificat client expiré émis pour $CN (simulation d'expiration)"
EOF
      read -r crt i <"$d/faux.b64"
      rm -f "$d/faux.b64"
      umask 077
      base64 -d <<<"$crt" >"$d/c.pem"
      base64 -d <<<"$i" >"$d/k.pem"
      kubectl --kubeconfig "$_E41_KCFG" config set-credentials "$u" --client-certificate="$d/c.pem" \
        --client-key="$d/k.pem" --embed-certs=true >/dev/null || { cp -p "$d/kubeconfig.orig" "$_E41_KCFG"; return 1; }
      sha256sum <"$d/c.pem" | cut -d' ' -f1 >"$d/faux.empreinte"
      rm -f "$d/c.pem" "$d/k.pem"
      m14_journal E41 "variante 1 : certificat expiré posé dans $_E41_KCFG (utilisateur $u)"
      m14_attendre 20 _e41_unauthorized || { _e41_defaire 1; return 10; }
      ;;
    2)
      rb="$(wb_kubectl -n mediagenda-dev get rolebindings -o json 2>/dev/null | jq -r '
        [.items[] | select(any(.subjects[]?; .kind == "Group" and .name == "medisphere:mediagenda-devs")) | .metadata.name][0] // empty')"
      [[ -n "$rb" ]] || return 10
      m14_ecrire E41 rolebinding "$rb"
      m14_sauver_objet E41 rolebinding "$rb" mediagenda-dev
      i="$(wb_kubectl -n mediagenda-dev get rolebinding "$rb" -o json | jq '[.subjects[] | .kind == "Group" and .name == "medisphere:mediagenda-devs"] | index(true)')"
      wb_kubectl -n mediagenda-dev patch rolebinding "$rb" --type json \
        -p "[{\"op\":\"replace\",\"path\":\"/subjects/$i/name\",\"value\":\"medisphere:mediagenda-dev\"}]" >/dev/null || return 1
      m14_journal E41 "variante 2 : sujet du RoleBinding $rb modifié"
      m14_attendre 20 _e41_julien_refuse || { _e41_defaire 2; return 10; }
      ;;
    3)
      wb_kubectl get validatingadmissionpolicy "$_E41_VAP" >/dev/null 2>&1 && return 10
      _e41_vap | wb_kubectl apply -f - >/dev/null || return 1
      m14_ecrire E41 vap 1
      # Les pods de la base jetable des témoins sont recréés… et refusés.
      wb_kubectl -n "$_M14_NS" delete pod -l app.kubernetes.io/name=postgres --wait=false >/dev/null 2>&1 || true
      m14_journal E41 "variante 3 : politique $_E41_VAP et sa liaison créées"
      m14_attendre 30 _e41_refus_vap || { _e41_defaire 3; return 10; }
      ;;
    4)
      m14_sauver_objet E41 rolebinding sonde-api "$_M14_NS"
      wb_kubectl -n "$_M14_NS" patch rolebinding sonde-api --type json \
        -p '[{"op":"replace","path":"/subjects/0/namespace","value":"default"}]' >/dev/null || return 1
      m14_journal E41 "variante 4 : sujet du RoleBinding sonde-api vers l'espace default"
      m14_attendre 120 _e41_sonde_ko || { _e41_defaire 4; return 10; }
      ;;
  esac
}

_e41_defaire() {
  local n="$1" d rb cur
  case "$n" in
    1)
      d="$(m14_etat E41)"
      if [[ -f "$d/kubeconfig.orig" ]]; then
        cur="$(kubectl --kubeconfig "$_E41_KCFG" config view --raw --minify -o jsonpath='{.users[0].user.client-certificate-data}' 2>/dev/null | base64 -d 2>/dev/null | sha256sum | cut -d' ' -f1)" || cur=""
        if [[ -f "$d/faux.empreinte" && "$cur" == "$(cat "$d/faux.empreinte")" ]]; then
          cp -p "$d/kubeconfig.orig" "$_E41_KCFG" && chmod 600 "$_E41_KCFG"
          m14_journal E41 "annulation : kubeconfig personnel d'origine remis"
        fi
      fi
      rm -f "$d/kubeconfig.orig" "$d/faux.empreinte" "$d/c.pem" "$d/k.pem" "$d/faux.b64"
      ;;
    2)
      rb="$(m14_lire E41 rolebinding)"
      if [[ -n "$rb" ]]; then
        if wb_kubectl -n mediagenda-dev get rolebinding "$rb" -o json 2>/dev/null |
          jq -e 'any(.subjects[]?; .kind == "Group" and .name == "medisphere:mediagenda-dev")' >/dev/null 2>&1; then
          m14_restaurer_objet E41 rolebinding "$rb" mediagenda-dev
        else
          m14_oublier_objet E41 rolebinding "$rb" mediagenda-dev
        fi
      fi
      m14_oublier E41 rolebinding
      ;;
    3)
      if [[ -n "$(m14_lire E41 vap)" ]]; then
        if wb_kubectl get validatingadmissionpolicy "$_E41_VAP" -o json 2>/dev/null | jq -e '.spec.validations[].expression | test("emptyDir")' >/dev/null 2>&1; then
          wb_kubectl delete validatingadmissionpolicybinding "$_E41_VAP" --ignore-not-found >/dev/null 2>&1 || true
          wb_kubectl delete validatingadmissionpolicy "$_E41_VAP" --ignore-not-found >/dev/null 2>&1 || true
          m14_journal E41 "annulation : politique $_E41_VAP retirée"
        fi
      fi
      m14_oublier E41 vap
      ;;
    4)
      if wb_kubectl -n "$_M14_NS" get rolebinding sonde-api -o json 2>/dev/null | jq -e '.subjects[0].namespace == "default"' >/dev/null 2>&1; then
        m14_restaurer_objet E41 rolebinding sonde-api "$_M14_NS"
      else
        m14_oublier_objet E41 rolebinding sonde-api "$_M14_NS"
      fi
      ;;
  esac
}

panne_E41_v1() { m14_preparer && m14_essayer E41 4 1; }
panne_E41_v2() { m14_preparer && m14_essayer E41 4 2; }
panne_E41_v3() { m14_preparer && m14_essayer E41 4 3; }
panne_E41_v4() { m14_preparer && m14_essayer E41 4 4; }

verifier_E41() {
  case "$WB_VAR" in
    1) _e41_unauthorized ;;
    2) _e41_julien_refuse ;;
    3) _e41_refus_vap ;;
    4) _e41_sonde_ko ;;
  esac
}

annuler_E41() {
  local v
  case "${WB_VAR:-}" in
    [1-4]) _e41_defaire "$WB_VAR" ;;
    *) for v in 1 2 3 4; do _e41_defaire "$v"; done ;;
  esac
  m14_journal E41 "annulation"
}

resume_E41() {
  case "${WB_VAR:-}" in
    1) echo "Ton propre kubectl répond « You must be logged in to the server (Unauthorized) »." ;;
    2) echo "Julien Petit n'a plus aucun droit dans mediagenda-dev (Forbidden)." ;;
    3) echo "Les bases de test de wb-pannes ne redémarrent plus : leurs pods sont refusés à la création." ;;
    4) echo "L'application de test « sonde-api » (wb-pannes) n'arrive plus à lire l'API : elle n'est plus prête." ;;
  esac
}

symptome_E41() {
  case "${WB_VAR:-}" in
    1)
      wb_symptome "Ticket INC-4141 — De : toi-même (note d'astreinte)" \
        "Lundi matin, premier « kubectl get nodes » de la semaine :" \
        "« error: You must be logged in to the server (Unauthorized) ». Karim, avec son poste, n'a" \
        "aucun problème. Retrouve l'accès sans utiliser admin.conf ni super-admin.conf (ils sont" \
        "réservés au bris de glace) et note ce qui aurait dû te prévenir." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 14 41"
      ;;
    2)
      wb_symptome "Ticket INC-4141 — De : Julien Petit" \
        "Depuis ce matin, toute l'équipe MédiAgenda est refusée dans mediagenda-dev :" \
        "« deployments.apps is forbidden: User \"julien.petit\" cannot list resource … ». Nos" \
        "certificats sont valides (vérifiés). Lucas a « rangé les RoleBindings » hier." \
        "Rends-nous nos droits, ni plus ni moins qu'avant." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 14 41"
      ;;
    3)
      wb_symptome "Ticket INC-4141 — De : Julien Petit" \
        "La base PostgreSQL de l'agenda de test (espace wb-pannes) a redémarré et ne revient pas :" \
        "« kubectl get pods » ne montre plus aucun pod postgres, et l'agenda n'est plus prêt." \
        "Sophie a demandé un durcissement des espaces des équipes cette semaine, Lucas s'en est" \
        "chargé. Remets la base en service sans désactiver la sécurité voulue par Sophie." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 14 41"
      ;;
    4)
      wb_symptome "Ticket INC-4141 — De : Nadia Roussel" \
        "L'application de test « sonde-api » (espace wb-pannes), qui lit l'API Kubernetes avec son" \
        "propre compte de service, n'est plus prête ; ses journaux disent « lecture de l'API :" \
        "ECHEC ». Rien n'a été redéployé. Lucas a « factorisé les RoleBindings » des espaces." \
        "Rends-lui son accès, sans lui donner un droit de plus." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 14 41"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 14 E41 4 "$@"; }
fi
