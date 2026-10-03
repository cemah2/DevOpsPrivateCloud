# ADR-0002 — Sauvegarder PAR1 vers PAR2 avec Proxmox Backup Server, chiffré côté client

- Statut : accepté
- Date : 2026-10-XX
- Décideurs : Claire Morel
- Consultés : Sophie Laurent (RSSI), Nadia Roussel (support/astreinte), Karim Benali

## Contexte et problème

Le socle PAR1 (`gw01`, `adm01`, `dns01`, puis GitLab, NetBox, MinIO…) tourne sur un seul hyperviseur, `pve01`. L'ancien serveur PAR2 (`hp01`, 16 Go RAM, ~2 To HDD) est disponible. Il faut une stratégie qui permette de restaurer une VM, un fichier, ou la configuration de l'hyperviseur, y compris après la perte totale de PAR1, avec des données qui seront à terme des données de santé (HDS).

## Facteurs de décision

- Objectifs : RPO ≤ 24 h pour le socle ; RTO ≤ 30 min pour une VM du socle, ≤ 4 h pour reconstruire `pve01`.
- Sécurité HDS : chiffrement des sauvegardes hors site, clé jamais présente sur le site de sauvegarde, traçabilité.
- Capacité : ~2 To de HDD à PAR2, débit limité par le tunnel WireGuard (et le LAN domestique).
- Intégrité : vérification régulière des sauvegardes ; restaurations testées (exigence d'audit).
- Exploitation : outil intégré à Proxmox, notifications, peu de scripts maison ; compétences de l'équipe.
- Coût : pas de licence obligatoire.

## Options envisagées

1. Proxmox Backup Server sur `hp01` (bare-metal), sauvegardes `vzdump` incrémentales, chiffrées côté client, via le tunnel `wg0`.
2. `vzdump` en fichiers (`.vma.zst`) vers un partage NFS/SMB sur `hp01`.
3. Outil générique (Restic/Borg/Veeam Agent) dans chaque VM, vers un dépôt sur `hp01` ou dans MinIO.
4. Réplication ZFS (`zfs send/receive`, réplication Proxmox) vers `hp01` installé en Proxmox VE.

## Décision

Option retenue : « PBS sur `hp01` », parce qu'elle fournit nativement l'incrémental à déduplication (le volume tient dans 2 To), la vérification des sauvegardes, le chiffrement côté client (la clé reste à PAR1), la restauration de fichiers et la restauration à chaud, intégrés à Proxmox et à son système de notifications.

Paramètres retenus :
- Tâche `vzdump` quotidienne des VMs du pool `lab` (mode *snapshot*, agent QEMU et *fs-freeze*), vers le stockage `pbs-par2`, namespace `par1`.
- Configuration de `pve01` sauvegardée chaque jour en sauvegarde de type `host` (M00-E30).
- Rétention : 7 quotidiennes, 4 hebdomadaires, 6 mensuelles (*prune* côté PBS), GC quotidien, vérification hebdomadaire des nouveaux instantanés et re-vérification mensuelle.
- Chiffrement côté client (AES-256-GCM) ; clé exportée en paperkey et conservée hors ligne, hors des deux sites.
- Transport par le tunnel `wg0` (double chiffrement : transport et contenu).
- Restauration testée chaque mois (procédure M00-E37) et après chaque changement majeur.

### Conséquences

- Positives : RPO 24 h et RTO mesuré de ~10-15 min pour une petite VM ; volumétrie maîtrisée par la déduplication ; PAR2 ne peut pas lire les données ; vérification automatique de l'intégrité.
- Négatives :
  - perte de la clé = perte de toutes les sauvegardes chiffrées (procédure de conservation de clé obligatoire) ;
  - une seule copie hors site et sur un seul support (HDD unique, pas de RAID) : règle 3-2-1 non satisfaite (pas de copie hors ligne/immuable) ;
  - `hp01` et `pve01` sont dans le même bâtiment dans le lab : le « hors site » est simulé ;
  - la cohérence applicative des bases de données n'est pas garantie par `fs-freeze` seul ;
  - dépendance au tunnel et à `gw01` : si `gw01` tombe, plus de sauvegarde ni de restauration via le chemin nominal.
- Actions induites :
  - supervision des tâches (notifications M00-E29, puis métriques module 21) ;
  - copie supplémentaire : synchronisation PBS vers un second datastore ou une bande/disque amovible (à décider, ticket à ouvrir) ;
  - sauvegardes applicatives des bases (module 27 : CloudNativePG + objets S3) ;
  - procédure d'accès à PBS sans `gw01` (route directe via le LAN, documentée dans le runbook de restauration) ;
  - PRA complet testé au final F5.

## Analyse des options

### PBS sur hp01
- Pour : incrémental à déduplication, chiffrement client, vérification, restauration fichier et à chaud, intégration Proxmox, notifications, namespaces.
- Contre : HDD unique lent pour la vérification et le GC ; réinstallation de `hp01` (sauvegarde préalable des photos) ; nouvel outil à maîtriser.

### vzdump en fichiers sur NFS
- Pour : simple, format autonome (un fichier = une VM), restaurable sans PBS.
- Contre : sauvegardes complètes à chaque fois (volume et durée × N), pas de déduplication, pas de vérification native, chiffrement à ajouter à la main, NFS à travers un tunnel sensible aux coupures.

### Outil générique dans les VMs
- Pour : sauvegarde applicative fine, indépendante de l'hyperviseur, dépôts chiffrés (Restic/Borg).
- Contre : ne restaure pas une VM entière (il faut la reconstruire), un agent par VM à gérer, ne couvre pas les VMs de lab éphémères ; complémentaire plutôt qu'alternatif.

### Réplication ZFS vers un Proxmox à PAR2
- Pour : RPO de quelques minutes, bascule rapide (VM prête à démarrer).
- Contre : ce n'est pas une sauvegarde (une corruption ou une suppression est répliquée), pas d'historique long, exige ZFS des deux côtés et un cluster ; 16 Go de RAM à PAR2 ne suffisent pas à faire tourner le socle. Sera étudiée au module 09 comme complément.

## Liens

- PLAN.md §4.3 bis ; exercices M00-E20 à M00-E23, M00-E30, M00-E36, M00-E37 ; final F5 (PRA).
- Documentation PBS : chiffrement côté client, maintenance des datastores.
