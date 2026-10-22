# RB-241 — Arrivée d'une personne

*Propriétaire : équipe Plateforme. Relu par : Sophie Laurent (RSSI), Nadia Roussel (support). Version M24-E23 (SEC-2523). Revue : à chaque nouveau service branché au SSO, et au moins une fois par an.*

## Déclencheur

Ticket RH « arrivée » (date d'arrivée, nom, prénom, équipe, responsable), **et** validation écrite par le responsable de l'équipe des groupes demandés. Un groupe `plateforme-admins` ou `securite` exige en plus l'accord de Claire Morel (administration) ou de Sophie Laurent (sécurité). Pas de ticket validé : pas d'accès.

## Objectif et délais

Accès prêts le premier jour à 9 h. Lancement de la procédure au plus tard **J-2** (le job de l'annuaire est manuel et protégé : il faut un Maintainer disponible).

## Prérequis

- Accès Maintainer à `plateforme/identite` (fusion et job `annuaire:appliquer`).
- Ticket `admin` sur `ipa01` (`kinit admin`, mot de passe du Vault `critique`) pour le premier mot de passe.
- Le modèle d'autorisation (`docs/securite/identite/modele-autorisation.md`) pour savoir ce que donne chaque groupe.

## Étapes

| # | Étape | Commande ou écran | Contrôle | Si ça échoue |
|---|---|---|---|---|
| 1 | Choisir l'identifiant : `prenom.nom`, minuscules, sans accent ; s'il existe déjà (personne partie : jamais réutilisé), ajouter un chiffre | `grep -n '<IDENTIFIANT>' annuaire/personnes.yml` dans `~/src/identite` | aucune ligne | autre identifiant |
| 2 | MR « arrivée de `<IDENTIFIANT>` (ticket `<TICKET-RH>`) » : entrée dans `annuaire/personnes.yml` (identifiant, prénom, nom, `<IDENTIFIANT>@medisphere.internal`, titre) et ajout aux groupes validés dans `annuaire/groupes.yml` | éditeur, `git commit`, MR | le job `annuaire:verifier` de la MR montre **une** personne ajoutée et les seuls groupes demandés | corriger la MR ; ne jamais créer la personne à la main dans FreeIPA ou Keycloak |
| 3 | Revue de la MR par un second membre de l'équipe (et par Sophie si `plateforme-admins` ou `securite`), fusion | GitLab | approbation présente | — |
| 4 | Appliquer | pipeline de `main` → job manuel `annuaire:appliquer` | job vert, second passage sans changement | lire le journal du job ; rien n'est appliqué à moitié sans être visible (idempotence) |
| 5 | Premier mot de passe, **expiré d'office** | `[admin@ipa01 ~]$ kinit admin && ipa passwd <IDENTIFIANT> && kdestroy` (mot de passe généré par le gestionnaire, jamais écrit ailleurs) | `ipa user-status <IDENTIFIANT>` | — |
| 6 | Remettre le mot de passe provisoire par un canal différent du nom (téléphone, en main propre) ; la personne le change à sa première connexion : sur un poste inscrit `kinit <IDENTIFIANT>`, ou par l'interface de FreeIPA | — | la personne se connecte à `https://sso.par1.medisphere.internal/realms/medisphere/account/` | mot de passe expiré refusé par Keycloak : changer d'abord par `kinit` |
| 7 | Membres de `plateforme-admins` et `securite` : enrôlement OTP à la première connexion (imposé par le flux `navigateur-medisphere`, M24-E21) | console de compte | *Signing in* montre un OTP | si l'application est perdue : RB-242 § « perte de second facteur » |
| 8 | Droits qui ne découlent pas des groupes (à faire **seulement** s'ils sont demandés au ticket) : ACL PBS par personne (`proxmox-backup-manager acl update …`, M24-E15) ; groupe NetBox `sso-ecriture` pour un administrateur | voir M24-E15 | — | — |
| 9 | Premier accès guidé (30 min, avec un membre de l'équipe) : GitLab (bouton « SSO MédiSphère »), Grafana, Argo CD, `kubectl` par kubelogin (contexte `k8s-par1-oidc`, M24-E16), `step ssh login` (M24-E20) | — | `kubectl auth whoami` montre `oidc:<IDENTIFIANT>` et ses groupes | `lab/bin/check 24 17` |
| 10 | Clore le ticket avec les preuves (ci-dessous) | — | — | — |

## Ce qui découle des groupes, sans rien faire de plus

Connexion à tous les services en SSO ; rôles Grafana et organisation « Sécurité » ; rôles Argo CD ; membres Harbor ; ACL Proxmox VE ; droits Kubernetes (`rbac/oidc.yaml`) ; HBAC et sudo des machines inscrites ; groupes GitLab par `outils/synchro-gitlab.py` (pipeline horaire : lancer le pipeline planifié à la main si l'accès est attendu dans l'heure).

## Preuves conservées

| Preuve | Où | Durée |
|---|---|---|
| Ticket RH et validation du responsable | outil de tickets | durée du contrat + 5 ans |
| MR (auteur, relecteur, date, contenu) et pipeline d'application | `plateforme/identite` | historique Git |
| Premier accès (événement `LOGIN` du royaume) | Loki, locataire `audit`, `{service="keycloak"} \|= "<IDENTIFIANT>"` | rétention du locataire `audit` (1 an) |

## Retour arrière

Arrivée annulée : MR qui passe la personne à `etat: disabled` (jamais de suppression : l'identifiant reste réservé) et la retire des groupes, puis RB-242 § « départ normal ».
