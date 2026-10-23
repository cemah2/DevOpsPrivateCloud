# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq, code Python et scripts distants entre apostrophes
# break-E40.sh — M24-E40 « Panne : SSH et sudo refusés sur les VMs »
#
# Quatre variantes, chacune sur UNE des briques de l'accès aux VMs (M24-E19, M24-E20) :
#   1. règle HBAC « hbac-support » désactivée dans l'annuaire (« ménage » de Lucas) : Nadia (support)
#      n'entre plus sur mon01 ni nbx01 ; la connexion est fermée juste après l'authentification par
#      certificat (pam_sss, étape account) ;
#   2. règle sudo « sudo-plateforme » restreinte à un seul hôte (ipa01, « pour essayer ») : Lucas entre
#      partout mais « sudo -g systemd-journal journalctl » est refusé sur toutes les VMs ;
#   3. SSSD hors service sur WB_M24_VM_SSSD (défaut nbx01) : /etc/sssd/sssd.conf rendu lisible par
#      tous (0644 : SSSD refuse alors de démarrer), cache invalidé (sss_cache -E), SSSD relancé (échec) ;
#      plus aucune personne de l'annuaire n'existe sur cette VM ; le compte local admin n'est pas touché ;
#   4. provisioner OIDC « keycloak » de step-ca (ca01, /etc/step-ca/config/ca.json) : le gabarit SSH met
#      le COURRIEL comme principal au lieu de preferred_username ; step-ca redémarré. Les certificats
#      émis ensuite ne correspondent plus à aucun compte (« no matching principal »).
# Rien ne touche le compte local admin des VMs, ses clés, le provisioner « admin » de step-ca, ni
# l'annuaire au-delà des deux règles nommées. Annulation : seulement si la marque est encore là.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m24-commun.sh
source "$WB_ROOT/modules/24-identite/corrige/pannes/_m24-commun.sh"

_E40_CA="${WB_M24_CA:-ca01}"
_E40_CA_JSON="${WB_M24_CA_JSON:-/etc/step-ca/config/ca.json}"
_E40_STEP_CA_URL="${WB_STEP_CA_URL:-https://ca01.par1.medisphere.internal}"
_E40_HBAC=hbac-support
_E40_SUDO=sudo-plateforme
_E40_HOTE_FAUX="${WB_M24_IPA_FQDN:-ipa01.par1.medisphere.internal}"

# --- Annuaire (cadre FreeIPA sur ipa01) --------------------------------------------------------------

read -r -d '' _E40_PY_HBAC <<'PY' || true
def actif(r):
    v = r.get("ipaenabledflag", [True])
    v = v[0] if isinstance(v, (list, tuple)) else v
    return str(v).upper() == "TRUE"
try:
    r = api.Command.hbacrule_show(P["regle"])["result"]
except errors.NotFound:
    sortie({"etat": "absente"}); sys.exit(0)
if P["action"] == "lire":
    sortie({"etat": "active" if actif(r) else "inactive"})
elif P["action"] == "desactiver":
    if not actif(r):
        sortie({"etat": "deja-inactive"})
    else:
        api.Command.hbacrule_disable(P["regle"])
        sortie({"etat": "desactivee"})
elif P["action"] == "activer":
    if actif(r):
        sortie({"etat": "deja-active"})
    else:
        api.Command.hbacrule_enable(P["regle"])
        sortie({"etat": "activee"})
PY

read -r -d '' _E40_PY_SUDO <<'PY' || true
try:
    r = api.Command.sudorule_show(P["regle"], all=True)["result"]
except errors.NotFound:
    sortie({"etat": "absente"}); sys.exit(0)
cat = [str(x) for x in r.get("hostcategory", [])]
hotes = [str(x) for x in r.get("memberhost_host", [])]
if P["action"] == "lire":
    sortie({"etat": "presente", "categorie": cat, "hotes": hotes})
