# Guide utilisateur du cloud MédiSphère

> Pour les équipes de développement et d'exploitation applicative. Propriétaire : équipe Plateforme. Version `cloud-v1` (PLAT-1190).
> Une question qui n'est pas ici : ticket `DEV-` à la plateforme. Un incident : astreinte (Nadia Roussel), en précisant le projet et l'identifiant de la requête (`X-Openstack-Request-Id`) si tu l'as.

## 1. Ce que c'est

Un cloud privé OpenStack 2026.1 hébergé à PAR1 : des serveurs virtuels, des réseaux privés, des disques persistants, des répartiteurs de charge et des adresses joignables depuis le réseau d'administration et le VPN — en libre-service, par API, CLI, tableau de bord ou OpenTofu. Les données restent chez MédiSphère (stockage Ceph de PAR1).

| Point d'accès | Adresse |
|---|---|
| Tableau de bord (Horizon) | `https://openstack.par1.medisphere.internal` — domaine `medisphere`, ton identifiant habituel |
| API (Keystone) | `https://openstack.par1.medisphere.internal:5000/v3` |
| Certificats | émis par la PKI MédiSphère : installe la racine (`medisphere-root-ca.crt`) sur ton poste |
| Joignable depuis | réseau d'administration (MGMT), VPN d'administration, `runner01` (CI) |

## 2. Ton équipe, ton projet

- Une équipe = un **groupe** Keystone (ex. `equipe-mediagenda`) ; un environnement = un **projet** (ex. `mediagenda-dev`, `mediagenda-prod`) dans le domaine `medisphere`.
- Rôles : `member` (créer et gérer les ressources du projet), `reader` (voir sans modifier). Personne n'a `admin` hors de l'équipe Plateforme.
- Quotas par projet (instances, vCPU, mémoire, volumes, IP flottantes) : `openstack limits show --absolute`. Les quotas additionnés de tous les projets dépassent la capacité réelle : un « No valid host » peut arriver avant ton quota (prévenir la plateforme).
- Arrivée d'une équipe : runbook RB-100 (la plateforme crée groupe, projets, quotas, identifiants).

## 3. Accéder par la CLI

```
moi@poste:~$ uv tool install python-openstackclient --with python-octaviaclient --with python-heatclient
```

`~/.config/openstack/clouds.yaml` (sans secret) :

```yaml
clouds:
  mediagenda-dev:
    auth:
      auth_url: https://openstack.par1.medisphere.internal:5000/v3
      username: <TON-IDENTIFIANT>
      user_domain_name: medisphere
      project_name: mediagenda-dev
      project_domain_name: medisphere
    region_name: RegionOne
    interface: public
    identity_api_version: 3
    cacert: /usr/local/share/ca-certificates/medisphere-root-ca.crt
```

Le mot de passe va dans `secure.yaml` (mode 600) ou t'est demandé ; **jamais** sur une ligne de commande. Cinq échecs d'authentification consécutifs verrouillent ton compte 15 minutes ; les sessions Horizon durent 30 minutes.

**Automatisation** (CI, OpenTofu) : pas ton mot de passe, une **application credential** du projet, rôle `member`, avec une date d'expiration, stocké en variable protégée et masquée de ton projet GitLab.

## 4. Catalogue

| Ressource | Ce qui existe |
|---|---|
| Gabarits | `m1.petit` (1 vCPU, 1 Go, 10 Go), `m1.moyen` (2 vCPU, 2 Go, 20 Go), `m1.grand` (2 vCPU, 4 Go, 40 Go) |
| Images publiques | Debian 13, Rocky Linux 10 (format raw, agent QEMU) — n'envoie pas tes propres images qcow2 : demande |
| Réseau externe | `ext-net` : passerelle de tes routeurs et IP flottantes (10.10.52.200-249) |
| Volumes | type par défaut (Ceph, 3 copies), instantanés, sauvegardes Cinder |
| Répartiteurs | Octavia, fournisseur **OVN** : TCP/UDP, `SOURCE_IP_PORT`, pas de TLS ni de L7 (voir §6) |
| Piles | Heat (gabarits HOT) |
| Libre-service complet | module OpenTofu `openstack-env-app` : voir `libre-service.md` |

