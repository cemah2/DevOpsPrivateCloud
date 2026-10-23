# Parcours d'accueil et de départ d'une équipe

> Version 1.0 (F2-S01, PLAT-3201). Une copie de ce fichier est cochée par équipe, dans le ticket `DEV-` d'arrivée (ou de départ). La procédure technique est RB-320 ; ce parcours dit **quoi** vérifier et **avec qui**.

## Arrivée

### Avant (J-5 → J-1) — responsable de l'équipe + Plateforme

- [ ] Ticket `DEV-` d'arrivée ouvert, signé par le responsable de l'équipe et par Claire Morel (prestataire : contrat, date de fin, accord de Sophie Laurent).
- [ ] Nom court de l'équipe choisi (ni réservé, ni préfixe d'un autre).
- [ ] Liste des personnes (identifiant `prenom.nom`, rôle : responsable, développeur, lecteur).
- [ ] Besoins estimés : environnements, services prévus, mémoire et CPU, stockage ; données manipulées (données de santé ? oui/non).
- [ ] Offre de service lue par le responsable (`offre-de-service.md`), questions notées.
- [ ] Bilan de capacité refait (`capacite.md`) ; budget accepté.

### Jour J — Plateforme

- [ ] MR sur `plateforme/equipes` (fichier de l'équipe), relue, fusionnée ; heure de fusion notée.
- [ ] Propagation terminée : MR de rendu fusionnées dans les cinq dépôts cibles, applications passées.
- [ ] Comptes : premier mot de passe transmis à chaque personne par un canal séparé, changement imposé ; OTP enrôlé (obligatoire pour un prestataire).
- [ ] Vérifications de RB-320 § 2 (annuaire, locataire, espaces rattachés, quotas, coffre, AppProject, Grafana, route d'alertes, catalogue).
- [ ] Un membre de l'équipe se connecte au portail, à GitLab, à Argo CD, à Grafana, au coffre : chacun voit **son** périmètre et rien d'autre.
- [ ] Contrôle négatif : SSH vers une VM refusé ; `kubectl` en écriture dans `<equipe>-prod` refusé ; lecture de `kv/mediagenda/…` refusée.

### Premiers jours (J → J+5) — équipe, avec un parrain de la Plateforme

- [ ] Premier service créé par le modèle « Nouveau service » ; heure notée.
- [ ] Premier déploiement en `dev` (`Synced`/`Healthy`, URL qui répond) ; heure notée → **délai jusqu'au premier déploiement**.
- [ ] Tout ce qui a demandé l'intervention de la Plateforme est noté (ticket, attente, cause) dans `docs/accueil/mesures/`.
- [ ] Documentation du service visible dans le portail (TechDocs).

### Avant la production — équipe + Plateforme (revue de mise en production)

- [ ] SLO déclaré (Pyrra) et alertes de budget d'erreur routées vers l'adresse de l'équipe ; test de routage fait.
- [ ] Tableau de bord dans le dossier Grafana de l'équipe.
- [ ] Runbook de service minimal (que faire si l'alerte sonne, qui appeler, comment revenir en arrière).
- [ ] Secrets de production dans `kv/<equipe>/prod/…`, jamais ailleurs.
- [ ] Contact d'astreinte de l'équipe connu de Nadia Roussel.
- [ ] Première mise en production par MR, dans la fenêtre autorisée.

### Après un mois — responsable + Plateforme

- [ ] Retour d'expérience recueilli (satisfaction, frictions) ; quotas ajustés aux recommandations du VPA.

## Départ

### Départ d'une personne

- [ ] Le responsable prévient la Plateforme **le jour même** (ticket `DEV-`).
- [ ] Retrait du fichier de l'équipe (changement d'équipe) ou `etat: disabled` dans l'annuaire (départ de MédiSphère, RB-242) ; MR fusionnée.
- [ ] Vérifié : compte désactivé, retiré du groupe, plus membre du groupe GitLab ; jetons personnels GitLab révoqués ; sessions Keycloak fermées.

### Départ d'une équipe ou fin de contrat d'un prestataire

- [ ] Date de fin connue dès l'arrivée (prestataire : expiration posée sur les comptes) ; rappel à J-15.
- [ ] Inventaire de ce que l'équipe laisse : dépôts, images, espaces, volumes, secrets, tableaux, tickets ouverts ; qui reprend quoi (repreneur nommé).
- [ ] Données : à garder, exporter ou détruire, accord écrit du responsable et, pour des données de santé, de Sophie Laurent.
- [ ] MR `etat: retiree` ; propagation et application (plan de destruction lu et appliqué à la main).
- [ ] Jetons révoqués : jetons de groupe GitLab, jetons personnels, sessions Keycloak ; certificats SSH (16 h) expirés.
- [ ] Espaces et locataire retirés **explicitement** après l'inventaire (RB-320 § Départ), sauvegardes vérifiées avant.
- [ ] Revue d'accès refaite : plus aucune trace de l'équipe (annuaire actif, GitLab, Argo CD, coffre, RBAC du cluster).
- [ ] Preuves rangées dans `docs/accueil/departs/<equipe>.md`.