elif P["action"] == "restreindre":
    if cat != ["all"] or hotes:
        sortie({"etat": "deja-restreinte", "categorie": cat, "hotes": hotes}); sys.exit(0)
    api.Command.sudorule_mod(P["regle"], hostcategory=None)
    api.Command.sudorule_add_host(P["regle"], host=[P["hote"]])
    sortie({"etat": "restreinte"})
elif P["action"] == "retablir":
    # Seulement si la règle porte encore EXACTEMENT la restriction posée par la panne.
    if cat or hotes != [P["hote"]]:
        sortie({"etat": "modifiee-depuis", "categorie": cat, "hotes": hotes}); sys.exit(0)
    api.Command.sudorule_remove_host(P["regle"], host=[P["hote"]])
    api.Command.sudorule_mod(P["regle"], hostcategory="all")
    sortie({"etat": "retablie"})
PY

_e40_hbac() { m24_ipa_py "$_E40_PY_HBAC" "$(jq -nc --arg r "$_E40_HBAC" --arg a "$1" '{regle: $r, action: $a}')" | tail -n 1; }
_e40_sudo() {
  m24_ipa_py "$_E40_PY_SUDO" "$(jq -nc --arg r "$_E40_SUDO" --arg a "$1" --arg h "$_E40_HOTE_FAUX" '{regle: $r, action: $a, hote: $h}')" | tail -n 1
}

# _e40_sudo_refuse — sur la VM témoin, la règle de Lucas ne s'applique plus (cache de SSSD invalidé).
_e40_sudo_refuse() {
  m24_ssh "$_M24_VM_SSSD" 'sss_cache -E >/dev/null 2>&1 || true; sudo -l -U lucas.martin 2>&1' | grep -qiE 'not allowed|n.est pas autoris'
}

# --- SSSD sur la VM témoin --------------------------------------------------------------------------

_e40_sssd_casser() {
  m24_wb_exec "$_M24_VM_SSSD" <<'EOF'
f=/etc/sssd/sssd.conf
[ -f "$f" ] || exit 10
systemctl is-active --quiet sssd || exit 10
stat -c %a "$f" > "$WB_DIR/$WB_EX.mode"
sss_cache -E >/dev/null 2>&1 || true
chmod 0644 "$f"
systemctl restart sssd >/dev/null 2>&1 || true
sleep 3
if systemctl is-active --quiet sssd; then
  # Version de SSSD qui accepterait 0644 : on en reste à l'arrêt du service.
  systemctl stop sssd
  echo arret > "$WB_DIR/$WB_EX.methode"
else
  echo permissions > "$WB_DIR/$WB_EX.methode"
fi
journal "sssd.conf en 0644, cache invalidé, sssd relancé ($(cat "$WB_DIR/$WB_EX.methode"))"
EOF
}

_e40_sssd_reparer() {
  m24_wb_exec "$_M24_VM_SSSD" <<'EOF'
f=/etc/sssd/sssd.conf
if [ -f "$WB_DIR/$WB_EX.mode" ] && [ "$(stat -c %a "$f" 2>/dev/null)" = 644 ]; then
  chmod "$(cat "$WB_DIR/$WB_EX.mode")" "$f"
fi
systemctl is-active --quiet sssd || systemctl start sssd || true
rm -f "$WB_DIR/$WB_EX.mode" "$WB_DIR/$WB_EX.methode"
journal "annulation : droits de sssd.conf et service sssd rétablis si nécessaire"
EOF
}

_e40_sssd_panne() {
  m24_ssh "$_M24_VM_SSSD" '! systemctl is-active --quiet sssd && ! getent -s sss passwd lucas.martin >/dev/null && echo panne' | grep -qx panne
}

# --- step-ca --------------------------------------------------------------------------------------------

