# Topologie de la messagerie (RabbitMQ)

> `docs/donnees/messagerie-topologie.md` — M27-E04 (DEV-2804), complété en M27-E08 (prod).
> Grappe : [`rabbitmq.md`](rabbitmq.md).

## Principe

Toute la topologie est **déclarée** dans `plateforme/donnees/topologie/<vhost>/` et appliquée par le
Messaging Topology Operator (Application `rabbitmq-topologie`). Rien n'est créé à la main dans
l'interface ; une application ne déclare **pas** ses files (`MEDINOTIF_DECLARER_FILE=0`, droit
`configure` vide).

## Par environnement `<env>` (`recette`, `prod`)

```
MédiAgenda (mediagenda-<env>)                              MédiNotif (medinotif-<env>)
   │ AMQPS 5671, utilisateur mediagenda-<env>                 ▲ AMQPS 5671, utilisateur medinotif-<env>
   │ publish exchange=notifications key=notifications        │ consume notifications (prefetch 1, ack après envoi)
   ▼                                                          │
 vhost medinotif-<env>                                        │
 ┌──────────────────────────┐   liaison « notifications »   ┌─┴──────────────────────────────┐
 │ échange notifications    │ ───────────────────────────► │ file quorum notifications       │
 │ (direct)                 │                               │ politique notifications-rebut : │
 └──────────────────────────┘                               │  dead-letter-exchange,          │
                                                            │  delivery-limit 5,              │
                                nack sans remise en file    │  at-least-once, reject-publish  │
 ┌──────────────────────────┐ ◄──── ou 5 livraisons ─────── └─────────────────────────────────┘
 │ échange notifications.   │
 │ rebut (fanout)           │ ──► file quorum notifications.rebut  (lue par une personne, jamais purgée sans ticket)
 └──────────────────────────┘
```

| Objet RabbitMQ | Objet Kubernetes (`messagerie`) | Remarque |
|---|---|---|
| vhost `medinotif-<env>` | `Vhost` `medinotif-<env>` | `defaultQueueType: quorum`, `deletionPolicy: retain` |
| échange `notifications` | `Exchange` `medinotif-<env>-notifications` | direct, durable |
| file `notifications` | `Queue` `medinotif-<env>-notifications` | quorum, `deletionPolicy: retain` ; type et arguments figés |
| échange `notifications.rebut` | `Exchange` `medinotif-<env>-notifications-rebut` | fanout |
| file `notifications.rebut` | `Queue` `medinotif-<env>-notifications-rebut` | quorum |
| liaisons | `Binding` `medinotif-<env>-notifications`, `…-notifications-rebut` | clé `notifications` ; vide pour le rebut |
| politique `notifications-rebut` | `Policy` `medinotif-<env>-notifications-rebut` | motif `^notifications$`, `applyTo: quorum_queues` |

## Comptes et droits

| Utilisateur RabbitMQ | Secret OpenBao | configurer | écrire | lire |
|---|---|---|---|---|
| `medinotif-<env>` | `kv/medinotif/<env>/amqp` | `^$` | `^$` | `^notifications$` |
| `mediagenda-<env>` | `kv/mediagenda/<env>/amqp` | `^$` | `^notifications$` (échange) | `^$` |
| `wb-checks` | `kv/plateforme/rabbitmq/wb-checks` | `^$` | `^$` | `^$` (métadonnées seulement, étiquette `monitoring`) |

Clés des secrets AMQP : `utilisateur`, `mot_de_passe`, `url` (`amqps://<utilisateur>:<mot de passe>@rabbitmq.messagerie.svc:5671/medinotif-<env>`). Le même secret sert à la plateforme (création de l'utilisateur, ClusterSecretStore `openbao`, exception écrite dans `eso-plateforme.hcl`) et à l'application (SecretStore de son espace).

## Ce qui a été constaté (recette, <AAAA-MM-JJ>)

- 10 messages valides publiés par `ressources/E04-messages/publier.py` (compte `mediagenda-recette`) : `medinotif_messages_total{resultat="envoye"}` = 10 ; 2 invalides : `{resultat="invalide"}` = 2, et 2 messages dans `notifications.rebut`, en-tête `x-death` (`reason: rejected`, `queue: notifications`, `exchange: notifications`).
- Publier avec le compte de MédiNotif : `ACCESS_REFUSED - write access to exchange 'notifications'`.
- Le worker n'a pas eu à connaître le rebut : `basic_nack(requeue=False)` suffit, la **file** sait où envoyer.

## Ajouter un environnement

1. OpenBao : `kv/medinotif/<env>/amqp` et `kv/mediagenda/<env>/amqp` ; chemins ajoutés à `eso-plateforme.hcl` (MR `plateforme/secrets`).
2. `plateforme/donnees` : copier `topologie/medinotif-recette/` en `topologie/medinotif-<env>/` (remplacer le préfixe et le vhost), l'ajouter à `topologie/kustomization.yaml` ; règle AMQPS de l'espace dans `rabbitmq/reseau.yaml`.
3. `plateforme/k8s` : espace `medinotif-<env>` (étiquettes, quota, `LimitRange`, `80-openbao.yaml`), cloison `isolement-medinotif-<env>` ; rôle `eso-medinotif-<env>` dans `plateforme/secrets`.
4. `medinotif/deploiement` : overlay ; `plateforme/gitops` : élément de l'ApplicationSet `medinotif`, destination de l'AppProject.
