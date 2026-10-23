# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq, awk et scripts distants entre apostrophes
# _f5-exercice.sh — fonctions PROPRES à l'exercice (phases 3 et 4 du final F5 : check-S08 à check-S14)
# et aux contrôles préalables des pannes break-S08, break-S09, break-S10. Sourcé, jamais lancé seul.
# Préfixe : _f5e_. Il source _f5-par2.sh (fonctions de base _f5p_ : dépôts, SSH, kubectl de k8s-par2,
# DNS, S3, reg02) : une seule implémentation par fonction, mêmes variables WB_F5_* et mêmes défauts.
#
# Lecture seule :
#   - Kubernetes : « kube » (compte wb-checks de k8s-par1) et _f5p_kube (compte wb-checks de k8s-par2) ;
#   - GitLab en GET (jeton des checks) quand PAR1 est joignable ; pendant le PRA (S09 à S11, checks lancés
#     depuis adm02), les documents sont lus dans le miroir de plateforme/medisphere sur adm02 (branche
#     main), avec repli sur le clone de travail (WB_F5_DEPOT_PAR2, HEAD) ;
#   - SSH + « sudo -n » en LECTURE sur adm02, dns03, s3-02, gw01/gw02 (cat, systemctl is-active, nft list,
#     chronyc tracking) ; root sur pbs01 (= hp01) pour « qm config » et « pvesh get » ;
#   - DNS, HTTP(S) en GET.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée.
#
# Variables (lab/lab.env ; défauts ci-dessous). Celles de _f5-par2.sh, plus :
#   WB_F5_EXERCICE          nom de l'exercice (2026-exercice-1) : docs/pra/exercices/<nom>/, docs/pra/mesures/<nom>/
#   WB_F5_DEPOT_PAR2        clone de travail de plateforme/medisphere sur adm02 (défaut ~/medisphere de admin)
#   WB_F5_SONDE_CSV         mesures de ms-sonde-pra sur adm02 (/var/lib/ms-sonde-pra/mesures.csv)
#   WB_F5_RTO_MEDIAGENDA_MIN, WB_F5_RTO_MEDIDOC_MIN, WB_F5_RTO_RDV_MIN, WB_F5_RPO_MEDIAGENDA_MIN
#   WB_F5_PROM_PAR2_URL, WB_F5_AM_PAR2_URL, WB_F5_MAILPIT_PAR2_URL (supervision minimale de PAR2, S11, S14)
#   WB_F5_COUPURE_RETOUR_MAX_MIN (S12)

# shellcheck source=_f5-par2.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-par2.sh"

_f5e_miroir_doc="$_f5p_miroirs/$_f5p_projet_doc.git"
_f5e_depot_par2="${WB_F5_DEPOT_PAR2:-\$HOME/medisphere}"
_f5e_exercice="${WB_F5_EXERCICE:-2026-exercice-1}"
_f5e_csv_chemin="${WB_F5_SONDE_CSV:-/var/lib/ms-sonde-pra/mesures.csv}"
_f5e_adm02="admin@$_f5p_adm02_hote"
_f5e_dns03="admin@$_f5p_dns03_hote"
_f5e_s302="admin@$_f5p_s302_hote"
_f5e_hp01="root@$_f5p_hp01_hote"
_f5e_prom2="${WB_F5_PROM_PAR2_URL:-http://adm02.par2.medisphere.internal:9090}"
_f5e_am2="${WB_F5_AM_PAR2_URL:-http://adm02.par2.medisphere.internal:9093}"
_f5e_mailpit2="${WB_F5_MAILPIT_PAR2_URL:-http://adm02.par2.medisphere.internal:8025}"
# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
{
  _f5e_rto_mediagenda="${WB_F5_RTO_MEDIAGENDA_MIN:-240}"
  _f5e_rto_medidoc="${WB_F5_RTO_MEDIDOC_MIN:-480}"
  _f5e_rto_rdv="${WB_F5_RTO_RDV_MIN:-480}"
  _f5e_rpo_mediagenda="${WB_F5_RPO_MEDIAGENDA_MIN:-15}"
  _f5e_coupure_max="${WB_F5_COUPURE_RETOUR_MAX_MIN:-15}"
}

