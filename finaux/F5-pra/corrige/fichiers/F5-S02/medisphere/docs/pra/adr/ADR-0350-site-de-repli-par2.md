# ADR-0350 — Un site de repli tiède sur `hp01`

| | |
|---|---|
| Statut | Proposé par <MOI> le <AAAA-MM-JJ> ; **accepté** par Claire Morel le <AAAA-MM-JJ> |
| Ticket | PLAT-3502 |
| Relecteurs | Karim Benali (technique), Sophie Laurent (sécurité, conformité), Julien Petit (MédiAgenda) |
| Révision | après l'exercice 2026-1 (S13), à chaque nouveau contrat de service (MédiVisio), si `hp01` est remplacé |

## Contexte

- L'audit HDS relève un PRA non testé (trois rapports). Claire a obtenu un exercice réel dans deux mois, sans nouveau matériel.
- BIA (`bia.md`) et objectifs (`objectifs.md`) : MédiAgenda RTO 4 h / RPO 15 min ; MédiDoc 8 h / 1 h ; Legacy-RDV 8 h / 24 h ; MédiNotif 8 h.
- Ressources : `hp01` (Xeon E3-1220L v2, 2 cœurs, 16 Go, ≈ 2 To HDD) porte **PBS et toutes les sauvegardes du lab** ; lien inter-sites `wg0` sur le LAN maison ; Internet propre à `hp01`.
- Contraintes de sécurité : données de santé hébergées en France (HDS, EEE) ; aucun secret ni clé de PAR1 n'est utile s'il faut PAR1 pour l'utiliser (`dependances.md`).

## Options

| | A. Sauvegardes seules, reconstruction à la demande | B. Site **tiède** sur `hp01` | C. Site **chaud** | D. Prestataire externe (IaaS HDS) |
|---|---|---|---|---|
| Idée | rien ne tourne à PAR2 ; le jour J, on installe un hyperviseur (sur `hp01` ou un serveur loué), on reconstruit depuis le code (F1) et on restaure depuis PBS et `s3-01`… copié où ? | `hp01` devient aussi hyperviseur ; données, code, images répliqués en continu ; cluster de secours à zéro réplica ; coffre de secours arrêté | B + applications démarrées, base promue automatiquement, noms basculés par sonde | réplication vers un IaaS certifié HDS ; reprise chez lui |
| RTO MédiAgenda atteignable | 1 à 2 jours (installation, reconstruction F1 ≈ 8 h mesurées, restauration) | **≈ 2 h 30** (vagues de `dependances.md`) | < 30 min | 2 à 4 h (selon outillage) |
| RPO MédiAgenda | 24 h (sauvegardes de nuit ; les archives de WAL sont sur `s3-01`, perdu avec PAR1) | **≈ 7 min** (archive + `filer.sync`) | secondes (flux) | minutes |
| Coût matériel | nul | nul (`hp01`) | second hyperviseur à PAR2 (≈ 64 Go, ordre de grandeur 2 à 4 k€, à vérifier) | abonnement mensuel (ordre de grandeur 500 à 1 500 €/mois, à vérifier) + sortie de données |
| Entretien | faible ; mais le code de reconstruction s'abîme sans essai | moyen : réplications à surveiller, cluster à monter avec `k8s-par1`, exercice semestriel | élevé : deux productions | moyen ; dépendance contractuelle |
| Risque pour les sauvegardes | nul | **réel** : un hyperviseur sur l'hôte de PBS (mémoire, disque, mises à jour) | réel (même hôte si `hp01`) | nul |
| Retour à PAR1 | reconstruction | contrôlé (jetons CNPG, réplications inversées) | contrôlé | contrôlé, sortie de données |
| Conformité | PRA « sur le papier » : l'écart de l'audit demeure | PRA **testable** sur notre infrastructure | idem B | dépend du contrat (HDS, localisation, réversibilité) |

## Décision

**Option B : site tiède sur `hp01`**, avec les garde-fous ci-dessous. A ne tient pas l'objectif de MédiAgenda (RTO 4 h, RPO 15 min) et laisse les archives de WAL mourir avec PAR1. C n'est pas finançable aujourd'hui et `hp01` ne peut pas la porter (16 Go). D est l'option de la cible à trois ans ; elle exige un appel d'offres et une analyse de réversibilité (F7) : elle est notée comme **condition de révision**.

Choix techniques retenus (justifiés dans `dependances.md`) :

