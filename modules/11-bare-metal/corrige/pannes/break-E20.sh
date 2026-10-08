# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E20.sh — M11-E20 « Panne : iPXE s'arrête en chemin »
#
# Variantes (toutes sur pxe01) :
#   1. boot.ipxe : la première ligne « #!ipxe » devient « #! ipxe » (« retouche » à la main) →
#      iPXE télécharge le script mais ne le reconnaît plus (« Exec format error ») ;
#   2. scripts par MAC (racine/ipxe/mac-*.ipxe) passés en 0600 root:root (« rendu lancé en root
#      avec un umask restrictif ») → nginx répond 403, iPXE « Permission denied » après le
#      téléchargement réussi de boot.ipxe ;
#   3. certificat de nginx remplacé par un certificat de même clé, signé par une « MédiSphère CA
#      provisoire » éphémère (« restauration d'une ancienne configuration ») → iPXE refuse la
#      chaîne (sa seule racine est MédiSphère Root CA) ; un client sans vérification passerait.
#      Sans effet si pxe01 n'est pas en HTTPS (M11-E13 non fait) : variante suivante.
# Sauvegardes : /var/lib/workbook/M11-E20.* sur pxe01.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m11-commun.sh
source "$WB_ROOT/modules/11-bare-metal/corrige/pannes/_m11-commun.sh"

# _e20_code CHEMIN — code de sortie de curl en HTTPS vérifié depuis adm01 (0 = 2xx, 22 = 4xx/5xx,
# 60 = certificat refusé, 7 = connexion refusée).
_e20_code() {
  local rc=0
  curl -sS --fail -o /dev/null --max-time 10 --resolve "$_M11_PXE_FQDN:443:$_M11_PXE_IP" \
    "https://$_M11_PXE_FQDN$1" 2>/dev/null || rc=$?
  printf '%s\n' "$rc"
}

# _e20_premier_mac — chemin (URL) d'un script par MAC servi par pxe01.
_e20_premier_mac() {
  m11_wb_exec pxe01 2>/dev/null <<'EOF'
r="$(nginx_racine)"
f="$(ls "$r"/ipxe/mac-*.ipxe 2>/dev/null | head -n 1)"
[ -n "$f" ] && printf '/ipxe/%s\n' "$(basename "$f")"
EOF
}

# _e20_entete_ok — boot.ipxe servi commence par « #!ipxe ».
_e20_entete_ok() {
  [[ "$(curl -sS --max-time 10 --resolve "$_M11_PXE_FQDN:443:$_M11_PXE_IP" \
    "https://$_M11_PXE_FQDN/boot.ipxe" 2>/dev/null | head -n 1)" == "#!ipxe" ]]
}

_e20_precondition() {
  if [[ "$(_e20_code /boot.ipxe)" != 0 ]] || ! _e20_entete_ok; then
    wb_avert "pxe01 ne sert pas déjà boot.ipxe en HTTPS vérifié : lab/bin/check 11 20"
    return 1
  fi
  local m
  m="$(_e20_premier_mac)"
  if [[ -z "$m" || "$(_e20_code "$m")" != 0 ]]; then
    wb_avert "pxe01 ne sert pas déjà de script par MAC (ipxe/mac-*.ipxe) : lab/bin/check 11 20"
    return 1
  fi
  m11_ecrire E20 mac "$m"
}

_mE20_une() {
  local n="$1" rc=0
  case "$n" in
    1)
      m11_wb_exec pxe01 >/dev/null <<'EOF' || rc=$?
f="$(nginx_racine)/boot.ipxe"
subst "$f" '\A#!ipxe' '#! ipxe' || exit $?
journal "$f : en-tête « #!ipxe » remplacé par « #! ipxe »"
EOF
      ;;
    2)
      m11_wb_exec pxe01 >/dev/null <<'EOF' || rc=$?
r="$(nginx_racine)"
n=0
for f in "$r"/ipxe/mac-*.ipxe; do
  [ -f "$f" ] || continue
  sauver "$f"
  chown root:root "$f"
  chmod 0600 "$f"
  noter_injecte "$f"
  n=$((n + 1))
done
[ "$n" -gt 0 ] || exit 10
journal "$n script(s) par MAC passés en 0600 root:root"
EOF
      ;;
    3)
      m11_wb_exec pxe01 FQDN="$_M11_PXE_FQDN" >/dev/null <<'EOF' || rc=$?
