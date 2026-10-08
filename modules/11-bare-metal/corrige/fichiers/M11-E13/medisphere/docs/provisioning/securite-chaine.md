# Sécurité de la chaîne de provisioning (SEC-1230)

> Analyse de M11-E13. Décision associée : ADR-0111.

## La chaîne et ses maillons

```
 serveur (ROM PXE / UEFI)
   │ 1. DHCP (relayé par gw01/gw02) ──────────► Kea dns01/dns02 : adresse, next-server, fichier
   │ 2. TFTP ─────────────────────────────────► pxe01 : undionly.kpxe / ipxe.efi
   │ 3. iPXE : DHCP à nouveau (classe iPXE) ──► Kea : https://pxe01…/boot.ipxe
   │ 4. HTTPS (racine MédiSphère intégrée) ───► pxe01 : boot.ipxe → mac-<mac>.ipxe → noyau, initrd,
   │                                            preseed ou kickstart (ajoutés à l'initrd par iPXE)
   │ 5. installateur ─────────────────────────► miroirs officiels (HTTP Debian, HTTPS Rocky)
   ▼ 6. premier démarrage, Ansible (clé d'hôte signée, rôle base)
```

| Maillon | Qui peut usurper | Ce qu'il y gagne | Protection retenue | Reste |
|---|---|---|---|---|
| 1. DHCP | tout poste du VLAN 60 (répond avant Kea) | désigner son propre serveur TFTP | isolation du VLAN 60 ; Kea autoritaire ; en production : *DHCP snooping* des commutateurs | usurpable dans le lab |
| 2. TFTP | idem, ou usurpation de 10.10.60.10 | servir un faux chargeur | binaire versionné et vérifié par Ansible sur `pxe01` ; en production : Secure Boot | usurpable sur le fil |
| 3. DHCP iPXE | idem | désigner une autre URL | l'URL n'apporte rien sans un certificat de notre PKI | — |
| 4. HTTPS | quiconque n'a pas un certificat MédiSphère pour `pxe01` | rien | iPXE ne fait confiance qu'à notre racine ; certificat ACME de 30 jours | compromission de `pxe01` ou de `ca01` |
| 5. Miroirs | attaquant sur le chemin vers Internet | rien : paquets refusés | Debian : `Release` signé (clés de l'archive dans l'initrd), sommes des paquets ; Rocky : HTTPS (autorité publique) et paquets signés GPG | compromission d'une clé d'archive |
| 6. Premier démarrage | — | — | aucune confiance accordée à la machine avant la signature de sa clé d'hôte par Ansible depuis `adm01`/`runner01` | — |

## Secrets

Aucun mot de passe dans les fichiers de réponse : root verrouillé, `admin` verrouillé (clé SSH seulement, sudo par règle dédiée), accès console de secours par le compte `secours` du rôle `base`. Historique Git vérifié (`git log -p -S 'password' -- preseed kickstart gabarits`) : <résultat>. Les fichiers de réponse ne sont servis qu'au VLAN 60 et à `adm01`.

## VLAN 60

Sortie : DNS (`dns01`, `dns02`), HTTP/HTTPS vers Internet hors LAN maison, DHCP relayé ; `pxe01` seul vers `ca01:443` (ACME) ; `ca01` vers `pxe01:80` (défi). Rien vers MGMT ni vers les autres services du socle. Entrée : `adm01` (administration).

## iLO de `hp01`

IPMI sur IP désactivé (CHG-1230) ; flux UDP 623 retiré. Compte `wb-redfish` : connexion seule (lecture). Le contrôle de l'alimentation n'est pas nécessaire aux exercices restants : privilège retiré (il avait été donné en M11-E08 pour l'essai facultatif).

## Ce qui reste non protégé (accepté dans le lab)

DHCP et TFTP (maillons 1-2) ; Secure Boot désactivé sur les VMs OVMF ; pas de signature des images (ADR-0111, option 3). Raison : lab isolé, VLAN 60 sans autre machine que les nôtres ; à traiter avec les commutateurs et serveurs physiques.
