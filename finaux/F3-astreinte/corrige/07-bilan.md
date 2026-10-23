# Corrigé — Final F3, phase 7 : bilan

> ⚠️ Corrigé : à n'ouvrir qu'après avoir cherché. Les trois livrables de référence sont des **exemples** : il en existe d'autres, et les tiens doivent porter tes chiffres, tes heures et tes décisions.

**Non testé en conditions réelles** : les tests `promtool` de référence ont été écrits pour Prometheus 3.x et relus, mais pas exécutés lors de la rédaction (lance `promtool test rules` dans la CI de `plateforme/observabilite`, c'est précisément le critère) ; la configuration d'Alertmanager de l'extrait n'a pas été passée à `amtool check-config` (même remarque).

---

### F3-S14 — Le post-mortem de la semaine

#### Solution de référence

Fichier : [`post-mortems/INC-5910.md`](fichiers/S14/medisphere/docs/exploitation/post-mortems/INC-5910.md).

**Le choix de l'incident.** Les deux candidats naturels sont INC-5903 (lenteur de MédiAgenda en **production**, impact client réel) et INC-5910 (perte de la VIP du coffre, si c'est la variante qui t'est échue : recette tombée, **production exposée à une heure près**, CI bloquée). Le critère n'est pas l'impact constaté seul, mais l'impact **possible** et ce qu'on peut apprendre : un point unique au-dessus de toute la chaîne de secrets vaut un post-mortem même si la prod n'a rien perdu. Un post-mortem d'INC-5913 (rappels en retard, prod) ou d'INC-5912 (sécurité) est tout aussi défendable si tu le justifies. Ce qui ne l'est pas : choisir l'incident le plus simple à raconter.

**Reconstituer la chronologie depuis des sources, pas de mémoire.**

```
admin@adm01:~$ git -C ~/medisphere show main:docs/exploitation/journal/2026-11-05.md | grep INC-5910
admin@adm01:~$ curl -s -u "$MAILPIT_USER:$MAILPIT_PASSWORD" \
  "https://mon01.par1.medisphere.internal:8025/api/v1/search?query=$(jq -rn --arg q 'subject:"INC-5910"' '$q|@uri')" \
  | jq -r '.messages[] | "\(.Created) \(.Subject)"'
admin@adm01:~$ curl -s -u "$MAILPIT_USER:$MAILPIT_PASSWORD" \
  "https://mon01.par1.medisphere.internal:8025/api/v1/search?query=$(jq -rn --arg q 'to:astreinte@medisphere.internal' '$q|@uri')&limit=200" \
  | jq -r '.messages[] | select(.Created | startswith("2026-11-05")) | "\(.Created) \(.Subject)"'
```

Dans Grafana : `ALERTS{alertname=~"MagasinSecretsEnErreur|ExternalSecretEnErreur"}` sur la matinée (passages en *pending* et *firing*) ; Loki `{unit="keepalived.service"}` (journald des nœuds du coffre, collecté par Alloy) et, locataire `audit`, les écritures et lectures d'OpenBao autour de l'heure de la cause ; `kubectl get events` est trop court-vivant (1 h) : Loki garde les événements Kubernetes (M22).

**Mesures.** Écris tes définitions (celles de ta procédure S02) et applique-les à des horodatages : MTTA = premier signal reçu → prise en compte ; MTTR = début de l'impact → rétablissement. Donne aussi le MTTD : c'est souvent lui qui révèle le vrai problème (ici : l'utilisateur a précédé l'alerte).

**Cinq pourquoi.** Descendre jusqu'à une **condition du système** (« seul l'actif est éligible à la VIP, et rien ne surveille qu'elle soit portée »), jamais jusqu'à une personne (« X a arrêté keepalived »). Les facteurs contributifs (absence de fiche de changement, baux qui masquent l'urgence) sont aussi importants que la cause.

**Actions.** Peu, concrètes, datées, portées, chacune avec un ticket ; une détection (sonde VIP), une prévention (politique Kyverno, fiche de changement), une atténuation (étude d'architecture), un exercice. Les tickets d'actions issus du post-mortem prennent des numéros `PLAT-337x` (au-delà des numéros des scénarios), pour ne pas se confondre avec les tickets des scénarios `PLAT-33xx`.

#### Explications

Un post-mortem sert à **changer le système**, pas à raconter : il se juge à ses actions et à leur suivi. « Sans recherche de coupable » n'est pas de la politesse : quiconque craint d'être désigné cache les détails qui permettraient d'apprendre.

#### Pièges classiques

- Une chronologie de mémoire, sans sources, aux heures arrondies.
- Des actions vagues (« être plus vigilant ») ou sans date ni porteur.
- Confondre la cause déclenchante et la cause du système.
- Oublier ce qui a bien marché (on le perd au prochain réaménagement).

#### En production chez MédiSphère

Post-mortem obligatoire pour tout SEV1 et SEV2 dans les cinq jours ouvrés, relu en réunion d'exploitation ; actions suivies dans un tableau jusqu'à clôture ; les post-mortems alimentent les exercices de jeu (M29).

---

### F3-S15 — Faire taire les alertes inutiles

#### Solution de référence (il en existe d'autres)

**1. Inventaire et classement** — [`revue-alertes-semaine.md`](fichiers/S15/medisphere/docs/exploitation/revue-alertes-semaine.md). Compter d'abord (Mailpit par objet, `ALERTS` sur la semaine), classer ensuite avec une règle écrite (actionnable = il faut agir maintenant et l'alerte dit quoi), décider enfin, alerte par alerte, avec l'outil le plus étroit : remplacer, retarder, regrouper, inhiber, router, ou **ne rien changer** (sécurité).

**2. La MR** (`plateforme/observabilite`, une branche, une MR qui cite `PLAT-3315`) :

- [`regles/capacite-astreinte.yaml`](fichiers/S15/observabilite/regles/capacite-astreinte.yaml) et ses [tests](fichiers/S15/observabilite/tests/capacite-astreinte.test.yaml) : remplaçants de `KubeCPUOvercommit` et `KubeMemoryOvercommit` (même question, `for: 1h`, avertissement aux heures ouvrées) ; les tests prouvent qu'ils sonnent quand la capacité manque, et qu'un pic de Job de 30 min ne sonne pas ;
- les règles de S13 ([`notifications-astreinte.yaml`](fichiers/S13/observabilite/regles/notifications-astreinte.yaml)) remplacent `KubeHpaMaxedOut` (être au plafond pendant une campagne est voulu ; plafond **et** retard ne l'est pas) — si tu ne les as pas encore poussées en S13, elles entrent dans cette MR ;
- [`kps/values.yaml` (extrait)](fichiers/S15/observabilite/kps/values.yaml.extrait) : `defaultRules.disabled` pour les trois règles du chart remplacées ; un regroupement des erreurs d'ESO (une notification par alerte, tous espaces confondus) ; quatre inhibitions « la cause fait taire ses conséquences » (coffre → ESO, file sans consommateur → file qui grossit, plafond et retard → file qui grossit en prod, KEDA absent → scaler en erreur) ; la liste `inhibit_rules` est donnée **en entier** (Helm remplace les listes) ;
- [`alertmanager/routes-tests.txt` (lignes ajoutées)](fichiers/S15/observabilite/alertmanager/routes-tests.txt.extrait).

Vérification locale avant la MR, comme la CI (outils de l'image Prometheus/Alertmanager ou binaires sur `adm01`) :

```
admin@adm01:~/src/observabilite$ sh outils/extraire-regles.sh
admin@adm01:~/src/observabilite$ promtool check rules build/regles/*.yml
admin@adm01:~/src/observabilite$ promtool test rules tests/*.test.yaml
admin@adm01:~/src/observabilite$ mkdir -p /tmp/am && yq '.alertmanager.config' kps/values.yaml > /tmp/am/alertmanager.yaml \
  && yq '.alertmanager.templateFiles["medisphere.tmpl"]' kps/values.yaml > /tmp/am/medisphere.tmpl \
  && yq -i '.templates = ["medisphere.tmpl"]' /tmp/am/alertmanager.yaml
admin@adm01:~/src/observabilite$ (cd /tmp/am && amtool check-config alertmanager.yaml) && sh outils/tester-routes.sh /tmp/am/alertmanager.yaml alertmanager/routes-tests.txt
```

**3. Vérifier une inhibition sur l'Alertmanager du cluster** (les essais de routage ne les couvrent pas) : envoyer une alerte source et une alerte cible factices, de courte durée, puis constater que la cible est inhibée.

```
admin@adm01:~$ AM=http://alertmanager.apps.par1.medisphere.internal:9093
admin@adm01:~$ amtool --alertmanager.url=$AM alert add alertname=RabbitmqFileSansConsommateur vhost=medinotif-recette queue=essai-plat3315 gravite=avertissement equipe=plateforme --end=$(date -u -d '+5 min' +%FT%TZ)
admin@adm01:~$ amtool --alertmanager.url=$AM alert add alertname=RabbitmqFileQuiGrossit vhost=medinotif-recette queue=essai-plat3315 gravite=avertissement equipe=plateforme --end=$(date -u -d '+5 min' +%FT%TZ)
admin@adm01:~$ curl -s "$AM/api/v2/alerts?filter=queue%3D%22essai-plat3315%22" | jq -r '.[] | "\(.labels.alertname) inhibée par : \(.status.inhibitedBy)"'
```

(Alertes d'essai sur la **recette** et une file inexistante, expirant seules en 5 minutes, consignées dans la main courante : elles peuvent produire un courriel aux heures ouvrées.)

**4. Après fusion** : Argo CD synchronise ; la configuration chargée (`/api/v2/status`, `config.original`) a les nouvelles inhibitions ; les règles remplacées n'existent plus dans Prometheus (`/api/v1/rules`), les nouvelles si.

#### Explications

Le bruit tue l'astreinte plus sûrement qu'une alerte manquante : une personne qui reçoit 40 notifications inutiles par semaine finit par ne plus les lire, y compris la bonne. Mais chaque réduction de bruit est un risque de trou : d'où la règle « pas de suppression sans remplaçant testé », et les tests qui prouvent qu'une situation réelle sonne encore. L'inhibition est l'outil des **doublons causaux** (la cause notifiée, ses conséquences tues), le regroupement celui des **rafales** (la même chose N fois), la durée (`for`) celui des situations **transitoires**, la route et les intervalles horaires celui de la **mauvaise personne ou du mauvais moment**.

#### Alternatives

- Silences permanents à la place des inhibitions : invisibles dans le code, oubliés, dangereux ; un silence est un outil d'incident, daté.
- Monter les seuils plutôt que la durée : plus simple, mais transforme une alerte de capacité en alerte de panne.
- Sloth/Pyrra (SLO, M21) : remplacer des alertes de cause par des alertes de taux de consommation du budget d'erreur ; plus juste pour les services, plus long à mettre en place.

#### Pièges classiques

- Désactiver une règle du chart en éditant son fichier rendu (écrasé à la prochaine montée de version) au lieu de `defaultRules.disabled`.
- Une inhibition dont les étiquettes `equal` n'existent pas sur la source **ou** la cible : elle ne fait jamais rien (ou, sans `equal`, elle fait taire trop large).
- Inhiber ou regrouper des alertes de sécurité.
- Donner une liste partielle de `inhibit_rules` : Helm la remplace, les inhibitions du M21 disparaissent.

#### En production chez MédiSphère

Revue du bruit à chaque fin d'astreinte (une ligne dans le rapport de semaine), indicateur « notifications par semaine et part d'actionnables », toute nouvelle alerte avec runbook et tests (politique du M21-E32).

---

### F3-S16 — Rapport de semaine et passation

#### Solution de référence

Fichier : [`rapport-semaine-2026-S45.md`](fichiers/S16/medisphere/docs/exploitation/rapport-semaine-2026-S45.md).

Les durées viennent de la main courante, par la même définition partout ; les médianes (et pas les moyennes) résistent mieux à un incident hors norme. Les interruptions se donnent **par service**, production d'abord, en distinguant interruption et dégradation. La dette se classe par **risque**, pas par ancienneté. La passation dit ce qui est **en cours d'exécution** (silences, injections, interventions suspendues) : idéalement rien, et alors on l'écrit.

**Clore et étiqueter.**

```
admin@adm01:~$ ls ~/.local/state/workbook/pannes-actives/ 2>/dev/null     # aucune injection F3 ouverte
admin@adm01:~$ amtool --alertmanager.url=http://alertmanager.apps.par1.medisphere.internal:9093 silence query   # aucun silence d'incident restant
admin@adm01:~/medisphere$ git switch main && git pull
admin@adm01:~/medisphere$ ls docs/exploitation/{gestion-incidents.md,rapport-semaine-*.md} docs/exploitation/post-mortems/
admin@adm01:~/medisphere$ git tag -a astreinte-v1 -m "Final F3 : semaine d'astreinte (procédure, main courante, post-mortem, rapport)"
admin@adm01:~/medisphere$ git push origin astreinte-v1
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check F3 16
```

(Si `plateforme/medisphere` protège ses étiquettes ou les fait poser par semantic-release, comme depuis le M01, passe par ce chemin : le critère est l'existence de l'étiquette sur un commit de `main` qui contient les livrables.)

#### Explications

Un rapport de semaine est lu deux fois : par la direction (cinq minutes, la phrase et le tableau), par la personne suivante (toute la semaine, les points ouverts). Il fait aussi la preuve, auprès des auditeurs (HDS, ISO 27001), que les incidents sont suivis jusqu'à leurs actions.

#### Pièges classiques

- Recopier la main courante au lieu de la synthétiser.
- Des MTTR calculés avec des définitions différentes d'un incident à l'autre.
- Une passation qui oublie un silence actif ou une intervention à moitié faite.
- Poser l'étiquette avant que le rapport soit fusionné.

#### En production chez MédiSphère

Rapport de semaine à modèle fixe, généré en partie (tableau des incidents depuis la main courante, notifications depuis Alertmanager/Mailpit), relu à la passation du lundi en présentiel ou en visio, archivé avec l'étiquette de la semaine.