## 5. Premiers pas (réseau, serveur, IP flottante)

```
moi@poste:~$ export OS_CLOUD=mediagenda-dev
moi@poste:~$ openstack network create equipe-net
moi@poste:~$ openstack subnet create --network equipe-net --subnet-range 172.20.20.0/24 --dns-nameserver 10.10.20.10 --dns-nameserver 10.10.20.16 equipe-sn
moi@poste:~$ openstack router create equipe-rt
moi@poste:~$ openstack router set --external-gateway ext-net equipe-rt
moi@poste:~$ openstack router add subnet equipe-rt equipe-sn
moi@poste:~$ openstack security group create equipe-ssh
moi@poste:~$ openstack security group rule create --protocol tcp --dst-port 22 --remote-ip 10.255.1.0/24 equipe-ssh
moi@poste:~$ openstack keypair create --public-key ~/.ssh/id_ed25519.pub ma-cle
moi@poste:~$ openstack server create --flavor m1.petit --image debian-13 --network equipe-net \
                --security-group equipe-ssh --key-name ma-cle --wait essai01
moi@poste:~$ openstack floating ip create ext-net        # puis : openstack server add floating ip essai01 <IP>
moi@poste:~$ ssh debian@<IP>
```

Plages privées : choisis-les hors 10.10.0.0/16, 10.20.0.0/16 et 10.255.0.0/16 (réseaux de MédiSphère).

## 6. Ce qu'il faut savoir

- **Groupes de sécurité** : tout est fermé en entrée par défaut. N'ouvre que ce qu'il faut, depuis les plages qu'il faut ; jamais SSH depuis `0.0.0.0/0`.
- **Répartiteur OVN** : tes serveurs voient l'adresse des **clients** (pas de traduction) ; ouvre le port de l'application aux clients **et** au sous-réseau (contrôles de santé). Pas de HTTPS sur le répartiteur : termine le TLS dans ton application.
- **Les instances ne joignent pas** le plan de contrôle du cloud ni les réseaux d'infrastructure (hors DNS du socle) ; elles joignent Internet.
- **Les données** : un disque d'instance disparaît avec l'instance ; ce qui doit survivre va dans un **volume**. La plateforme sauvegarde la base du cloud, **pas** tes données : sauvegarde tes volumes (instantanés, `openstack volume backup create`) selon ton besoin.
- **Disponibilité** : un seul contrôleur aujourd'hui. Pendant une maintenance annoncée, l'API et Horizon peuvent être indisponibles quelques minutes ; tes instances continuent de tourner. La perte du contrôleur coupe les IP flottantes jusqu'à son retour (voir `haute-disponibilite.md`).
- **Maintenance des calculs** : tes instances peuvent être migrées à chaud (coupure de l'ordre de la seconde) ; tu es prévenu à l'avance.

## 7. Dépannage rapide

| Symptôme | Premier réflexe |
|---|---|
| « No valid host was found » | `openstack limits show --absolute` (quota ?) ; gabarit plus petit ; sinon ticket avec l'identifiant de la requête (`--debug`) |
| Instance `ERROR` | `openstack server show <nom> -c fault` ; ticket avec l'identifiant de l'instance |
| IP flottante muette | groupe de sécurité (port, plage source) ; routeur relié à `ext-net` ; l'instance écoute-t-elle ? |
| Configuration cloud-init ignorée | `openstack console log show <nom>` |
| Volume qui ne s'attache pas | état du volume (`available` ?), une seule instance à la fois |
| Répartiteur `ONLINE` mais clients sans réponse | règles du groupe de sécurité des membres pour les **clients** (§6) |

## 8. Aller plus loin

- Libre-service par OpenTofu : `libre-service.md`.
- Architecture, décisions, limites connues : `README.md` (ce dossier), ADR-0100.
- Runbooks de la plateforme : `runbooks/` (RB-100 accueil d'une équipe, RB-101 mises à jour, RB-102 maintenance d'un calcul).
