#!/usr/bin/env bats
# Tests de bin/ms-verif-conteneurs (M12-E28). Aucun accès réseau : ssh et curl sont remplacés par
# des fonctions (prioritaires sur les commandes du PATH) qui répondent selon des variables d'état
# préparées par chaque test. Chaque contrôle a au moins un test « rouge ».
# Prérequis : bin/ms-verif-conteneurs charge lib/ms-commun.sh (M02-E20) : les tests tournent dans le
# projet plateforme/outils (task test:bats, CI), pas dans le dossier du corrigé seul.
# Les fonctions de remplacement sont appelées indirectement (par main) :
# shellcheck disable=SC2329,SC2317
# shellcheck source-path=SCRIPTDIR

setup() {
  # shellcheck source=../../bin/ms-verif-conteneurs
  source "$BATS_TEST_DIRNAME/../../bin/ms-verif-conteneurs"
  D="$BATS_TEST_TMPDIR"
  export MS_ETAT_DOSSIER="$D/etat"
  : >"$D/cle"
  export MS_CONF="$D/ms-verif-conteneurs.conf"
  cat >"$MS_CONF" <<FIN
MS_CONTENEURS_HOTES=(ctr01.par1.medisphere.internal ctr02.par1.medisphere.internal)
MS_CONTENEURS_UTILISATEUR=supervision
MS_CONTENEURS_CLE=$D/cle
MS_CONTENEURS_ATTENDUS=(ctr01:api ctr01:entree ctr02:quadlet)
MS_CONTENEURS_SANS_SONDE=(ctr01:entree)
MS_CONTENEURS_SEUIL_REDEMARRAGES=1
MS_CONTENEURS_METRIQUES=(http://ctr01.par1.medisphere.internal:9323/metrics)
FIN
  # État simulé (modifié par les tests).
  API_ETAT=running API_SANTE=healthy API_REDEM=0
  QUADLET_SANTE=healthy QUADLET_REDEM=2
  CTR01_JOIGNABLE=1 CTR01_TRONQUE=0 CTR02_ERREUR=0
  METRIQUES=1

  ssh() {
    local hote="${*: -2:1}"
    case "$hote" in
      *ctr01*)
        ((CTR01_JOIGNABLE)) || return 255
        printf 'docker\troot\tapi\t%s\t%s\t%s\tmediagenda-api:0.2.0\n' "$API_ETAT" "$API_SANTE" "$API_REDEM"
        printf 'docker\troot\tentree\trunning\taucune\t0\thaproxy:3.2-trixie\n'
        ((CTR01_TRONQUE)) || echo "fin 2" ;;
      *ctr02*)
        printf 'podman\tapp\tquadlet\trunning\t%s\t%s\tctr01…/mediagenda/api:recette\n' "$QUADLET_SANTE" "$QUADLET_REDEM"
        ((CTR02_ERREUR)) && echo "erreur podman app : podman ne répond pas"
        echo "fin 1" ;;
    esac
  }
  curl() {
    ((METRIQUES)) || return 7
    printf '# HELP engine_daemon_engine_info …\nengine_daemon_engine_info{version="29.8.2"} 1\n'
  }
}

@test "tout va bien : code 0" {
  run main
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bilan : "*", 0 anomalie(s)."* ]]
}

@test "option inconnue : code 2" {
  run main --nimporte-quoi
  [ "$status" -eq 2 ]
}

@test "configuration absente : code 1" {
  MS_CONF="$D/absente.conf" run main
  [ "$status" -eq 1 ]
}

@test "configuration sans conteneur attendu : code 1 (rien à surveiller n'est pas « tout va bien »)" {
  sed -i 's/^MS_CONTENEURS_ATTENDUS=.*/MS_CONTENEURS_ATTENDUS=()/' "$MS_CONF"
  run main
  [ "$status" -eq 1 ]
}

@test "hôte injoignable : KO" {
  CTR01_JOIGNABLE=0
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"KO  hote"*"ctr01 injoignable"* ]]
}

@test "réponse tronquée : KO" {
  CTR01_TRONQUE=1
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"réponse incomplète"* ]]
}

@test "moteur en erreur sur l'hôte : KO" {
  CTR02_ERREUR=1
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"KO  moteur"*"podman ne répond pas"* ]]
}

@test "conteneur attendu absent : KO" {
  sed -i 's/ctr02:quadlet)/ctr02:quadlet ctr02:fantome)/' "$MS_CONF"
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"ctr02:fantome attendu, introuvable"* ]]
}

@test "conteneur arrêté : KO" {
  API_ETAT=exited
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"ctr01:api est exited"* ]]
}

@test "conteneur en boucle de redémarrage : KO" {
  API_ETAT=restarting
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"redémarre en boucle"* ]]
}

@test "conteneur unhealthy : KO" {
  API_SANTE=unhealthy
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"ctr01:api est unhealthy"* ]]
}

@test "conteneur attendu sans sonde de santé (hors exception) : KO" {
  QUADLET_SANTE=aucune
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"ctr02:quadlet n'a pas de sonde de santé"* ]]
}

@test "exception écrite : pas de sonde admise" {
  run main
  [[ "$output" != *"ctr01:entree n'a pas de sonde"* ]]
}

@test "redémarrages : premier passage sans référence, puis hausse détectée, puis stable" {
  run main
  [ "$status" -eq 0 ]
  API_REDEM=3
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"ctr01:api a redémarré 3 fois depuis le dernier passage (0 → 3)"* ]]
  run main
  [ "$status" -eq 0 ]
}

@test "compteur remis à zéro (conteneur recréé) : pas d'alerte" {
  API_REDEM=5
  run main
  API_REDEM=0
  run main
  [ "$status" -eq 0 ]
}

@test "métriques du démon injoignables : KO" {
  METRIQUES=0
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"KO  metriques"* ]]
}

@test "mode silencieux : seules les anomalies et le bilan" {
  run main --quiet
  [ "$status" -eq 0 ]
  [[ "$output" != *"OK  "* ]]
}
