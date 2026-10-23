# RB-320 — Accueillir, modifier ou retirer une équipe (équipe en code)

| | |
|---|---|
| Déclencheur | ticket `DEV-` d'arrivée, de changement ou de départ d'une équipe, signé par son responsable et par Claire Morel (prestataire : aussi Sophie Laurent) |
| Exécutant | équipe Plateforme (Maintainer de `plateforme/equipes`) |
| Durée | ≈ 30 min de travail (MR et relecture), ≈ 20 min d'application automatique |
| Références | ADR-0320, `plateforme/equipes` (README, schéma), offre de service et parcours d'accueil (`docs/accueil/`), RB-280 (équipes historiques) |

Variables : `EQUIPE=<equipe>`.

## 1. Préparer le fichier (MR sur `plateforme/equipes`)

1. Recueillir : nom court (pas un préfixe déjà pris), responsable, personnes (identifiant `prenom.nom`, rôle), environnements, besoins de capacité estimés, adresse de contact ; pour un prestataire, la date de fin du contrat.
2. Branche **protégée** `conf/equipe-$EQUIPE` (sinon pas d'aperçu : le coffre refuse les branches non protégées). Copier `equipes/medivisio.yaml` (équipe produit) ou `equipes/data.yaml` (équipe sans production).
3. Localement : `uv run outils/rendre.py --valider && uv run outils/capacite.py`. Si le bilan dépasse : réduire le budget, ou ouvrir la discussion capacité (Claire Morel) — jamais relever le ratio d'engagement sans ADR.
4. MR. Relire dans le pipeline : `capacite.md` (artefact), `apercu.diff` (ce qui changera dans chaque dépôt cible), l'aperçu GitLab (groupe, projet `gitops`, jetons). Relecteur : un autre membre de la Plateforme ; Sophie Laurent pour un prestataire.

**Vérifier** avant fusion : pipeline vert ; le diff ne touche que l'équipe visée (+ la liste des utilisateurs Capsule).

## 2. Fusionner et suivre la propagation

5. Fusion. Le pipeline de `main` crée le groupe GitLab, le projet `$EQUIPE/gitops`, les jetons de groupe (rangés dans OpenBao), puis ouvre une MR `chore(equipes): rendu…` dans `plateforme/identite`, `plateforme/secrets`, `plateforme/infra`, `plateforme/k8s`, `plateforme/gitops` (artefact `propagation.txt` : les liens).
6. Chaque MR se fusionne seule quand SON pipeline réussit. Une MR qui reste ouverte = un contrôle du dépôt cible a refusé le rendu : lire son pipeline, corriger **dans `plateforme/equipes`**, jamais dans le dépôt cible.
7. Applications automatiques : `annuaire:appliquer` puis `synchro:gitlab` (identite), `tofu:apply:equipes` (secrets, identite, infra/Grafana) — **sauf** destruction annoncée par un plan : lire le plan, puis lancer le job manuel `tofu:apply`. Argo CD synchronise `equipes-k8s`, `equipes-gitops` et `capsule`.
8. Prestataire (OTP) seulement : si le plan Keycloak échoue sur « group not found », synchroniser les groupes de la fédération (console : User federation → `ipa01` → Mappers → `groupes-ipa` → *Sync LDAP groups to Keycloak*) et relancer `tofu:plan`.

**Vérifier** (≤ 30 min après la fusion) :

```
admin@adm01:~$ ipa group-show $EQUIPE                                   # membres
admin@adm01:~$ kubectl get tenant $EQUIPE -o jsonpath='{.status.state} {.status.namespaces}{"\n"}'
admin@adm01:~$ kubectl get ns -l capsule.clastix.io/tenant=$EQUIPE -o custom-columns=NOM:.metadata.name,PROPRIETAIRE:.metadata.ownerReferences[0].name
admin@adm01:~$ kubectl get resourcequota,limitrange,secretstore -n $EQUIPE-<env>
admin@adm01:~$ kubectl -n argocd get appproject $EQUIPE && kubectl -n argocd get applicationset $EQUIPE
admin@adm01:~$ bao read identity/group/name/$EQUIPE && bao policy read $EQUIPE-equipe
admin@adm01:~$ kubectl get capsuleconfiguration default -o jsonpath='{.spec.users}{"\n"}'
admin@adm01:~$ lab/bin/check F2 02          # pour medivisio et data ; ms-verif-equipe $EQUIPE à partir de F2-S13
```

Et du point de vue de l'équipe : un membre se connecte au portail (son groupe apparaît dans le catalogue, ≤ 30 min) ; `kubectl auth whoami` montre `oidc:$EQUIPE` ; `bao kv list kv/$EQUIPE` répond après `bao login -method=oidc` ; `ssh` vers une VM est **refusé** (aucune règle HBAC).

## 3. Envoyer le parcours d'accueil

9. `docs/accueil/parcours-accueil.md`, liste « Arrivée » : cocher, envoyer au responsable avec l'offre de service, noter l'heure de fusion (mesure du délai d'accueil, `docs/accueil/mesures/`).

## Changer une équipe

Même chemin : MR sur `equipes/$EQUIPE.yaml` (personne en plus ou en moins, quota, nouvel environnement, nouveau service). Une personne qui part de l'équipe : la retirer du fichier (ou `etat: disabled` si elle quitte MédiSphère, voir RB-242). Un **quota réduit** sous la consommation actuelle n'évince rien, mais bloque les créations : prévenir l'équipe.

## Dérogations

- Synchroniser une production pendant la fenêtre interdite (vendredi 16 h → lundi 8 h) : l'astreinte ouvre une MR qui ajoute à l'AppProject (fichier rendu : donc dans `plateforme/gitops/equipes/$EQUIPE/projet.yaml` **par exception**, MR marquée `derogation`, ticket `INC-`) une fenêtre `allow` bornée, puis la MR inverse. Le rendu suivant l'efface : c'est voulu.
- Un besoin hors du chemin balisé (base, file, compartiment, exposition publique, appel vers une autre équipe) : ticket `DEV-`, traité selon l'offre de service.

## Départ (équipe ou prestataire)

1. MR : `etat: retiree` (et date dans le ticket). Effets à la propagation : personnes désactivées dans l'annuaire (jamais supprimées), groupe vidé, appartenances GitLab retirées, jetons de groupe révoqués, politique, groupe externe et rôles du coffre supprimés (**plan avec destruction : application manuelle**), AppProject, ApplicationSet, routes d'alertes, utilisateurs Capsule, cloison réseau retirés.
2. Ce que la CI ne fait **pas** : supprimer le locataire et les espaces (`Prune=false`, `preventDeletion`). Après accord écrit du responsable (données à garder, à exporter, à détruire) :

   ⚠️ **Attention** : supprimer le `Tenant` supprime **tous** ses espaces et leurs volumes. Avant de lever la protection : inventaire **par espace** (l'étiquette `capsule.clastix.io/tenant` est sur les espaces, pas sur les objets qu'ils contiennent), sauvegardes vérifiées (Velero, CNPG), accord écrit ; retire si besoin un espace à garder (`kubectl patch namespace … ownerReferences: []`, RB-280 § Retour arrière). Retour arrière tant que rien n'est supprimé : remettre `preventDeletion: true`.
   ```
   admin@adm01:~$ kubectl get tenant $EQUIPE -o jsonpath='{.status.namespaces}{"\n"}'
   admin@adm01:~$ for ns in $(kubectl get ns -l capsule.clastix.io/tenant=$EQUIPE -o name | cut -d/ -f2); do kubectl -n "$ns" get all,pvc,externalsecrets; done   # inventaire
   admin@adm01:~$ kubectl patch tenant $EQUIPE --type=merge -p '{"spec":{"preventDeletion":false}}'
   ```
3. Preuves (comptes désactivés, jetons révoqués, espaces retirés) dans `docs/accueil/departs/$EQUIPE.md`.
