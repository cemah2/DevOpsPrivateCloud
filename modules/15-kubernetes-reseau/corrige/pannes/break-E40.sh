# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M15-E40 « Panne : le certificat n'est jamais délivré »
#
# Témoin : Certificate wb-essais/joker-repetition (*.apps.par1.medisphere.internal, émetteur
# ClusterIssuer step-ca-acme : un joker exige le défi DNS-01), créé APRÈS la panne.
# Variantes :
#   1. TSIG : tsigKeyName du solveur rfc2136 changé (certmanager-k8s → certmanager) : mise à jour
#      refusée par l'autoritaire (BADKEY / NOTAUTH) ;
#   2. caBundle de l'émetteur remplacé par une CA « MédiSphère CA provisoire » régénérée (la CA des
#      modules 01 à 06, retirée) : le client ACME ne fait plus confiance à ca01 ;
#   3. sélecteur du solveur DNS-01 : apps.par1… → app.par1… (faute de frappe) : aucun solveur
#      utilisable pour le joker (HTTP-01 n'accepte pas les jokers) ;
#   4. le Certificate témoin désigne « step-ca-acme » sans kind (Issuer par défaut) : émetteur
#      introuvable dans l'espace.
# L'horloge et les quotas ACME sont traités dans le corrigé (non injectés : ils toucheraient ca01
# ou tous les nœuds).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m15-commun.sh
source "$WB_ROOT/modules/15-kubernetes-reseau/corrige/pannes/_m15-commun.sh"

_E40_NS=wb-essais
_E40_CERT=joker-repetition

_e40_issuer() { m15_k get clusterissuer "$_M15_ISSUER" -o json 2>/dev/null; }

_e40_temoin() {
  local kind="$1"
  m15_sauver certificate "$_E40_CERT" "$_E40_NS"
  m15_sauver secret "$_E40_CERT-tls" "$_E40_NS"
  m15_k apply -f - >/dev/null 2>&1 <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $_E40_CERT
  namespace: $_E40_NS
  annotations:
    medisphere.fr/demande: "PLAT-1647 : répétition du renouvellement du joker"
spec:
  secretName: $_E40_CERT-tls
  duration: 2160h
  dnsNames:
    - "*.$_M15_ZONE"
  privateKey:
    algorithm: ECDSA
    size: 256
    rotationPolicy: Always
  issuerRef:
    name: $_M15_ISSUER
$kind
EOF
}

_e40_non_delivre() {
  ! m15_k -n "$_E40_NS" get certificate "$_E40_CERT" -o json 2>/dev/null \
    | jq -e '.status.conditions[]? | select(.type == "Ready" and .status == "True")' >/dev/null
}

_m15E40_une() {
  local n="$1" j idx pem
  j="$(_e40_issuer)" || return 1
  idx="$(jq -r '[.spec.acme.solvers | to_entries[] | select(.value.dns01.rfc2136 != null) | .key][0] // empty' <<<"$j")"
  case "$n" in
    1)
      [[ -n "$idx" ]] || return 10
      m15_patch_json clusterissuer "$_M15_ISSUER" "" \
        ".spec.acme.solvers[$idx].dns01.rfc2136.tsigKeyName |= (sub(\"certmanager-k8s\"; \"certmanager\"))" || return 10
      ;;
    2)
      pem="$(openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout /dev/null \
        -subj "/O=MediSphere/CN=MediSphere CA provisoire" -days 30 2>/dev/null)" || return 1
      m15_patch_json clusterissuer "$_M15_ISSUER" "" ".spec.acme.caBundle = \"$(printf '%s\n' "$pem" | base64 -w0)\"" || return 1
      ;;
    3)
      [[ -n "$idx" ]] || return 10
      m15_patch_json clusterissuer "$_M15_ISSUER" "" "
        .spec.acme.solvers[$idx].selector |= (
          if . == null then {dnsZones: [\"app.par1.medisphere.internal\"]}
          else ((.dnsZones // empty) |= map(sub(\"^apps\\\\.\"; \"app.\")))
             | ((.dnsNames // empty) |= map(sub(\"\\\\.apps\\\\.\"; \".app.\")))
          end)" || return 10
      ;;
    4)
      m15_ecrire E40 kind_absent oui
      ;;
  esac
  m15_ecrire E40 issuer_pose "$(_e40_issuer | jq -cS '.spec')"
  if ((n == 4)); then
    _e40_temoin "" || return 1
  else
    _e40_temoin "    kind: ClusterIssuer" || return 1
  fi
  m15_journal E40 "variante $n posée"
}

panne_E40_v1() { m15_preparer && m15_essayer E40 4 1; }
panne_E40_v2() { m15_preparer && m15_essayer E40 4 2; }
panne_E40_v3() { m15_preparer && m15_essayer E40 4 3; }
panne_E40_v4() { m15_preparer && m15_essayer E40 4 4; }

# Le certificat témoin ne doit pas être délivré au bout de 90 s (une émission saine prend 20 à 60 s).
verifier_E40() { sleep 90; _e40_non_delivre; }

annuler_E40() {
  local pose
  pose="$(m15_lire E40 issuer_pose)"
  if [[ -n "$pose" && "${WB_VAR:-}" != 4 && "$(_e40_issuer | jq -cS '.spec' 2>/dev/null || true)" == "$pose" ]]; then
    m15_remettre clusterissuer "$_M15_ISSUER" ""
  fi
  # Le témoin (certificat, Secret, demandes en cours) disparaît dans tous les cas.
  m15_k -n "$_E40_NS" delete certificate "$_E40_CERT" --ignore-not-found >/dev/null 2>&1 || true
  m15_k -n "$_E40_NS" delete secret "$_E40_CERT-tls" --ignore-not-found >/dev/null 2>&1 || true
  m15_oublier E40
}

resume_E40() {
  echo "Le certificat de répétition $_E40_NS/$_E40_CERT (joker *.$_M15_ZONE) n'est jamais délivré."
}

symptome_E40() {
  wb_symptome "Ticket INC-4246 — De : Karim Benali" \
    "Le joker apps-joker expire dans quelques semaines : j'ai voulu répéter son renouvellement avec" \
    "un certificat identique, $_E40_NS/$_E40_CERT. Il est toujours « False » après 20 minutes et je" \
    "ne veux pas découvrir le jour J que le vrai ne se renouvellera pas. Lucas a « mis à jour" \
    "l'émetteur » la semaine dernière, à la main ou par le dépôt, il ne sait plus." \
    "Trouve pourquoi, répare, et laisse le témoin se délivrer (ne le supprime pas)." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 15 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 15 E40 4 "$@"; }
fi
