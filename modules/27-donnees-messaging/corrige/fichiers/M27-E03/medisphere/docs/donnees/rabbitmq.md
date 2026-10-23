# RabbitMQ de MédiSphère (`messagerie/rabbitmq`)

> `docs/donnees/rabbitmq.md` — M27-E03 (PLAT-2803). Fiche d'exploitation. Topologie et comptes des
> applications : [`messagerie-topologie.md`](messagerie-topologie.md). Redémarrage en roulement :
> [RB-271](runbooks/RB-271-rabbitmq-redemarrage-roulement.md).

## En bref

| Élément | Valeur |
|---|---|
| Version | RabbitMQ **4.3.7** (`registry.par1.medisphere.internal/dockerhub/library/rabbitmq:4.3.7-management`, par empreinte), Erlang 27 |
| Opérateurs | Cluster Operator **2.23.1**, Messaging Topology Operator **1.20.4**, espace `rabbitmq-system`, Application `rabbitmq-operateurs` |
| Source | `plateforme/donnees` : `vendor/rabbitmq/` (manifestes amont épinglés, `outils/recopier-operateurs.sh` vérifie leurs SHA-256), `rabbitmq/` (grappe, Application `rabbitmq`) |
| Grappe | `RabbitmqCluster` `rabbitmq`, 3 nœuds `rabbitmq-server-0..2` (un par travailleur, anti-affinité requise), PVC `ceph-rbd` 10 Gio, 1 Gio de mémoire chacun, PDB `maxUnavailable: 1` |
| Métadonnées | **Khepri** (Raft, *feature flag* `khepri_db`) : 3 nœuds, majorité 2 |
| Ports | 5671 AMQPS (applications, dans le cluster) ; 15672 gestion HTTP (Gateway seulement) ; 15671 gestion HTTPS (Topology Operator) ; 15692 Prometheus ; 5672 **fermé** par la CNP `rabbitmq` |
| TLS | Certificate `rabbitmq-tls` (ClusterIssuer `openbao-services`, 72 h, renouvelé à 24 h) |
| Interface | `https://rabbitmq.apps.par1.medisphere.internal`, connexion **Keycloak** (client public `rabbitmq`, rôles du client → groupes) |

## Comptes

| Compte | Où | Usage | Droits |
|---|---|---|---|
| Personnes (SSO) | Keycloak, rôles du client `rabbitmq` | interface de gestion | `plateforme-admins` : administrateur, configurer/écrire/lire partout ; `plateforme`, `support` : supervision (`monitoring`) |
| `wb-checks` | `User` déclaratif, mot de passe `kv/plateforme/rabbitmq/wb-checks` | vérifications du workbook (API, authentification basique) | étiquette `monitoring`, permission **vide** (`^$`) sur chaque vhost : voit les métadonnées, ne lit aucun message |
| Applications | voir `messagerie-topologie.md` | AMQPS | par vhost, minimales |
| **Bris de glace** : utilisateur `default_user_…` | Secret `messagerie/rabbitmq-default-user` (clés `username`, `password`, `default_user.conf`, `host`, `port`, `provider`, `type`), créé par l'opérateur | **uniquement** si Keycloak est indisponible ou si l'opérateur ne réconcilie plus | administrateur |

### Utiliser le compte de bris de glace

1. Ticket `INC-` ou `CHG-` ouvert, annonce dans le canal d'astreinte.
2. Lecture par une personne de `plateforme-admins` (droits du M24-E17 ; contrôle : `kubectl auth can-i get secrets -n messagerie`) :
   ```
   admin@adm01:~$ kubectl -n messagerie get secret rabbitmq-default-user -o jsonpath='{.data.username}' | base64 -d; echo
   admin@adm01:~$ kubectl -n messagerie exec -it rabbitmq-server-0 -c rabbitmq -- rabbitmqctl list_users
   ```
   (`rabbitmqctl` dans un pod s'authentifie par le cookie Erlang : le mot de passe n'est même pas nécessaire pour l'essentiel des diagnostics.)
3. Après usage : consigner l'usage dans le journal de l'incident. Une rotation de ce compte change **ensemble** l'utilisateur dans RabbitMQ et le Secret `rabbitmq-default-user`, que le Topology Operator utilise pour appliquer la topologie : suivre la procédure de la documentation du Cluster Operator de ta version (non répétée en conditions réelles ici).

## Vérifications courantes

```
admin@adm01:~$ kubectl -n messagerie get rabbitmqcluster rabbitmq
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-diagnostics cluster_status
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-diagnostics metadata_store_status
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl list_feature_flags name state
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-diagnostics alarms
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-diagnostics listeners
admin@adm01:~$ set -a; . ~/.config/workbook/rabbitmq-checks.env; set +a
admin@adm01:~$ curl -s -u "$RABBITMQ_USER:$RABBITMQ_PASSWORD" https://rabbitmq.apps.par1.medisphere.internal/api/overview | jq '{rabbitmq_version, cluster_name}'
```

Certificat présenté sur 5671 (depuis un pod de `wb-essais`, racine MédiSphère montée) :

```
admin@adm01:~$ kubectl -n wb-essais run tls-essai --rm -it --restart=Never \
    --image=registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim -- bash
root@tls-essai:/# apt-get update -qq && apt-get install -qq -y openssl >/dev/null
root@tls-essai:/# openssl s_client -connect rabbitmq.messagerie.svc:5671 -servername rabbitmq.messagerie.svc \
      -CAfile /chemin/medisphere-root-ca.crt </dev/null 2>/dev/null | grep -E 'subject=|Verify return code'
```

(La CNP de `messagerie` doit accepter 5671 depuis `wb-essais` le temps de l'essai, ou l'essai se fait depuis un pod de la grappe.)

## Règles

- Files **quorum** uniquement (les files miroir n'existent plus depuis 4.0 ; une file classique ne survit pas à la perte de son nœud).
- Jamais de purge pour « débloquer » ; jamais deux nœuds arrêtés en même temps (PDB) ; redémarrage en roulement par RB-271.
- Montée de version : répétée d'abord dans `wb-essais` (M27-E15) ; 4.4 interdit le retour en 4.3 (format v2 des files classiques).
