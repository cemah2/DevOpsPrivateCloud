# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# break-S05.sh — F3-S05 « Mardi : les certificats ne se renouvellent plus »
#
# Témoin : Certificate wb-pannes/repetition-joker (*.apps.par1.medisphere.internal, ClusterIssuer
# step-ca-acme : un joker exige le défi DNS-01 RFC 2136 ; c'est la « répétition hebdomadaire » du
# renouvellement du joker de gw-par1), créé APRÈS l'injection : il ne devient jamais prêt.
# La racine et la CA intermédiaire de ca01 ne sont JAMAIS touchées ; le certificat réel apps-joker non plus.
#   1. PowerDNS (dns01) : la métadonnée TSIG-ALLOW-DNSUPDATE de la zone apps.par1.medisphere.internal
#      perd la clé certmanager-k8s (« nettoyage » de Lucas) ; les mises à jour de cert-manager sont
#      refusées (REFUSED/NOTAUTH), celles d'ExternalDNS passent toujours. Valeur d'origine sauvegardée sur
#      dns01 (/var/lib/workbook/F3-S05.meta), remise si la valeur injectée est toujours en place.
#   2. ClusterIssuer step-ca-acme : spec.acme.server pointé vers /acme/acme-v2/directory (« passage en
#      v2 » de Lucas, provisioner inexistant sur ca01) : l'enregistrement du compte ACME échoue, l'émetteur
#      passe à Ready=False. Objet sauvegardé (wb_k8s_sauver), remis s'il porte encore l'URL injectée.
#      Sans effet (variante suivante) si l'objet est réconcilié tout de suite par un outil.
#   3. Bordure (gw01 ET gw02, quelle que soit la maîtresse) : règle nftables insérée À CHAUD en tête de
#      la chaîne forward, qui jette 10.10.40.0/24 et 10.240.0.0/16 → 10.10.20.11:443 (commentaire
#      « PLAT-3305 durcissement provisoire ») : plus aucun dialogue ACME depuis les travailleurs.
#      /etc/nftables.conf n'est pas modifié. Annulation : suppression des seules règles qui portent ce
#      commentaire (jamais par numéro seul : un rechargement renumérote).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_f3-commun.sh
source "$WB_ROOT/finaux/F3-astreinte/corrige/pannes/_f3-commun.sh"

_S05_NS=wb-pannes
_S05_CERT=repetition-joker
_S05_ZONE=apps.par1.medisphere.internal
_S05_ISSUER=step-ca-acme
_S05_DNS="${WB_F3_DNS_PRIMAIRE:-dns01}"
_S05_GW="${WB_F3_PASSERELLES:-gw01 gw02}"
_S05_URL_FAUSSE="https://ca01.par1.medisphere.internal/acme/acme-v2/directory"
_S05_COMMENTAIRE="PLAT-3305 durcissement provisoire"

_s05_issuer_pret() {
  wb_kubectl get clusterissuer "$_S05_ISSUER" -o json 2>/dev/null |
    jq -e '.status.conditions[]? | select(.type == "Ready" and .status == "True")' >/dev/null 2>&1
}

# --- Témoin ----------------------------------------------------------------------------------------------

_s05_temoin() {
  wb_kubectl get namespace "$_S05_NS" >/dev/null 2>&1 || wb_kubectl create namespace "$_S05_NS" >/dev/null || return 1
  wb_kubectl -n "$_S05_NS" delete certificate "$_S05_CERT" --ignore-not-found >/dev/null 2>&1 || true
  wb_kubectl -n "$_S05_NS" delete secret "$_S05_CERT-tls" --ignore-not-found >/dev/null 2>&1 || true
  wb_kubectl apply -f - >/dev/null <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $_S05_CERT
  namespace: $_S05_NS
  annotations:
    medisphere.internal/demande: "Répétition hebdomadaire du renouvellement du joker de gw-par1 (RB-151)"
spec:
  secretName: $_S05_CERT-tls
  dnsNames:
    - "*.$_S05_ZONE"
  privateKey:
    algorithm: ECDSA
    size: 256
    rotationPolicy: Always
  issuerRef:
    group: cert-manager.io
    kind: ClusterIssuer
    name: $_S05_ISSUER
EOF
}
_s05_temoin_pret() {
  wb_kubectl -n "$_S05_NS" get certificate "$_S05_CERT" -o json 2>/dev/null |
    jq -e '.status.conditions[]? | select(.type == "Ready" and .status == "True")' >/dev/null 2>&1
}
_s05_temoin_retirer() {
  wb_kubectl -n "$_S05_NS" delete certificate "$_S05_CERT" --ignore-not-found >/dev/null 2>&1 || true
  wb_kubectl -n "$_S05_NS" delete secret "$_S05_CERT-tls" --ignore-not-found >/dev/null 2>&1 || true
}

