# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # programmes bash -c et filtres jq entre apostrophes
# check-S01.sh — F1-S01 « La carte d'amorçage de MédiSphère » (RED publié) : présence et contenu
# minimal de docs/day0/carte-amorcage.md sur main de plateforme/medisphere. Lecture seule (GitLab).
# Le fond (justesse de l'ordre, des cycles, des durées) s'évalue avec la grille du corrigé.

# shellcheck source=_f1-preparer.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-preparer.sh"

title "F1-S01 — La carte d'amorçage de MédiSphère"
require_cmd curl jq

_f1_s01_chemin="$(_f1p_doc_chemin '^carte-amorcage\.md$')" || _f1_s01_chemin=""
check_cmd "docs/day0/carte-amorcage.md publié sur main de $_f1p_projet_doc" test -n "$_f1_s01_chemin"

if [[ -n "$_f1_s01_chemin" ]]; then
  _f1_s01_texte="$(_f1p_fichier "$_f1p_projet_doc" "$_f1_s01_chemin" 2>/dev/null)" || _f1_s01_texte=""
  check_cmd "la carte nomme les briques du socle à reconstruire d'abord (passerelles, DNS, PKI, GitLab, S3, Harbor, OpenBao, Keycloak)" \
    _f1p_contient "$_f1_s01_texte" 'gw0[12]|passerelle' 'dns0[12]|PowerDNS' 'ca01|step-ca' 'git01|GitLab' 's3-01|SeaweedFS' 'Harbor|reg01' 'OpenBao|vault0' 'Keycloak|idp01'
  check_cmd "la carte va jusqu'au cluster et aux applications (Ceph, kubeadm, Helmfile, Argo CD, MédiAgenda)" \
    _f1p_contient "$_f1_s01_texte" 'ceph' 'kubeadm|k8s-par1' 'Helmfile' 'Argo ?CD' 'M.{1,2}diAgenda'
  check_cmd "un ordre de construction explicite (étapes numérotées ou graphe)" \
    _f1p_contient "$_f1_s01_texte" '(^|[[:space:]])(1\.|1\)|étape 1|mermaid|graph (TD|LR)|-->|──▶|→)'
  check_cmd "une section sur les dépendances circulaires" _f1p_contient "$_f1_s01_texte" 'circulaire|cycle'
  check_cmd "les cycles attendus sont traités (forge qui héberge son propre code, registre qui sert ses images, coffre et Ansible, ESO et méthode k8s-par1)" \
    _f1p_contient "$_f1_s01_texte" 'GitLab' 'Harbor' 'Ansible Vault|vault-pass' 'ESO|External Secrets' 'k8s-par1'
  check_cmd "une section sur les secrets hors du code" _f1p_contient "$_f1_s01_texte" 'hors (du )?code|hors (de )?Git|hors ligne'
  check_cmd "les secrets d'amorçage sont recensés (parts Shamir de kms01, racine hors ligne, mots de passe des Vault Ansible, clés age, bris de glace, admin.conf)" \
    _f1p_contient "$_f1_s01_texte" 'Shamir' 'kms01' 'racine' 'Ansible Vault|vault-pass|ansible-vault' '(^|[^a-z])age([^a-z]|$)' 'RB-240|bris de glace' 'admin\.conf'
  check_cmd "des durées estimées (minutes ou heures) par étape" \
    _f1p_contient "$_f1_s01_texte" '[0-9]+ ?(min|h|heures?|minutes?)([^a-z]|$)'
  check_cmd "aucun secret apparent dans la carte (clé privée, jeton glpat-, AGE-SECRET-KEY)" \
    bash -c '! grep -Eq -- "BEGIN [A-Z ]*PRIVATE KEY|glpat-|glrt-|AGE-SECRET-KEY|hvs\.|s\.[A-Za-z0-9]{24}" <<<"$1"' _ "$_f1_s01_texte"
else
  skip "contenu de la carte d'amorçage" "document absent"
fi