1. **Hyperviseur** : Proxmox VE 9.2 ajouté au Debian 13 de PBS 4.2 (paquet `proxmox-ve`), nom de nœud `pbs01`, **après go/no-go** et sauvegarde de la configuration de PBS ; stockage `par2-vms` **plafonné** (jeu ZFS avec quota, ou volume séparé) ; pool `par2`.
2. **Réseau** : `vmbr2` (PAR2 INFRA) routé par `hp01` ; sortie Internet propre (NAT `inet par2`) ; VPN d'administration de secours `wg1` sur `hp01`.
3. **Données** : `weed filer.sync -isActivePassive` compartiment par compartiment (liste minimale) ; `rclone` pour MédiDoc (RGW) ; *push mirrors* vers `adm02` ; `cosign copy` des images **déployées** vers `reg02` ; base de MédiAgenda en **topologie distribuée** CloudNativePG (seule manière d'avoir bascule **et** retour contrôlés).
4. **Confiance et secrets** : autorité intermédiaire « MédiSphère PAR2 Intermediate CA » (cérémonie) ; `bao-par2` restauré depuis l'instantané horaire et descellé par une copie de `kms01` restaurée depuis PBS ; enveloppe de reprise physique.
5. **Cluster** : `k8s-par2` mononœud, **même code** que `k8s-par1`, fichiers de site seulement ; L2 announcements de Cilium au lieu de BGP (pas de routeur BGP à PAR2) ; applications à zéro réplica ; Argo CD sur les miroirs.
6. **Noms** : noms de service globaux en CNAME de TTL 60 s ; `dns03` secondaire de toutes les zones, promu en PRA.

Ce que nous **refusons** : un hyperviseur PAR2 qui touche au datastore `ds-lab` ou à la configuration de PBS ; des secrets de reprise stockés uniquement à PAR1 ou uniquement dans un coffre qui a besoin de PAR1 ; des réplications « tout ou rien » (`ci-cache`, `conformite`… ne partent pas : minimisation) ; une bascule automatique (décision humaine, RB-350).

## Conséquences

- **Acceptées** : nœud unique à PAR2 (aucune haute disponibilité pendant un PRA) ; pas d'observabilité complète (sonde `ms-sonde-pra` en permanence, supervision minimale sur `adm02` pendant un PRA) ; pas de MédiVisio ni de Data ; gel des livraisons pendant un PRA ; `hp01` porte **à la fois** les sauvegardes et le site de repli : un sinistre qui toucherait PAR2 pendant un PRA ne laisserait que l'enveloppe et les archives hors site.
- **Charges nouvelles** : surveiller les retards de réplication (alertes, S04) ; monter `k8s-par2` en même temps que `k8s-par1` (F4 : « la chaîne d'abord ») ; renouveler l'intermédiaire PAR2 (3 ans) ; vérifier l'enveloppe (semestriel) ; exercice de PRA **semestriel** (`calendrier-tests.md`).
- **Changements à PAR1** : filer de `s3-01` exposé à `s3-02` seulement (gRPC protégé) ; `mediagenda-db` déclare la topologie distribuée ; en-tête `X-MediSphere-Site` sur les routes ; méthode `k8s-par2` dans OpenBao ; *push mirrors* ; job `cosign copy`.

## Risques

| Risque | Probabilité | Impact | Mesure |
|---|---|---|---|
| L'installation de PVE abîme PBS (paquets, noyau, ports) | faible | critique | go/no-go (simulation APT), sauvegarde de `/etc/proxmox-backup` hors de `hp01`, retour arrière écrit (RB-353), installation hors fenêtre de sauvegarde |
| `par2-vms` remplit le disque de `ds-lab` | moyenne | critique | limite technique (quota), alerte à 80 % |
| Mémoire de `hp01` saturée pendant un PRA (PBS + 10 Go de VMs) | moyenne | élevé | pas de tâche de vérification PBS pendant un PRA ; `kms01` restauré à 0,5 Go ; mémoire de `k8s-par2-n01` fixe (pas de surallocation sur `hp01`) |
| Réplication silencieusement arrêtée | moyenne | élevé (RPO réel ≠ RPO promis) | mesure du retard **côté destination**, alertes (S04), contrôle avant chaque exercice |
| Suppression à PAR1 propagée à PAR2 | faible | élevé | PBS reste la sauvegarde ; versionnage des compartiments ; règles de RB-354 |
| Enveloppe incomplète le jour J | moyenne | critique | vérification semestrielle en double contrôle ; répétition (S05, S08) |
| Divergence si PAR1 revient pendant le PRA | faible | élevé | neutralisation de PAR1 avant tout retour (RB-351) ; promotion sans jeton = ancien primaire reconstruit |

**Conditions de révision** : RTO de MédiAgenda mesuré > 3 h à l'exercice ; contrat de téléconsultation signé (MédiVisio dans le périmètre) ; remplacement ou panne de `hp01` ; option D chiffrée par un appel d'offres.