# --- Variante 1 : TSIG retirée de la zone côté PowerDNS ------------------------------------------------

read -r -d '' _S05_AIDE_PDNS <<'AIDE' || true
pdnsutil() {
  if id pdns >/dev/null 2>&1 && [ "$(id -u)" = 0 ]; then runuser -u pdns -- /usr/bin/pdnsutil "$@"; else command pdnsutil "$@"; fi
}
# meta_lire — valeurs de TSIG-ALLOW-DNSUPDATE de la zone, séparées par des espaces.
meta_lire() {
  pdnsutil metadata get "$ZONE" TSIG-ALLOW-DNSUPDATE 2>/dev/null | sed -n 's/^TSIG-ALLOW-DNSUPDATE *= *//p' | tr ',' ' ' | xargs
}
AIDE

_s05_v1_poser() {
  { printf '%s\n' "$_S05_AIDE_PDNS"; cat <<'EOF'
command -v pdnsutil >/dev/null || exit 10
avant="$(meta_lire)"
case " $avant " in *" certmanager-k8s "*) ;; *) exit 10 ;; esac
apres="$(printf '%s\n' $avant | grep -vx certmanager-k8s | xargs)"
[ -f "$WB_DIR/F3-S05.meta" ] || printf '%s\n' "$avant" > "$WB_DIR/F3-S05.meta"
# shellcheck disable=SC2086
pdnsutil metadata set "$ZONE" TSIG-ALLOW-DNSUPDATE $apres >/dev/null || exit 1
journal "TSIG-ALLOW-DNSUPDATE de $ZONE : « $avant » → « $apres »"
EOF
  } | wb_exec "$_S05_DNS" ZONE="$_S05_ZONE" >/dev/null 2>&1
}
_s05_v1_defaire() {
  { printf '%s\n' "$_S05_AIDE_PDNS"; cat <<'EOF'
[ -f "$WB_DIR/F3-S05.meta" ] || exit 0
avant="$(cat "$WB_DIR/F3-S05.meta")"
cur="$(meta_lire)"
case " $cur " in
  *" certmanager-k8s "*) journal "annulation : certmanager-k8s déjà rétablie" ;;
  *)
    # shellcheck disable=SC2086
    pdnsutil metadata set "$ZONE" TSIG-ALLOW-DNSUPDATE $avant >/dev/null && journal "TSIG-ALLOW-DNSUPDATE rétablie : $avant" ;;
esac
rm -f "$WB_DIR/F3-S05.meta"
EOF
  } | wb_exec "$_S05_DNS" ZONE="$_S05_ZONE" >/dev/null 2>&1 || wb_avert "métadonnée de $_S05_ZONE à vérifier sur $_S05_DNS"
}

# --- Variante 2 : émetteur ACME vers un mauvais répertoire ---------------------------------------------

