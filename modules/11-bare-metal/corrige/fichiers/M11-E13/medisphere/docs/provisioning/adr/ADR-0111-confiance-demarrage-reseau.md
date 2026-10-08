# ADR-0111 — Confiance du démarrage réseau

- **Statut** : accepté
- **Date** : <AAAA-MM-JJ>
- **Décideurs** : Claire Morel, Sophie Laurent (RSSI), Karim Benali
- **Ticket** : SEC-1230

## Contexte et problème

Un serveur qui démarre sur le VLAN 60 exécute ce que le réseau lui donne : chargeur (TFTP), script iPXE, noyau et initrd (HTTP), fichier de réponse, paquets. DHCP et TFTP ne sont pas authentifiables. Il faut qu'à partir du chargeur iPXE plus rien ne s'exécute qui ne vienne de `pxe01`, sans dépendre d'un tiers et avec la PKI MédiSphère (step-ca, ECDSA P-256).

## Options envisagées

1. **Rien** (HTTP en clair, VLAN isolé) : simple ; tout poste du VLAN peut usurper `pxe01`.
2. **Racine MédiSphère intégrée au binaire iPXE (`TRUST=`) et HTTPS** : iPXE vérifie le certificat de `pxe01` (chaîne, nom, dates) ; tout ce qu'il télécharge est authentifié. Reconstruction du binaire si la racine change (tous les 10 ans) ; il faut une version d'iPXE qui vérifie l'ECDSA.
3. **Signature des images (`imgtrust`, `imgverify`)** avec une clé de signature de code : protège même en HTTP et même si `pxe01` est compromis en lecture seule ; impose de signer chaque script et chaque noyau à chaque rendu (clé de signature dans la CI), et de gérer une seconde PKI.
4. **Secure Boot UEFI (shim signé, iPXE 2.0)** : protège le chargeur lui-même ; nécessite un shim signé par Microsoft ou l'enrôlement de nos clés dans chaque micrologiciel ; ne couvre pas les machines BIOS.

## Décision

Option 2, maintenant : binaire iPXE construit par `ipxe/construire-ipxe.sh` (version épinglée, racine MédiSphère seule racine de confiance), HTTPS pour tout ce que télécharge iPXE, fichiers de réponse remis par iPXE dans l'initrd (les installateurs ne connaissent pas notre racine), paquets depuis les miroirs officiels (authentifiés par leurs signatures). L'option 3 est réévaluée si `pxe01` devient multi-site ; l'option 4 à l'arrivée des serveurs physiques (Secure Boot exigé par Sophie pour la production).

## Conséquences

- Positives : usurpation de `pxe01` impossible après le chargeur ; fichiers de réponse plus jamais servis en clair ; aucun tiers de confiance.
- Négatives : DHCP et TFTP restent usurpables (un faux chargeur peut toujours être servi : protection par l'isolation du VLAN 60 et, en production, la surveillance DHCP des commutateurs) ; reconstruction et redéploiement du binaire à chaque changement de racine ou de version d'iPXE ; diagnostic TLS plus difficile (codes d'erreur iPXE).
- Actions : procédure de construction dans RB-110 ; empreintes des binaires dans `host_vars/pxe01/pxe.yml` ; revue annuelle de la version d'iPXE (avis de sécurité) ; Secure Boot à traiter avec les serveurs physiques (module 26).