# Filtre jq : remplace le principal du gabarit SSH du provisioner keycloak (aller : courriel ; retour).
_E40_JQ_ALLER='(.authority.provisioners[] | select(.name == "keycloak" and .type == "OIDC") | .options.ssh.template) |=
  sub("(?<a>\"principals\"\\s*:\\s*\\[\\s*\\{\\{\\s*toJson\\s+)\\.Token\\.preferred_username"; "\(.a).Token.email")'
_E40_JQ_RETOUR='(.authority.provisioners[] | select(.name == "keycloak" and .type == "OIDC") | .options.ssh.template) |=
  sub("(?<a>\"principals\"\\s*:\\s*\\[\\s*\\{\\{\\s*toJson\\s+)\\.Token\\.email"; "\(.a).Token.preferred_username")'

# _e40_ca_modifier 'filtre jq' — applique le filtre à ca.json (sauvegarde une fois), redémarre step-ca ;
# remet le fichier et redémarre si step-ca ne repart pas. Code 10 : rien à changer.
_e40_ca_modifier() {
  m24_wb_exec "$_E40_CA" "F=$_E40_CA_JSON" "FILTRE=$1" <<'EOF'
[ -f "$F" ] || exit 10
t="$(mktemp)"
jq "$FILTRE" "$F" > "$t" || { rm -f "$t"; exit 10; }
if cmp -s "$t" "$F"; then rm -f "$t"; exit 10; fi
sauver "$F"
cp "$F" "$WB_DIR/$WB_EX.ca-avant.json"
cat "$t" > "$F"
rm -f "$t"
systemctl restart step-ca
sleep 5
if ! systemctl is-active --quiet step-ca; then
  cat "$WB_DIR/$WB_EX.ca-avant.json" > "$F"
  systemctl restart step-ca || true
  rm -f "$WB_DIR/$WB_EX.ca-avant.json"
  journal "step-ca ne repart pas avec la modification : fichier remis"
  exit 1
fi
rm -f "$WB_DIR/$WB_EX.ca-avant.json"
journal "ca.json modifié (gabarit SSH du provisioner keycloak), step-ca redémarré"
EOF
}

# _e40_principal_courriel — la configuration PUBLIQUE de step-ca annonce le courriel comme principal.
_e40_principal_courriel() {
  curl -sf --max-time 20 --cacert "$_M24_RACINE" "$_E40_STEP_CA_URL/provisioners?limit=100" 2>/dev/null |
    jq -e '[.provisioners[] | select(.name == "keycloak") | .options.ssh.template // ""] | any(test("principals\"\\s*:\\s*\\[\\s*\\{\\{\\s*toJson\\s+\\.Token\\.email"))' >/dev/null 2>&1
}

_e40_ca_nettoyer() {
  m24_wb_exec "$_E40_CA" <<'EOF'
m="$WB_DIR/$WB_EX.manifeste"
if [ -f "$m" ]; then
  while IFS="$(printf '\t')" read -r src dst; do [ "$dst" = ABSENT ] || rm -f -- "$dst"; done < "$m"
  rm -f "$m"
fi
EOF
}

# --- Variantes ---------------------------------------------------------------------------------------

_m24E40_une() {
  local n="$1" r rc=0
  m24_ecrire E40 variante "$n"
  case "$n" in
    1)
      m24_sain_hote "$_M24_IPA" || return 1
      r="$(_e40_hbac lire)"
      [[ "$(jq -r '.etat // ""' <<<"$r" 2>/dev/null)" == active ]] || return 10
      _e40_hbac desactiver | grep -q '"desactivee"' || return 1
      ;;
    2)
      m24_sain_hote "$_M24_IPA" || return 1
      m24_sain_hote "$_M24_VM_SSSD" || return 1
      r="$(_e40_sudo lire)"
      jq -e '.etat == "presente" and .categorie == ["all"] and (.hotes | length) == 0' >/dev/null 2>&1 <<<"$r" || return 10
      _e40_sudo restreindre | grep -q '"restreinte"' || return 1
      ;;
    3)
      m24_sain_hote "$_M24_VM_SSSD" || return 1
      _e40_sssd_casser || rc=$?
      ((rc == 0)) || return "$rc"
      ;;
    4)
      m24_sain_hote "$_E40_CA" || return 1
      _e40_ca_modifier "$_E40_JQ_ALLER" || rc=$?
      ((rc == 0)) || return "$rc"
      ;;
  esac
  m24_journal E40 "variante $n posée"
}