_s05_v2_poser() {
  local cur
  cur="$(wb_kubectl get clusterissuer "$_S05_ISSUER" -o jsonpath='{.spec.acme.server}' 2>/dev/null)" || return 10
  [[ "$cur" == https://* && "$cur" != "$_S05_URL_FAUSSE" ]] || return 10
  wb_k8s_sauver clusterissuer "$_S05_ISSUER"
  _f3p_ecrire S05 v2-url "$cur"
  wb_kubectl patch clusterissuer "$_S05_ISSUER" --type merge -p "{\"spec\":{\"acme\":{\"server\":\"$_S05_URL_FAUSSE\"}}}" >/dev/null || return 1
  _f3p_journal S05 "server de $_S05_ISSUER : $cur → $_S05_URL_FAUSSE"
  # Réconcilié aussitôt par un outil (Argo CD, autre) ? alors sans effet sur ce lab.
  sleep 60
  [[ "$(wb_kubectl get clusterissuer "$_S05_ISSUER" -o jsonpath='{.spec.acme.server}' 2>/dev/null)" == "$_S05_URL_FAUSSE" ]] || return 10
}
_s05_v2_defaire() {
  local orig
  orig="$(_f3p_lire S05 v2-url)"
  [[ -n "$orig" ]] || return 0
  if [[ "$(wb_kubectl get clusterissuer "$_S05_ISSUER" -o jsonpath='{.spec.acme.server}' 2>/dev/null)" == "$_S05_URL_FAUSSE" ]]; then
    wb_kubectl patch clusterissuer "$_S05_ISSUER" --type merge -p "{\"spec\":{\"acme\":{\"server\":\"$orig\"}}}" >/dev/null 2>&1 ||
      wb_k8s_restaurer || wb_avert "ClusterIssuer $_S05_ISSUER à remettre depuis plateforme/k8s"
    _f3p_journal S05 "server de $_S05_ISSUER rétabli"
  fi
  rm -rf -- "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/$WB_EX"
  _f3p_oublier S05 v2-url
}

# --- Variante 3 : la bordure jette l'ACME des travailleurs ---------------------------------------------

_s05_v3_poser() {
  local gw n=0
  for gw in $_S05_GW; do
    if wb_exec "$gw" REGLE="ip saddr { 10.10.40.0/24, 10.240.0.0/16 } ip daddr 10.10.20.11 tcp dport 443 counter drop comment \"$_S05_COMMENTAIRE\"" \
      >/dev/null 2>&1 <<'EOF'; then
nft list chain inet filter forward >/dev/null 2>&1 || exit 10
nft list chain inet filter forward | grep -qF "$(printf '%s' "$REGLE" | sed 's/.*comment //')" && exit 0
nft insert rule inet filter forward $REGLE || exit 1
journal "règle insérée en tête de inet filter forward : $REGLE"
EOF
      n=$((n + 1))
    else
      return 1
    fi
  done
  ((n > 0)) || return 10
}
_s05_v3_defaire() {
  local gw
  for gw in $_S05_GW; do
    wb_exec "$gw" COMMENTAIRE="$_S05_COMMENTAIRE" >/dev/null 2>&1 <<'EOF' || wb_avert "règle « $_S05_COMMENTAIRE » à vérifier sur $gw (nft -a list chain inet filter forward)"
for h in $(nft -a list chain inet filter forward 2>/dev/null | grep -F "comment \"$COMMENTAIRE\"" | sed -n 's/.*# handle \([0-9][0-9]*\)$/\1/p'); do
  nft delete rule inet filter forward handle "$h" && journal "règle « $COMMENTAIRE » retirée (handle $h)"
done
exit 0
EOF
  done
}

# --- Mécanique commune ------------------------------------------------------------------------------------

_f3p_S05_une() {
  local rc=0
  case "$1" in
    1) _s05_v1_poser || rc=$? ;;
    2) _s05_v2_poser || rc=$? ;;
    3) _s05_v3_poser || rc=$? ;;
  esac
  ((rc == 0)) || return "$rc"
  _s05_temoin || return 1
  # Une émission saine prend 1 à 3 min : 5 min sans certificat = panne constatée.
  sleep 300
  if _s05_temoin_pret; then
    _f3p_journal S05 "variante $1 : le témoin est quand même délivré (sans effet)"
    return 10
  fi
}
_f3p_S05_defaire() {
  case "$1" in
    1) _s05_v1_defaire ;;
    2) _s05_v2_defaire ;;
    3) _s05_v3_defaire ;;
  esac
}

_s05_injecter() {
  _f3p_preparer S05 || return 1
  _s05_issuer_pret || { echo "ClusterIssuer $_S05_ISSUER non prêt : $_F3P_REFUS" >&2; return 1; }
  wb_kubectl -n passerelles get certificate apps-joker -o json 2>/dev/null |
    jq -e '.status.conditions[]? | select(.type == "Ready" and .status == "True")' >/dev/null 2>&1 ||
    { echo "Le certificat passerelles/apps-joker n'est pas prêt : $_F3P_REFUS" >&2; return 1; }
  echo "Constat de l'effet sur un certificat témoin : 5 à 15 min…"
  _f3p_essayer S05 3 "$1"
}

panne_S05_v1() { _s05_injecter 1; }
panne_S05_v2() { _s05_injecter 2; }
panne_S05_v3() { _s05_injecter 3; }

verifier_S05() { ! _s05_temoin_pret && wb_kubectl -n "$_S05_NS" get certificate "$_S05_CERT" >/dev/null 2>&1; }

annuler_S05() {
  local v
  for v in 3 2 1; do _f3p_S05_defaire "$v" || true; done
  _s05_temoin_retirer
  _f3p_oublier S05 variante
}

resume_S05() { echo "les certificats ACME du cluster ne sont plus délivrés"; }

symptome_S05() {
  _f3p_symptome S05 INC-5905 "Ticket INC-5905 — De : Sophie Laurent — mardi 10 h 05" \
    "« La répétition hebdomadaire du renouvellement du joker (wb-pannes/repetition-joker, RB-151)" \
    "reste à False depuis ce matin, et cert-manager alerte. Le vrai joker *.apps est renouvelé" \
    "automatiquement dans quelques jours : si ce chemin est cassé, tous les services publiés par" \
    "gw-par1 tomberont à son échéance. Je veux savoir aujourd'hui ce qui bloque, et que la répétition" \
    "repasse au vert. Ne touche ni à la racine ni à l'intermédiaire de ca01. »" \
    "Temps cible : 1 h."
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F3 S05 3 "$@"; }
fi
