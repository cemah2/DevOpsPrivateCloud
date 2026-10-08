# Réseau des projets OpenStack (PAR1)

> Modèle réseau offert aux équipes sur le cloud MédiSphère. Rédigé en M10-E08 (PLAT-1108) ; la politique de flux du VLAN 52 (sortie vers Internet, VPN, DNS) est dans `reseau-externe.md` (M10-E12) ; le choix d'OVN est justifié par l'ADR-0100.

## Le modèle

```
   adm01 / VPN ── bordure gw01/gw02 (10.10.52.1) ── VLAN 52 « ext-net » 10.10.52.0/24
                                                         │  (flat, physnet1, br-ex sur osctl01)
                                  IP flottantes et passerelles de routeurs : .200-.249
                                                         │
                                          ┌──────────────┴──────────────┐
                                          │ routeur du projet (OVN)     │  SNAT : sortie du sous-réseau
                                          │ ex. routeur-plateforme      │  DNAT+SNAT : une IP flottante
                                          └──────────────┬──────────────┘       → une adresse privée
                                                         │
                                 réseau du projet (Geneve, MTU 1442), ex. reseau-plateforme
                                 sous-réseau privé (DHCP d'OVN), ex. 172.16.10.0/24
                                                         │
                                                   instances (groupes de sécurité sur chaque port)
```

| Objet | Qui le crée | Exemple (projet `plateforme`) |
|---|---|---|
| Réseau externe `ext-net` | équipe Plateforme (code : `plateforme/openstack`, `playbooks/reseau-externe.yml`) | `ext-net`, sous-réseau `ext-sous-reseau` 10.10.52.0/24, sans DHCP |
| Réseau et sous-réseau du projet | l'équipe du projet | `reseau-plateforme`, `sous-reseau-plateforme` 172.16.10.0/24, DHCP, résolveurs 10.10.20.10 et 10.10.20.16 |
| Routeur | l'équipe du projet | `routeur-plateforme` : passerelle sur `ext-net`, interface sur le sous-réseau |
| Groupes de sécurité | l'équipe du projet | `ssh-icmp-admin` : TCP 22 et ICMP depuis 10.10.10.0/24 |
| IP flottante | l'équipe du projet (quota) | une adresse de 10.10.52.200-249, associée à un port d'instance |

## Ce qu'un projet peut faire

- créer ses réseaux privés (plages libres, à choisir hors de 10.10.0.0/16, 10.20.0.0/16, 10.30.0.0/16, 10.90.0.0/16 et 10.255.0.0/16 pour éviter toute ambiguïté de routage avec le lab), ses routeurs, ses groupes de sécurité ;
- brancher la passerelle de ses routeurs sur `ext-net` et y prendre des IP flottantes, dans la limite de ses quotas.

## Ce qu'un projet ne peut pas faire

- créer un réseau de type fournisseur (VLAN, flat) ni brancher une instance directement sur `ext-net` (réservé aux administrateurs) ;
- choisir l'adresse de passerelle de son routeur sur `ext-net` ou une IP flottante précise (sauf rôle administrateur) ;
- voir les ressources réseau des autres projets.

## MTU

| Réseau | Type | MTU | Pourquoi |
|---|---|---|---|
| `ext-net` | flat (VLAN 52) | 1500 | `global_physnet_mtu` de Neutron (1500 par défaut) |
| réseaux des projets | Geneve | 1442 | 1500 − 58 octets d'encapsulation retenus par Neutron (en-tête Geneve maximal du pilote + en-tête IP) |
| VLAN 51 (transport Geneve) | — | 9000 | les paquets encapsulés (≈ 1500 octets) passent sans fragmentation, avec une marge |

Augmenter la MTU des réseaux de projets au-delà de 1442 est possible (Neutron la calcule à partir de `global_physnet_mtu` et `path_mtu`), mais le trafic vers l'extérieur repasse par un réseau à 1500 : à étudier en M10-E12, pas à improviser.

## Trajet d'un paquet vers une IP flottante

Aller (`adm01` → IP flottante) : `adm01` (VLAN 10) → bordure → VLAN 52 → `ens21` de `osctl01` → `br-ex` → port de passerelle du routeur logique (OVN, sur le *chassis* `osctl01`) : **DNAT** IP flottante → adresse privée → commutateur logique du projet → tunnel Geneve sur le VLAN 51 → calcul qui héberge l'instance → port de l'instance (groupe de sécurité appliqué). Retour : chemin inverse, **SNAT** de l'adresse privée vers l'IP flottante sur `osctl01`.

Conséquence : toutes les IP flottantes dépendent de `osctl01` (seule passerelle OVN). S'il redémarre, les instances continuent de tourner et de se parler entre elles, mais ne sont plus joignables de l'extérieur jusqu'à son retour.

## Diagnostic rapide

```
admin@adm01:~$ openstack router show <ROUTEUR> -c external_gateway_info -c interfaces_info
admin@adm01:~$ openstack floating ip list --long
admin@adm01:~$ ssh osctl01 sudo docker exec ovn_nb_db ovn-nbctl lr-nat-list neutron-<ID-ROUTEUR>
admin@adm01:~$ ssh osctl01 sudo docker exec ovn_sb_db ovn-sbctl show
```
