# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # motifs entre apostrophes
#
# check-E11.sh — M22-E11 : Revue : la configuration Alloy du stagiaire
# À lancer depuis adm01. Lecture seule : la version corrigée poussée sur la branche revue-lucas de
# plateforme/observabilite (alloy/revue-lucas/), lue par l'API GitLab. La revue elle-même
# (REVUE.md) s'auto-évalue avec le corrigé : le contrôle ne vérifie que des défauts objectivables.

# shellcheck source=_m22-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-operationnel.sh"

title "M22-E11 — Revue : la configuration Alloy du stagiaire"
require_cmd jq curl

_m22o_e11_b=revue-lucas
_m22o_e11_c="$(_m22o_contenu_main "$_M22O_P_OBS" alloy/revue-lucas/config.alloy "$_m22o_e11_b")"
_m22o_e11_v="$(_m22o_contenu_main "$_M22O_P_OBS" alloy/revue-lucas/values.yaml "$_m22o_e11_b")"
_m22o_e11_r="$(_m22o_contenu_main "$_M22O_P_OBS" alloy/revue-lucas/REVUE.md "$_m22o_e11_b")"
check_cmd "branche revue-lucas : alloy/revue-lucas/config.alloy" bash -c '[[ -n "$1" ]]' _ "$_m22o_e11_c"
check_cmd "branche revue-lucas : alloy/revue-lucas/values.yaml" bash -c '[[ -n "$1" ]]' _ "$_m22o_e11_v"
check_cmd "branche revue-lucas : alloy/revue-lucas/REVUE.md avec au moins 10 défauts numérotés" bash -c \
  '(( $(grep -Ec "^\\| *[0-9]+ *\\|" <<<"$1") >= 10 ))' _ "$_m22o_e11_r"

# Défauts objectivables de la version de Lucas : la version corrigée ne doit plus les contenir.
_m22o_e11_sans() { [[ -n "$1" ]] && ! grep -Eq -- "$2" <<<"$1"; }
_m22o_e11_avec() { grep -Eq -- "$2" <<<"$1"; }
check_cmd "corrigé : plus de recopie de toutes les étiquettes Kubernetes (labelmap)" _m22o_e11_sans "$_m22o_e11_c" 'labelmap'
check_cmd "corrigé : plus de mot de passe en clair" _m22o_e11_sans "$_m22o_e11_c" 'password *='
check_cmd "corrigé : plus d'adresse IP en dur pour Loki" _m22o_e11_sans "$_m22o_e11_c" '10\.10\.41\.62'
check_cmd "corrigé : format CRI (stage.cri), plus stage.docker" bash -c \
  'grep -q "stage.cri" <<<"$1" && ! grep -q "stage.docker" <<<"$1"' _ "$_m22o_e11_c"
check_cmd "corrigé : découverte limitée aux pods du nœud (spec.nodeName)" _m22o_e11_avec "$_m22o_e11_c" 'spec\.nodeName'
check_cmd "corrigé : un locataire est attribué (stage.tenant ou tenant_id)" _m22o_e11_avec "$_m22o_e11_c" 'stage\.tenant|tenant_id'
check_cmd "corrigé : pod en métadonnée structurée (stage.structured_metadata)" _m22o_e11_avec "$_m22o_e11_c" 'stage\.structured_metadata'
check_cmd "corrigé : route et code ne sont plus des étiquettes (pas de stage.labels sur eux)" bash -c \
  '[[ -n "$1" ]] && ! grep -Pzoq "stage\\.labels\\s*\\{[^}]*\\b(route|code)\\b" <<<"$1"' _ "$_m22o_e11_c"
check_cmd "corrigé : journald borné (max_age de quelques heures, pas 8760h)" bash -c \
  'grep -Eq "max_age *= *\"([1-9]|[1-4][0-9])h\"" <<<"$1" && ! grep -q "8760h" <<<"$1"' _ "$_m22o_e11_c"
check_cmd "corrigé : sondes écartées (stage.drop)" _m22o_e11_avec "$_m22o_e11_c" 'stage\.drop'
check_cmd "corrigé : données personnelles masquées (stage.replace)" _m22o_e11_avec "$_m22o_e11_c" 'stage\.replace'
check_cmd "corrigé : événements lus par un seul pod (clustering)" _m22o_e11_avec "$_m22o_e11_c" 'clustering'
check_cmd "values corrigées : positions hors de /tmp (storagePath)" bash -c \
  'grep -Eq "storagePath: */var/lib/" <<<"$1"' _ "$_m22o_e11_v"
check_cmd "values corrigées : image épinglée (pas latest)" _m22o_e11_sans "$_m22o_e11_v" 'tag: *latest'
check_cmd "values corrigées : limite de mémoire et tolérances" bash -c \
  'grep -q "memory:" <<<"$1" && grep -q "tolerations:" <<<"$1"' _ "$_m22o_e11_v"
check_cmd "values corrigées : configuration lue d'une ConfigMap gérée dans Git (pas collée)" bash -c \
  'grep -Eq "create: *false" <<<"$1"' _ "$_m22o_e11_v"