verifier_E40() {
  case "$WB_VAR" in
    1) [[ "$(_e40_hbac lire | jq -r '.etat // ""' 2>/dev/null)" == inactive ]] ;;
    2) m24_attendre 60 _e40_sudo_refuse ;;
    3) _e40_sssd_panne ;;
    4) m24_attendre 30 _e40_principal_courriel ;;
    *) return 1 ;;
  esac
}

panne_E40_v1() { m24_essayer E40 4 1; }
panne_E40_v2() { m24_essayer E40 4 2; }
panne_E40_v3() { m24_essayer E40 4 3; }
panne_E40_v4() { m24_essayer E40 4 4; }

annuler_E40() {
  local v
  v="$(m24_lire E40 variante)"
  case "$v" in
    1)
      # Réactivée seulement si elle est encore désactivée (une réparation de l'apprenant reste).
      _e40_hbac activer >/dev/null 2>&1 || wb_avert "règle HBAC $_E40_HBAC non réactivée (ipa hbacrule-enable $_E40_HBAC)"
      ;;
    2)
      _e40_sudo retablir >/dev/null 2>&1 || wb_avert "règle sudo $_E40_SUDO non rétablie (ipa sudorule-show $_E40_SUDO)"
      m24_ssh "$_M24_VM_SSSD" 'sss_cache -E' >/dev/null 2>&1 || true
      ;;
    3)
      _e40_sssd_reparer >/dev/null 2>&1 || wb_avert "$_M24_VM_SSSD : droits de /etc/sssd/sssd.conf (0600) et service sssd à vérifier"
      ;;
    4)
      if _e40_principal_courriel; then
        _e40_ca_modifier "$_E40_JQ_RETOUR" >/dev/null 2>&1 || wb_avert "$_E40_CA : gabarit du provisioner keycloak non rétabli (rejoue le rôle step_ca)"
      fi
      _e40_ca_nettoyer >/dev/null 2>&1 || true
      ;;
  esac
  m24_oublier E40 variante
  m24_journal E40 "annulation"
}

resume_E40() { echo "Des personnes de l'annuaire n'entrent plus sur les VMs, ou n'y ont plus sudo ; le compte local admin passe."; }

symptome_E40() {
  local qui detail
  case "$WB_VAR" in
    1)
      qui="Nadia Roussel"
      detail="Je fais « step ssh login » (OK, OTP compris), puis « ssh nadia.roussel@mon01… » : la connexion se ferme tout de suite, sans message. Pareil sur nbx01. Hier, ça marchait."
      ;;
    2)
      qui="Lucas Martin"
      detail="J'entre sur les VMs sans problème, mais « sudo -g systemd-journal journalctl -u ssh » me répond que je n'ai pas le droit, sur git01, mon01, nbx01… partout."
      ;;
    3)
      qui="Karim Benali"
      detail="Sur nbx01 seulement : « ssh karim.benali@nbx01… » est refusé (Permission denied), alors que mon01 et git01 marchent avec le même certificat. Le compte admin, lui, entre."
      ;;
    *)
      qui="Karim Benali"
      detail="« step ssh login » me donne bien un certificat, mais plus aucune VM ne l'accepte : « Permission denied (publickey) », pour moi comme pour Lucas. Avec ms-ssh-cert (compte admin), tout passe."
      ;;
  esac
  wb_symptome "Ticket INC-5140 — De : $qui" \
    "$detail" \
    "Lucas a « fait un peu de ménage » dans les accès hier soir." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 24 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 24 E40 4 "$@"; }
fi