# Faits figés (PLAN §4.5, §4.15) — noms globaux, Clusters CNPG, hôtes.
# shellcheck disable=SC2034
{
  _F5E_NOMS=(mediagenda.medisphere.internal medidoc.medisphere.internal rdv.medisphere.internal)
  _F5E_NS_PROD=mediagenda-prod
  _F5E_CNPG_PAR1=mediagenda-db
  _F5E_CNPG_PAR2=mediagenda-db-par2
  _F5E_NOEUD_PAR2=k8s-par2-n01
  _F5E_VMID_BAO_PAR2=1055
  _F5E_INC=INC-6109
}

# Chemin de « sonde » HTTP par nom global (réponse 2xx attendue, en-tête X-MediSphere-Site posé par la route).
_f5e_url() {
  case "$1" in
    mediagenda.*) echo "https://$1/sante" ;;
    medidoc.*) echo "https://$1/healthz" ;;
    *) echo "https://$1/" ;;
  esac
}

# ---------------------------------------------------------------------------------------------
# Hôtes (exécution locale ou SSH : _f5p_sur de _f5-par2.sh)
# ---------------------------------------------------------------------------------------------

# _f5e_lire HÔTE FICHIER — contenu d'un fichier, lisible directement ou par « sudo -n cat ».
_f5e_lire() {
  _f5p_sur "$1" "cat '$2' 2>/dev/null || sudo -n cat '$2'"
}

# _f5e_t0 — T0 du sinistre (secondes depuis l'époque), lu sur adm02 puis sur gw01 ; vide si absent.
# Fichier /var/lib/workbook/f5-t0 écrit par break-S09 : lignes T0_EPOCH=… et T0_ISO=….
_F5E_T0=""
_f5e_t0() {
  local c h
  if [[ -n "$_F5E_T0" ]]; then echo "$_F5E_T0"; return 0; fi
  for h in "$_f5e_adm02" gw01; do
    c="$(_f5e_lire "$h" /var/lib/workbook/f5-t0 2>/dev/null)" || continue
    _F5E_T0="$(sed -n 's/^T0_EPOCH=\([0-9][0-9]*\)$/\1/p' <<<"$c" | head -n1)"
    if [[ -n "$_F5E_T0" ]]; then echo "$_F5E_T0"; return 0; fi
  done
  return 1
}

# _f5e_levee — heure de levée de l'isolement (secondes), écrite sur gw01 par « break F5 09 --annuler ».
_f5e_levee() {
  _f5e_lire gw01 /var/lib/workbook/f5-levee 2>/dev/null | sed -n 's/^LEVEE_EPOCH=\([0-9][0-9]*\)$/\1/p' | head -n1
}

# ---------------------------------------------------------------------------------------------
# Kubernetes
# ---------------------------------------------------------------------------------------------

# _f5e_kq1 'filtre jq' ARGS… (k8s-par1) / _f5e_kq2 'filtre jq' ARGS… (k8s-par2) — « get … -o json » puis jq -e.
_f5e_kq1() {
  local f="$1" j
  shift
  j="$(kube get "$@" -o json 2>/dev/null)" || return 1
  jq -e "$f" >/dev/null 2>&1 <<<"$j"
}
_f5e_kq2() {
  local f="$1" j
  shift
  j="$(_f5p_kube get "$@" -o json 2>/dev/null)" || return 1
  jq -e "$f" >/dev/null 2>&1 <<<"$j"
}