crt="$(nginx_certificat)"
key="$(nginx_cle)"
[ -n "$crt" ] && [ -f "$crt" ] && [ -n "$key" ] && [ -f "$key" ] || exit 10
t="$(mktemp -d)"
openssl req -utf8 -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
  -subj "/O=MédiSphère/CN=MédiSphère CA provisoire" -keyout "$t/ca.key" -out "$t/ca.crt" >/dev/null 2>&1 || exit 1
openssl req -new -key "$key" -subj "/CN=$FQDN" -out "$t/req.csr" >/dev/null 2>&1 || exit 1
printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n' "$FQDN" >"$t/ext"
openssl x509 -req -in "$t/req.csr" -CA "$t/ca.crt" -CAkey "$t/ca.key" -CAcreateserial -days 365 \
  -extfile "$t/ext" -out "$t/feuille.crt" >/dev/null 2>&1 || exit 1
sauver "$crt"
cat "$t/feuille.crt" "$t/ca.crt" >"$crt"
noter_injecte "$crt"
rm -rf "$t"
nginx -t >/dev/null 2>&1 && systemctl reload nginx
journal "$crt : certificat signé par une « MédiSphère CA provisoire » éphémère (CA détruite)"
EOF
      ;;
  esac
  ((rc == 0)) || return "$rc"
  sleep 2
  verifier_E20_n "$n" || { _e20_defaire; return 10; }
}

verifier_E20_n() {
  case "$1" in
    1) [[ "$(_e20_code /boot.ipxe)" == 0 ]] && ! _e20_entete_ok ;;
    2) [[ "$(_e20_code "$(m11_lire E20 mac)")" == 22 ]] ;;
    3) [[ "$(_e20_code /boot.ipxe)" == 60 ]] ;;
    *) return 1 ;;
  esac
}

_e20_defaire() {
  m11_wb_exec pxe01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pxe01 : nginx -t ; ls -l de la racine servie"
recharger=0
if [ -f "$WB_DIR/$WB_EX.subst" ]; then
  defaire_subst >/dev/null
fi
if [ -f "$WB_DIR/$WB_EX.manifeste" ]; then
  garder_reparations
  restaurer_fichiers
  recharger=1
fi
if [ "$recharger" = 1 ] && nginx -t >/dev/null 2>&1; then systemctl reload nginx; fi
EOF
  m11_effacer E20 mac
}

_e20_injecter() {
  _e20_precondition || return 1
  m11_essayer E20 3 "$1"
}

panne_E20_v1() { _e20_injecter 1; }
panne_E20_v2() { _e20_injecter 2; }
panne_E20_v3() { _e20_injecter 3; }

verifier_E20() { verifier_E20_n "${WB_VAR:-0}"; }

annuler_E20() { _e20_defaire; }

resume_E20() {
  echo "Les serveurs du VLAN 60 chargent iPXE puis s'arrêtent sur une erreur avant l'installateur."
}

symptome_E20() {
  local -a l
  case "${WB_VAR:-0}" in
    1) l=("Plus aucun serveur ne s'installe : la console montre iPXE qui obtient son adresse,"
      "télécharge https://pxe01.par1.medisphere.internal/boot.ipxe (« ok »), puis s'arrête sur"
      "une erreur avec un code https://ipxe.org/… et rend la main au micrologiciel."
      "Quelqu'un a « juste ajouté un commentaire » dans un fichier ce matin.") ;;
    2) l=("Plus aucun serveur ne s'installe : iPXE télécharge boot.ipxe sans problème, affiche"
      "la ligne de bienvenue avec la MAC de la machine, puis échoue sur le téléchargement"
      "suivant (« Permission denied » et un code https://ipxe.org/…) et passe au disque."
      "Le rendu des fichiers a été relancé hier soir, sans erreur.") ;;
    *) l=("Plus aucun serveur ne s'installe : iPXE obtient son adresse puis échoue dès le"
      "téléchargement de https://pxe01.par1.medisphere.internal/boot.ipxe (« Permission denied »,"
      "code https://ipxe.org/…). Pourtant un collègue a ouvert la même adresse dans son"
      "navigateur après avoir accepté un avertissement. Une ancienne configuration de pxe01"
      "a été restaurée hier.") ;;
  esac
  wb_symptome "Ticket INC-3842 — De : Nadia Roussel" "${l[@]}" "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 11 20"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 11 E20 3 "$@"; }
fi
