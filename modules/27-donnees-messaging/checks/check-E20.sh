# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E20.sh — M27-E20 « Panne : MédiNotif ne consomme plus » : la file de recette a un consommateur et se
# vide, elle est protégée (rebut, limite de livraison), MédiNotif ne redémarre plus, la prod est intacte ;
# RB-277 ; panne close. Lecture seule.

# shellcheck source=_m27-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-expert.sh"

title "M27-E20 — MédiNotif consomme à nouveau"
require_cmd kubectl jq curl

check_cmd "notifications ($_m27p_vhost_recette) : un consommateur, moins de 20 messages prêts, pas de redélivrance en boucle" \
  _m27x_file_saine "$_m27p_vhost_recette"
check_cmd "notifications ($_m27p_vhost_recette) : rebut et limite de livraison en place (pas -1)" \
  _m27x_file_protegee "$_m27p_vhost_recette"
check_cmd "MédiNotif (recette) disponible, sans redémarrage depuis 10 min" _m27x_medinotif_sain medinotif-recette
check_cmd "notifications envoyées en recette dans les 15 dernières minutes (medinotif_messages_total)" \
  _m27p_prom_positif 'sum(increase(medinotif_messages_total{namespace="medinotif-recette", resultat="envoye"}[15m]))'
check_cmd "production intacte : notifications ($_m27p_vhost_prod) a un consommateur" \
  _m27p_file "$_m27p_vhost_prod" notifications '(.consumers // 0) >= 1'
check_cmd "runbook RB-277 « Un consommateur ne consomme plus » (rebut, rejeu sans doublon)" \
  _m27p_doc "$_m27p_runbooks" RB-277 'consommateur' 'rebut' 'peek|en-t[êe]te|x-death' 'doublon|idempot'
check_cmd "journal de diagnostic INC-5420" _m27x_journal_inc 5420 'hypoth' 'cause'
check_cmd "panne M27-E20 close (lab/bin/break 27 20 --annuler après réparation)" _m27p_aucune_panne_active E20