# Rôle d'un Cluster CNPG en topologie distribuée : « primaire » si spec.replica.primary vaut son nom (ou
# si la section replica est absente/désactivée), « replique » sinon.
_F5E_JQ_PRIMAIRE='(.spec.replica == null) or (.spec.replica.enabled == false)
  or ((.spec.replica.primary // "") == (.spec.replica.self // .metadata.name))'
_F5E_JQ_SAIN='(.status.phase // "") == "Cluster in healthy state"'
_F5E_JQ_NON_CLOTURE='((.metadata.annotations["cnpg.io/fencedInstances"] // "[]") | fromjson? // [] | length) == 0'

# ---------------------------------------------------------------------------------------------
# GitLab (lecture) : étiquette
# ---------------------------------------------------------------------------------------------

# Lecture des fichiers et de l'arborescence : _f5p_fichier, _f5p_arbre, _f5p_doc_motif (_f5-par2.sh).

_f5e_etiquette() {
  gitlab_api "projects/$(_f5p_enc "$_f5p_projet_doc")/repository/tags/$(_f5p_enc "$1")" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------------------------
# Documentation pendant le PRA : clone de travail sur adm02 (commits de la branche courante)
# ---------------------------------------------------------------------------------------------

# Source : le miroir de plateforme/medisphere sur adm02 (branche main, où l'équipe pousse pendant le PRA,
# RB-350) ; repli sur le clone de travail (HEAD) pour les fichiers absents du miroir.
# _f5e_pra_fichiers [DOSSIER] — union des fichiers suivis sous DOSSIER.
_f5e_pra_fichiers() {
  local d="${1:-$_f5p_doc_dir}"
  _f5p_sur "$_f5e_adm02" "{ git --git-dir='$_f5e_miroir_doc' ls-tree -r --name-only main -- '$d' 2>/dev/null; \
    git -C $_f5e_depot_par2 ls-tree -r --name-only HEAD -- '$d' 2>/dev/null; } | sort -u" 2>/dev/null
}
# _f5e_pra_contenu CHEMIN — version du miroir (main), sinon du clone (HEAD).
_f5e_pra_contenu() {
  _f5p_sur "$_f5e_adm02" "git --git-dir='$_f5e_miroir_doc' show 'main:$1' 2>/dev/null || git -C $_f5e_depot_par2 show 'HEAD:$1'" 2>/dev/null
}
# _f5e_doc_pra DOSSIER MOTIF_NOM REGEX… — comme _f5p_doc_motif, mais lu sur adm02 (miroir, sinon clone).
_f5e_doc_pra() {
  local d="$1" motif="$2" f c m ok
  shift 2
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    c="$(_f5e_pra_contenu "$f")" || continue
    ok=1
    for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || { ok=0; break; }; done
    if ((ok)); then printf '%s\n' "$f"; return 0; fi
  done < <(_f5e_pra_fichiers "$d")
  return 1
}

# _f5e_journal_pra [source=pra|gitlab] — lignes de main courante qui citent INC-6109 (docs/pra/journal/) ;
# « pra » : lues sur adm02 (miroir, sinon clone) ; « gitlab » : lues par _f5p_fichier (GitLab ou miroir).
_f5e_journal_pra() {
  local f
  if [[ "${1:-pra}" == pra ]]; then
    while IFS= read -r f; do
      [[ "$f" == "$_f5p_doc_dir"/journal/*.md ]] || continue
      _f5e_pra_contenu "$f" | grep -E "^- [0-2][0-9]:[0-5][0-9] $_F5E_INC \[" || true
    done < <(_f5e_pra_fichiers "$_f5p_doc_dir/journal")
  else
    while IFS= read -r f; do
      [[ "$f" == *.md ]] || continue
      _f5p_fichier "$_f5p_projet_doc" "$f" 2>/dev/null | grep -E "^- [0-2][0-9]:[0-5][0-9] $_F5E_INC \[" || true
    done < <(_f5p_arbre "$_f5p_projet_doc" "$_f5p_doc_dir/journal")
  fi
}

# ---------------------------------------------------------------------------------------------
# Mesures de la sonde ms-sonde-pra (adm02) : horodatage_utc,cible,code_http,latence_ms,site
# ---------------------------------------------------------------------------------------------

_F5E_CSV=""
_f5e_csv() {
  if [[ -z "$_F5E_CSV" ]]; then
    _F5E_CSV="$(_f5e_lire "$_f5e_adm02" "$_f5e_csv_chemin" 2>/dev/null)" || return 1
  fi
  [[ -n "$_F5E_CSV" ]] && printf '%s\n' "$_F5E_CSV"
}

# _f5e_csv_epoch — même CSV avec une première colonne en secondes (lignes illisibles ignorées).
_f5e_csv_epoch() {
  local l t
  _f5e_csv | while IFS= read -r l; do
    t="${l%%,*}"
    [[ "$t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] || continue
    t="$(date -u -d "$t" +%s 2>/dev/null)" || continue
    printf '%s,%s\n' "$t" "${l#*,}"
  done
}

# _f5e_rto NOM DEPUIS — minutes entre DEPUIS (epoch) et la première mesure 2xx servie par par2 pour NOM.
_f5e_rto() {
  _f5e_csv_epoch | awk -F, -v nom="$1" -v t0="$2" '
    $1 >= t0 && index($2, nom) > 0 && $3 ~ /^2[0-9][0-9]$/ && $5 ~ /par2/ { printf "%d\n", int(($1 - t0 + 59) / 60); exit }'
}

# _f5e_coupure_max NOM DEPUIS — plus longue suite de mesures non 2xx (minutes) pour NOM après DEPUIS.
_f5e_coupure_max() {
  _f5e_csv_epoch | awk -F, -v nom="$1" -v t0="$2" -v maintenant="$(date +%s)" '
    $1 >= t0 && index($2, nom) > 0 {
      if ($3 ~ /^2[0-9][0-9]$/) { if (debut) { d = $1 - debut; if (d > max) max = d; debut = 0 } }
      else if (!debut) { debut = $1 }
      n++
    }
    END { if (debut) { d = maintenant - debut; if (d > max) max = d } ; if (n) printf "%d\n", int((max + 59) / 60) }'
}

# _f5e_site NOM — valeur de l'en-tête X-MediSphere-Site renvoyé par le nom global (réponse 2xx exigée).
_f5e_site() {
  local u r
  u="$(_f5e_url "$1")"
  r="$(curl -s -o /dev/null -D - --max-time "$WB_TIMEOUT" "$u" 2>/dev/null)" || return 1
  grep -Eq '^HTTP/[0-9.]+ 2[0-9][0-9]' <<<"$r" || return 1
  sed -n 's/^[Xx]-[Mm]edi[Ss]phere-[Ss]ite:[[:space:]]*\([a-z0-9]*\).*/\1/p' <<<"$r" | head -n1
}

# ---------------------------------------------------------------------------------------------
# PAR2 prêt (contrôle préalable des pannes S08, S09 ; contrôles de S08 et S12)
# ---------------------------------------------------------------------------------------------

# Réplication des objets : _f5p_filersync_ok (_f5-par2.sh).
_f5e_p_noeud2() {
  local j
  j="$(_f5p_kube get node "$_F5E_NOEUD_PAR2" -o json 2>/dev/null)" || { echo "API de k8s-par2 injoignable (compte des checks)"; return 1; }
  jq -e '([.status.conditions[]? | select(.type == "Ready")][0].status == "True") and ((.spec.unschedulable // false) | not)' \
    >/dev/null 2>&1 <<<"$j" || { echo "$_F5E_NOEUD_PAR2 n'est pas Ready ou n'est pas planifiable"; return 1; }
}
_f5e_p_bao2() {
  local c
  c="$(_f5p_sur "$_f5e_hp01" "qm config $_F5E_VMID_BAO_PAR2" 2>/dev/null)" || { echo "VM $_F5E_VMID_BAO_PAR2 (bao-par2) introuvable sur hp01"; return 1; }
  if grep -q '^lock:' <<<"$c"; then echo "VM $_F5E_VMID_BAO_PAR2 (bao-par2) verrouillée ($(grep '^lock:' <<<"$c"))"; return 1; fi
}
_f5e_p_dns03() {
  [[ -n "$(_f5p_soa medisphere.internal "$_f5p_dns03")" ]] \
    || { echo "dns03 ne répond pas pour la zone medisphere.internal"; return 1; }
}
_f5e_p_reg02() {
  local c
  c="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "$_f5p_reg02_url/v2/" 2>/dev/null)" || c=""
  [[ "$c" == 200 || "$c" == 401 ]] || { echo "reg02 ne répond pas sur /v2/ (HTTP ${c:-aucune réponse})"; return 1; }
}
_f5e_p_cnpg2_replique() {
  _f5e_kq2 "($_F5E_JQ_PRIMAIRE | not) and $_F5E_JQ_SAIN" cluster "$_F5E_CNPG_PAR2" -n "$_F5E_NS_PROD" \
    || { echo "$_F5E_CNPG_PAR2 (k8s-par2) n'est pas une réplique saine"; return 1; }
}

# _f5e_par2_pret — code 0 si PAR2 est prêt, chaque problème sur la sortie d'erreur (« - … »).
_f5e_par2_pret() {
  local p r ko=0
  for p in _f5e_p_dns03 _f5e_p_reg02 _f5p_filersync_ok _f5e_p_noeud2 _f5e_p_bao2 _f5e_p_cnpg2_replique; do
    if ! r="$("$p" 2>/dev/null)"; then
      echo "  - ${r:-$p}" >&2
      ko=1
    fi
  done
  return "$ko"
}
