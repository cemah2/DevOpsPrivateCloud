# ADR-0071 — HAProxy et keepalived pour les points d'entrée du socle

- **Statut** : accepté
- **Date** : <AAAA-MM-JJ>
- **Décideurs** : Claire Morel, Karim Benali ; consultée : Sophie Laurent
- **Tickets** : PLAT-822 (répartiteurs), DEV-821 (comparaison avec Nginx)

## Contexte

Les services HTTPS du socle (GitLab, NetBox, puis les entrées de la plateforme aux blocs C à G)
sont joints chacun à l'adresse de sa VM : une VM arrêtée, c'est un service perdu, et chaque
service porte seul sa terminaison TLS et son exposition. Il faut un point d'entrée unique,
redondant, qui termine TLS avec les certificats de la PKI, contrôle la santé des serveurs et se
pilote sans redémarrage. La maquette (M07-E10, E11) a comparé HAProxy 3.2 et Nginx 1.26 sur le
même service.

## Décision

1. Deux répartiteurs `lb01` (10.10.70.10) et `lb02` (10.10.70.11) dans la DMZ, **HAProxy 3.2 LTS**
   (haproxy.debian.net), configuration générée par le rôle `haproxy` et validée (`haproxy -c`).
2. Une VIP **10.10.70.200** (`lb.par1.medisphere.internal`) portée par **keepalived** (VRRP v3,
   annonces unicast, VRID 170). L'instance suit l'état d'HAProxy (script de suivi : un HAProxy
   arrêté rend la VIP).
3. **Pas de préemption** : un répartiteur qui revient ne reprend pas la VIP ; le retour se fait à
   la main, au moment choisi (RB-070).
4. HAProxy écoute sur **toutes** les adresses de l'hôte (pas seulement la VIP) : chaque répartiteur
   se teste en direct, celui qui attend compris ; aucune dépendance à `ip_nonlocal_bind`.
5. Certificats **par répartiteur**, émis par ACME (step-ca), pour le nom de la VIP et le nom propre
   de l'hôte ; défi HTTP-01 relayé entre les deux répartiteurs (backend `be_acme`).

## Raisons du choix d'HAProxy plutôt que Nginx

| Critère | HAProxy 3.2 | Nginx 1.26 (édition libre) |
|---|---|---|
| Contrôles de santé actifs (requête HTTP périodique) | oui, natifs | non (seulement passifs : échec d'une vraie requête) |
| API d'exécution (drain, maintenance, poids, état) | socket d'administration | non (rechargement de la configuration) |
| Observabilité | page et CSV de statistiques, exportateur Prometheus intégré | `stub_status` (compteurs globaux) |
| Résolution DNS des serveurs en continu | section `resolvers` | paramètre `resolve` des serveurs amont : libre depuis 1.27.3, absent de la 1.26 de Debian |
| Mode TCP (SSH, PostgreSQL, Kubernetes API) | natif (`mode tcp`) | module `stream` |
| Servir des fichiers, cache | non | oui |

Nginx reste le serveur web de test (srv01/srv02) et le point de comparaison ; il n'est pas exclu
derrière les répartiteurs (fichiers statiques d'une application).

## Conséquences

- Positives : point d'entrée unique et redondant ; maintenance d'un serveur sans coupure (drain) ;
  supervision des serveurs publiés depuis un seul endroit (E29).
- Négatives : deux VMs de plus dans le socle ; un nouveau flux par service publié (DMZ vers le
  serveur) ; la PKI et le DNS deviennent des dépendances du démarrage d'un répartiteur (ACME).
- À suivre : bascule mesurée (E32) ; HAProxy 3.4 LTS (backends dynamiques par la CLI) à évaluer
  quand la plateforme publiera des services éphémères ; connexions longues coupées à la bascule
  (pas de synchronisation d'état entre répartiteurs : `peers` ne synchronise que les tables).

## Alternatives écartées

- **Nginx en mandataire** : contrôles de santé passifs seulement, pas d'API d'exécution.
- **Un seul répartiteur** : déplace le point unique de défaillance sans le supprimer.
- **Répartition par DNS (plusieurs A)** : pas de contrôle de santé, cache des clients.
- **IPVS (keepalived `virtual_server`)** : niveau 4 seulement, pas de terminaison TLS ni de routage
  par nom ; utile pour du TCP massif, pas pour publier des applications web.
