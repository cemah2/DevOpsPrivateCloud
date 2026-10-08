# Dossier M08-E34 — Stockage de l'équipe MédiNotif (exercice chronométré)

> À ouvrir à T0 seulement. Note l'heure maintenant dans la feuille de temps (en bas).

## Le besoin

> **Ticket CHG-960 (suite)** — *De : Claire Morel* — *Copie : Sophie Laurent*
> MédiNotif envoie les notifications (SMS, courriels) de toutes nos applications. Pour sa recette, l'équipe a besoin d'un volume pour son courtier de messages, d'un petit partage de fichiers pour les modèles de messages, et d'un compte S3 pour archiver les accusés de réception. Mêmes règles que pour MédiAgenda et MédiDoc (M08-E31) : cloisonnement total, plafonds, sauvegarde, supervision, et tout dans le registre.
> Contact de l'équipe : `medinotif` (pas encore de compte GitLab : c'est toi qui ouvres les MR).

## Exigences

| # | Exigence | Détail |
|---|---|---|
| 1 | Identité | Une identité cephx **`client.medinotif`**, limitée à l'espace de noms RBD et au chemin CephFS de l'équipe ; aucun `allow *`. Trousseau remis par Vault (chemin inscrit au registre des secrets) ; copie de test sur `cephcli01` (`/etc/ceph/ceph.client.medinotif.keyring`, 600). |
| 2 | Bloc | Espace de noms **`medinotif`** dans `rbd-equipes`. Image **`rabbitmq-recette`** de **20 Gio** créée dans cet espace de noms. Plafond bloc de l'équipe : **30 Gio** (provisionné), appliqué selon le mécanisme retenu en E31. |
| 3 | Fichier | Groupe de sous-volumes **`medinotif`** dans `cephfs`, plafond **5 Gio** ; sous-volume **`modeles`** de **2 Gio** dans ce groupe. |
| 4 | Objet | Compte RGW **`medinotif`** (même modèle que le compte MédiDoc de E12), quota de compte **10 Gio** activé, utilisateur racine du compte créé ; identifiants d'accès remis par Vault. |
| 5 | Cloisonnement | Depuis `cephcli01`, `client.medinotif` réussit sur ses ressources et **échoue** sur celles de `mediagenda`, de `medidoc` et sur `rbd-test` (matrice d'essais consignée dans le retour d'expérience). |
| 6 | Capacité | Le quota du pool `rbd-equipes` couvre toujours la somme des plafonds bloc des trois équipes ; sinon, il est relevé par MR et la marge restante du cluster est vérifiée (`ceph df`) avant. |
| 7 | Sauvegarde | L'image `rabbitmq-recette` est désignée pour la sauvegarde nocturne (E25) par le mécanisme retenu en E31 ; la prise en compte est constatée (passage forcé du service ou passage de la nuit). |
| 8 | Supervision | La sonde `ms-verif-ceph` reste verte ; si ton mécanisme de plafond bloc repose sur une surveillance, MédiNotif y figure. |
| 9 | Documentation | `docs/stockage/allocations.md` (une ligne par ressource, ticket CHG-960), registre des secrets complété (identité cephx, identifiants S3 : emplacements, propriétaire, échéance — jamais les valeurs). |
| 10 | Traçabilité | Chaque changement passe par une MR fusionnée après pipeline vert (`plateforme/ceph`, `plateforme/ansible` si besoin, `plateforme/medisphere`). |

## Vérification

À T4, depuis `adm01` : `lab/bin/check 08 34`. Tout doit être vert.

## Feuille de temps

| Jalon | Définition | Heure | Écart depuis T0 | Gestes manuels / commentaire |
|---|---|---|---|---|
| T0 | Ouverture du dossier | | 0 | |
| T1 | MR ouvertes (code et registre), plan relu | | | |
| T2 | Identité, bloc et fichier livrés, cloisonnement testé | | | |
| T3 | Objet livré, sauvegarde et supervision constatées | | | |
| T4 | `lab/bin/check 08 34` entièrement vert, documentation fusionnée | | | |

**Retour d'expérience** (une demi-page, dans `docs/stockage/tests/` ou en description de la MR de mise à jour de ta procédure d'accueil) : ce qui a pris le plus de temps, chaque geste manuel et l'outillage qui l'aurait évité, ce qui manquait au registre des allocations, comment descendre sous 30 minutes.
