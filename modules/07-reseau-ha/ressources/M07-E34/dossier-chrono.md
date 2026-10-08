# Dossier M07-E34 — Point d'entrée `agenda-demo` (exercice chronométré)

> À ouvrir à T0 seulement. Note l'heure maintenant dans la feuille de temps (en bas).

## Le besoin

> **Ticket CHG-863 (suite)** — *De : Julien Petit*
> Pour la démonstration aux partenaires, j'ai une maquette statique de MédiAgenda. En attendant les vrais serveurs applicatifs (module 12), elle est servie par les deux serveurs Nginx de la maquette réseau, `srv01` et `srv02`, qui affichent leur nom. Il me faut une adresse propre, en HTTPS, qui tienne si l'un des deux serveurs ou l'un des deux répartiteurs tombe, et **qui ne soit pas visible depuis l'extérieur des locaux** : pas d'accès depuis le LAN maison, même par la redirection HTTPS de la bordure.

## Exigences

| # | Exigence | Détail |
|---|---|---|
| 1 | Nom | `agenda-demo.par1.medisphere.internal`, qui mène à la VIP des répartiteurs 10.10.70.200 (enregistrement A ou alias vers `lb.par1.medisphere.internal`), créé **par le code** (même chemin que les noms de M07-E13). |
| 2 | Serveurs | `srv01` et `srv02` (VMID 2075 et 2076, Nginx, port 80, déjà en service depuis M07-E08), sans modification de leur configuration. Section de serveurs **`be_agenda_demo`**, serveurs nommés **`srv01`** et **`srv02`**, répartition tour à tour, contrôle de santé HTTP applicatif (`GET /`, code 200). |
| 3 | Redondance | Le service répond si un serveur s'arrête, et si le répartiteur actif s'arrête (configuration identique sur `lb01` et `lb02`, générée par le rôle `haproxy`). |
| 4 | TLS | Certificat ACME (`ca01`) au nom `agenda-demo.par1.medisphere.internal` sur **les deux** répartiteurs, renouvelé automatiquement ; politique TLS et HSTS de M07-E28 ; HTTP redirigé vers HTTPS. |
| 5 | Marque | Chaque réponse porte l'en-tête `X-MediSphere-Service: agenda-demo` (ajouté par les répartiteurs). |
| 6 | Accès | Autorisé depuis 10.10.0.0/16 et le VPN d'administration (10.255.1.0/24) ; **toute autre source reçoit 403**, en particulier une requête venue du LAN maison par la redirection HTTPS de la VIP WAN. |
| 7 | Flux | Ce que les répartiteurs doivent joindre est ouvert dans la matrice commune des passerelles, au plus juste (sources, destinations, port), avec motif et référence `M07-E34`. Le filtrage local des répartiteurs est revu si nécessaire. |
| 8 | Supervision | `ms-verif-reseau` (M07-E29) contrôle le service de bout en bout et l'état des deux serveurs ; modification de **sa configuration** seulement. |
| 9 | Traçabilité | Chaque changement passe par une MR fusionnée après pipeline vert. |

## Vérification

À T5, depuis `adm01` : `lab/bin/check 07 34`. Tout doit être vert **avant** le retrait.

## Retrait (après la vérification)

Par le code : nom DNS, section de serveurs et règles des répartiteurs, certificat (suppression des fichiers et de l'unité de renouvellement ; révocation ou expiration : choix justifié), flux de la matrice, entrée de supervision. Vérifie qu'il ne reste rien (`dig` sur les deux résolveurs, `haproxy.cfg` des deux répartiteurs, `nft list ruleset` des deux passerelles, configuration de `ms-verif-reseau`).

## Feuille de temps

| Jalon | Définition | Heure | Écart depuis T0 | Gestes manuels / commentaire |
|---|---|---|---|---|
| T0 | Ouverture du dossier | | 0 | |
| T1 | MR ouvertes (DNS, répartiteurs, matrice) | | | |
| T2 | Certificats obtenus sur les deux répartiteurs | | | |
| T3 | Service servi par la VIP, deux serveurs `UP` | | | |
| T4 | Accès restreint prouvé, supervision à jour | | | |
| T5 | `lab/bin/check 07 34` entièrement vert | | | |
| T6 | Service retiré, plus aucune trace | | | |

**Retour d'expérience** (une demi-page, dans `docs/socle/tests/`) : ce qui a pris le plus de temps, chaque geste manuel et l'outillage qui l'aurait évité, ce que tu changes dans RB-070, comment descendre sous 30 minutes.
