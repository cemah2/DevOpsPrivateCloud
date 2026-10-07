# Dossier M06-E34 — Mise en service de `stat01` (exercice chronométré)

> À ouvrir à T0 seulement. Note l'heure maintenant dans la feuille de temps (en bas).

## Le besoin

> **Ticket CHG-760 (suite)** — *De : Claire Morel*
> La direction veut une page d'information interne du socle : la liste des services, leurs adresses, le contact d'astreinte. Le contenu est fourni (fichier `index.html` de ce dossier). Ce qui m'intéresse, c'est **comment** il est servi : la démonstration doit montrer que notre chaîne de mise en service fonctionne de bout en bout, sans geste manuel, avec la sécurité dès le premier jour.

## Exigences

| # | Exigence | Détail |
|---|---|---|
| 1 | Machine | VM `stat01`, VMID **2069**, VNet `vinfra`, 1 vCPU, 1 Go, disque 10 Go sur `local-nvme`, clone **complet** de l'image dorée `current`, pool `lab`, étiquettes `env-m06` et `role-statut` (pas `socle` : le service est temporaire), créée par OpenTofu (état ou configuration de ton choix, justifié dans le retour d'expérience). |
| 2 | Adresse | Attribuée par **NetBox** : la première adresse libre de la plage des adresses statiques de service du VLAN INFRA (PLAN : `.10-.49`). Aucune adresse écrite à la main dans le code. La VM existe dans NetBox (cluster `pve01`, `vmid` = 2069), avec son interface et son adresse primaire. |
| 3 | Nom | `stat01.par1.medisphere.internal` (A) et son PTR, créés **par le même code** que la VM ; résolus par les deux résolveurs, réponse validée DNSSEC (`ad`). |
| 4 | Accès d'administration | Clé d'hôte SSH **signée** par la CA SSH (aucune empreinte à accepter depuis `adm01`) ; connexion par certificat d'utilisateur ; rôles `base` et `ssh_durci` appliqués. |
| 5 | Service | nginx sert `index.html` (fourni, à ne pas modifier) en **HTTPS** sur 443, TLS 1.2 minimum ; le port 80 ne sert qu'au défi ACME et à la redirection vers HTTPS. |
| 6 | Certificat | Émis par `ca01` par **ACME**, nom `stat01.par1.medisphere.internal`, renouvelé automatiquement à 15 jours de l'expiration (même mécanisme que le reste du socle, M06-E27). |
| 7 | Filtrage | Rôle `pare_feu_local` : 443 depuis MGMT, le VPN d'administration et INFRA ; 80 depuis `ca01` seulement ; 22 depuis `adm01` et `runner01`. Aucune règle de `gw01` ajoutée **si** elle n'est pas nécessaire : justifie dans le retour d'expérience pourquoi il en faut une, ou non. |
| 8 | Supervision | `ms-verif-services` (M06-E29) surveille le certificat de `stat01` (expiration, nom, émetteur) ; aucune modification du script, seulement de sa configuration. |
| 9 | Sauvegarde | Décide et justifie : sauvegarde applicative, sauvegarde de VM, ou rien. |
| 10 | Traçabilité | Chaque changement passe par une MR (`plateforme/infra`, `plateforme/ansible`, `plateforme/outils` si besoin), fusionnée après pipeline vert. |

## Contenu à servir

[`index.html`](index.html) : à déposer tel quel par le rôle Ansible (il contient un témoin vérifié par le check).

## Vérification

À T5, depuis `adm01` : `lab/bin/check 06 34`. Tout doit être vert **avant** le retrait.

## Retrait (après la vérification)

Par le code : suppression de la VM, de ses objets NetBox (VM, interface, adresse), de ses enregistrements DNS, de son entrée de supervision, des règles de filtrage qui lui étaient propres. Vérifie qu'il ne reste rien (NetBox, DNS sur les deux serveurs faisant autorité, `qm status 2069`, configuration de `ms-verif-services`).

## Feuille de temps

| Jalon | Définition | Heure | Écart depuis T0 | Gestes manuels / commentaire |
|---|---|---|---|---|
| T0 | Ouverture du dossier | | 0 | |
| T1 | Plan OpenTofu relu (VM, NetBox, DNS) et MR ouverte | | | |
| T2 | VM démarrée, présente dans l'inventaire Ansible, SSH par certificat | | | |
| T3 | Service configuré (nginx, certificat ACME, filtrage) | | | |
| T4 | Supervision à jour, décision de sauvegarde prise | | | |
| T5 | `lab/bin/check 06 34` entièrement vert | | | |
| T6 | Service retiré, plus aucune trace | | | |

**Retour d'expérience** (une demi-page, dans `docs/socle/tests/` ou en commentaire de la MR de mise à jour de RB-060) : ce qui a pris le plus de temps, chaque geste manuel et l'outillage qui l'aurait évité, ce que tu changes dans RB-060, comment descendre sous une heure.
