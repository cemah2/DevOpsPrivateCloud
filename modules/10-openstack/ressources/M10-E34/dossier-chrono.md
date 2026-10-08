# Dossier CHG-1160 — Environnement d'essai pour l'équipe MédiNotif

> À ouvrir à **T0** seulement. Note l'heure maintenant sur la feuille de temps (en bas).

## Le besoin

L'équipe MédiNotif (service d'envoi de notifications SMS et courriel) démarre une preuve de concept : deux « travailleurs » qui consommeront plus tard une file de messages (module 27). Pour l'instant, elle veut un environnement isolé, prêt à recevoir son code, avec un disque pour la file locale. Le stagiaire Lucas Martin suit le projet en observation : il doit **voir** l'environnement, sans rien pouvoir modifier.

## Exigences

**Identité et projet** (durable : par le code de la plateforme)
1. Projet `medinotif-essai` dans le domaine `medisphere`, description qui cite `CHG-1160`.
2. Quotas : 3 instances, 4 vCPU, 6 144 Mo de mémoire, 2 volumes, 30 Go de volumes, 1 IP flottante, 1 routeur, 2 réseaux.
3. Groupe `equipe-medinotif` (domaine `medisphere`) avec le rôle `member` sur le projet ; utilisateur `lucas.martin` avec le rôle `reader` sur le projet (s'il n'existe pas encore dans le domaine `medisphere`, crée-le par le même chemin que les autres personnages : le code d'identité de M10-E05/E23).

**Réseau**
4. Réseau `medinotif-net`, sous-réseau `medinotif-sn` en 192.168.60.0/24, DNS du socle (10.10.20.10, 10.10.20.16).
5. Routeur `medinotif-rt` relié à `ext-net` et à `medinotif-sn`.
6. Groupe de sécurité `medinotif-ssh` : SSH (TCP 22) depuis 10.10.10.0/24 et 10.255.1.0/24, et entre les membres du groupe (rebond de l'exigence 9) ; ICMP entre les membres du groupe. Aucune autre règle d'entrée, et aucune ouverte à `0.0.0.0/0`.

**Calcul et stockage**
7. Paire de clés `medinotif-cle` (clé publique de ton compte `admin` de `adm01`).
8. Instance `medinotif-worker01` : Rocky Linux 10, `m1.petit`, groupe `medinotif-ssh`, **une IP flottante**.
9. Instance `medinotif-worker02` : Debian 13, `m1.petit`, groupe `medinotif-ssh`, **sans** IP flottante, joignable en SSH depuis `medinotif-worker01` (rebond).
10. Volume `medinotif-file` de 10 Go, attaché à `medinotif-worker01`, système de fichiers XFS monté sur `/srv/file` et remonté au redémarrage.

**Preuves** (à noter dans la feuille de temps)
11. `ssh` depuis `adm01` vers `medinotif-worker01` par son IP flottante, puis rebond vers `medinotif-worker02` ; `ping` de `worker02` depuis `worker01`.
12. Avec les identifiants de `lucas.martin` : la liste des instances du projet s'affiche ; la création d'un volume est **refusée**.

**Retrait** (après la vérification)
13. Tout est retiré : ressources du projet, puis quotas, projet, groupe et rôles par le code (dans l'ordre de RB-100) ; le compte `lucas.martin` reste s'il existait avant.

## Feuille de temps

| Jalon | Heure | Remarques (gestes manuels et leur raison, blocages) |
|---|---|---|
| T0 — ouverture du dossier | | |
| T1 — projet, groupe et rôles (code d'identité), quotas (état `openstack-projets`) en place : MR fusionnées, playbook et apply faits | | |
| T2 — réseau, routeur, groupe de sécurité | | |
| T3 — instances, IP flottante, volume monté | | |
| T4 — preuves faites, `lab/bin/check 10 34` vert | | |
| T5 — retrait terminé | | |

**Temps T0 → T4** : ……… (cible : moins de 2 h)

## Retour d'expérience (une demi-page)

- Ce qui a pris le plus de temps, et pourquoi.
- Les gestes manuels, et ce qu'il faudrait changer (code, runbook) pour les supprimer.
- Ce que tu changes dans RB-100 (lien vers la MR).
