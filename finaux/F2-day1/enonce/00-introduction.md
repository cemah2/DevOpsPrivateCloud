# Final F2 — Introduction : Day 1, accueillir les équipes

## Trois arrivées le même mois

Lundi, 8 h 40. La reconstruction du Day 0 est derrière vous : `k8s-par1` est revenu depuis le code, l'étiquette `day0-v1` est posée, l'audit HDS a eu sa démonstration. Dans la boîte de Claire Morel, trois messages attendent depuis vendredi. Inès Garnier, qui monte **MédiVisio**, la nouvelle équipe produit de téléconsultation, veut « un premier service en ligne cette semaine, pas ce trimestre ». Hugo Bernard, analyste de la nouvelle **équipe Data**, doit sortir les statistiques d'activité demandées par la direction et demande « juste un accès en lecture à la base de prod ». Julien Petit annonce que **AxiomDev**, le prestataire retenu pour développer la fonctionnalité de rappels intelligents de MédiAgenda, commence dans trois semaines, pour trois mois ; Marc Vidal, leur chef de projet, enverra la liste des développeurs.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Day 1 — la plateforme doit servir
>
> Bonjour,
>
> On a construit la plateforme et on sait la reconstruire. Maintenant elle doit **servir**, et je ne veux pas que l'accueil de ces trois équipes se fasse à coups de tickets et de copier-coller du RB-280. Ce que j'attends :
> 1. une **offre de service** écrite : ce qu'on fournit, ce qu'on ne fournit pas, qui est responsable de quoi, comment on nous joint ;
> 2. une équipe se crée **en un changement relu** : identité, dépôts, locataire, quotas, secrets, déploiement, tableaux de bord, alertes. Même chose pour la modifier ou la faire partir ;
> 3. MédiVisio **en production** par le chemin balisé, avec ses alertes et son SLO, et on **mesure** le temps qu'il lui a fallu ;
> 4. l'équipe Data **autonome** sur ses bases et ses traitements, **sans jamais** toucher à la production — Sophie y tient, moi aussi ;
> 5. AxiomDev avec des accès **bornés dans le temps et le périmètre**, audités, et **retirés proprement** à la fin du contrat ;
> 6. à la fin, une recette, et un retour d'expérience honnête : ce qui a coincé, ce qu'on change.
>
> Rien ne passe à la main : Git, la CI, Argo CD, comme d'habitude. Et la capacité des travailleurs n'est pas extensible : fais le compte avant de promettre des quotas.
> Claire

---

## Ce que tu construis dans ce final

| Phase | Fichier | Scénarios | Ce qui en sort |
|---|---|---|---|
| 1. Cadre | [`01-cadre.md`](01-cadre.md) | S01 à S03 | offre de service et parcours d'accueil ; projet **`plateforme/equipes`** (« équipe en code ») ; équipes `medivisio` et `data` créées par lui ; réponses de conception multi-locataire |
| 2. MédiVisio | [`02-medivisio.md`](02-medivisio.md) | S04 à S06 | service `medivisio/consultation` du modèle à la production : catalogue, image signée, Argo CD, secrets, SLO, alertes, tableau de bord, runbook ; délai jusqu'au premier déploiement mesuré |
| 3. Data | [`03-data.md`](03-data.md) | S07 à S09 | bases CloudNativePG en libre-service, extraction pseudonymisée, traitements par lots, refacturation interne ; réponse à la demande d'accès à la production |
| 4. Prestataire | [`04-prestataire.md`](04-prestataire.md) | S10 à S12 | comptes datés, OTP, accès limités à `mediagenda/api` et `mediagenda-axiomdev`, revue d'accès, départ |
| 5. Recette | [`05-recette.md`](05-recette.md) | S13, S14 | outil `ms-verif-equipe`, étiquette **`day1-v1`**, retour d'expérience et feuille de route |

Durée indicative : 40 à 55 heures, dont 14 à 18 pour la phase 1 (S02 est le plus long scénario du final) et 10 à 14 pour la phase 2.

## Architecture visée en fin de phase 2

```
                    plateforme/equipes (equipes/<equipe>.yaml)  ◀── MR relue (ou modèle Backstage « nouvelle-equipe »)
                         │ CI : valider · bilan de capacité · rendre · créer dans GitLab · propager
       ┌─────────────────┼──────────────────┬──────────────────────┬────────────────────┬──────────────────┐
       ▼                 ▼                  ▼                      ▼                    ▼                  ▼
 plateforme/identite  plateforme/secrets  plateforme/infra      plateforme/k8s       plateforme/gitops   GitLab
 annuaire (ipa01),    politiques, groupe  (observabilite-       locataire Capsule,   AppProject,         groupe <equipe>,
 synchro GitLab,      externe, rôles ESO  grafana) dossier et   espaces, quotas,     ApplicationSet,     <equipe>/gitops,
 OTP (Keycloak)       et CI (OpenBao)     équipe Grafana        coffre, alertes      dépôts, Capsule     jetons de groupe
                                                                       │                    │
                                                                       ▼                    ▼
   portail (Backstage) ── modèle « Nouveau service » ──▶ medivisio/consultation ──CI (signée)──▶ Harbor
        catalogue : Group medivisio (LDAP), Component medivisio-consultation      │ promotion (MR)
                                                                                   ▼
                                          medivisio/consultation-deploiement ──▶ Argo CD ──▶ medivisio-dev
                                                                              (MR)          medivisio-recette
                                                                              (MR, sync manuelle) medivisio-prod
   Prometheus/Pyrra (SLO) ──▶ Alertmanager ──▶ medivisio@ (Mailpit) ; critiques ──▶ astreinte@
```

---

## État d'entrée : `day0-v1`

Ce final suppose le Day 0 réussi (F1) et l'état de fin du bloc G. Avant S01 :

```
admin@adm01:~$ lab/bin/check F1 14
admin@adm01:~$ git -C ~/medisphere fetch --tags && git -C ~/medisphere tag -l 'day0-v1'
admin@adm01:~$ lab/bin/check 28 25 && lab/bin/check 27 25 && lab/bin/check 26 46 && lab/bin/check 25 46 && lab/bin/check 24 46
admin@adm01:~$ kubectl get tenants.capsule.clastix.io
admin@adm01:~$ kubectl get applications.argoproj.io -n argocd | grep -Ev 'Synced +Healthy'
admin@adm01:~$ kubectl get priorityclasses | grep medisphere
```

Attendu : les checks verts ; l'étiquette `day0-v1` ; les locataires `mediagenda`, `medidoc`, `medinotif` à l'état `Active` ; aucune Application hors `Synced`/`Healthy` (la seconde commande ne doit afficher que l'en-tête) ; les quatre classes `medisphere-critique`, `-standard`, `-ci`, `-lot`. Si F1 n'a pas été fait, l'état de fin du bloc G suffit (`lab/bin/check 29 25` et ceux ci-dessus) : note-le dans `docs/accueil/README.md`.

## Personnages ajoutés

| Personnage | Identifiant | Rôle | Équipe (groupe) |
|---|---|---|---|
| **Inès Garnier** | `ines.garnier` | Lead dev de MédiVisio, responsable de l'équipe | `medivisio` |
| Léo Fabre | `leo.fabre` | Développeur MédiVisio | `medivisio` |
| **Hugo Bernard** | `hugo.bernard` | Analyste de l'équipe Data, responsable | `data` |
| Sarah Colin | `sarah.colin` | Ingénieure Data | `data` |
| **Marc Vidal** | `marc.vidal` | Chef de projet d'AxiomDev (prestataire) | `ext-axiomdev` (phase 4) |
| Yanis Perrin | `yanis.perrin` | Développeur d'AxiomDev | `ext-axiomdev` (phase 4) |

Les personnages déjà connus gardent leur rôle (PLAN §2) : Claire Morel arbitre, Karim Benali relit, Sophie Laurent tient la sécurité et les données de santé, Julien Petit accueille AxiomDev, Nadia Roussel tient l'astreinte.

### Comptes à créer

Aucun compte n'est créé à la main. Les personnes de MédiVisio et de Data entrent dans l'annuaire **par le mécanisme de S02** ; celles d'AxiomDev en S10. Ce qui existe avant S02 et ce que tu prépares :

| Compte | Où | Quand | Comment |
|---|---|---|---|
| `ines.garnier`, `leo.fabre`, `hugo.bernard`, `sarah.colin` | FreeIPA → Keycloak (fédération) → GitLab, Grafana, Argo CD, portail, coffre (SSO) | S02 | fichier de l'équipe, puis premier mot de passe (`ipa passwd`, expiré d'office, RB-241) ; leur compte GitLab naît à leur **première connexion SSO** |
| Compte de service GitLab pour ton mécanisme (nom de référence : `svc-equipes`) | GitLab | S02 | comptes de service GitLab (Free depuis 18.11) ; jeton rangé dans OpenBao, jamais dans une variable de CI |
| `marc.vidal`, `yanis.perrin` | comme ci-dessus, **datés** | S10 | fichier de l'équipe `ext-axiomdev` |

**Jouer les personnages.** Pour agir « en tant qu'Inès » (portail, GitLab, coffre, Argo CD), ouvre une fenêtre de navigation privée et connecte-toi avec son compte ; en ligne de commande, `kubelogin` et `bao login -method=oidc` ouvrent le navigateur de la même façon (M24, M25). Note ses mots de passe dans `~/.config/workbook/personnages.env` (600), jamais dans un dépôt.

## Mémoire et capacité

Profil de travail des blocs F et G **inchangé** : socle v5 + `ceph-par1` + `k8s-par1`, ≈ 111 Go sur 128 (PLAN §3.3, §4.14). F2 n'ajoute **aucune VM** (plage 3200-3299 réservée, inutilisée) : les nouvelles équipes vivent dans les trois travailleurs (10 Go chacun). Chaque quota accordé est donc prélevé sur leur marge : S02 commence par un **bilan de capacité** (*requests* réservées contre allouable, par travailleur) et le refait à chaque arrivée. `k8s-w03` porte la marque `dedie=bdd:NoSchedule` (M14) : seules les bases y vont.

## Format de référence du fichier d'équipe

S02 te laisse concevoir le mécanisme, mais pas le **contrat** : les phases suivantes (Data, AxiomDev, l'outil `ms-verif-equipe` de la recette) lisent le même fichier. Le projet s'appelle **`plateforme/equipes`** ; chaque équipe y est décrite par **`equipes/<equipe>.yaml`** ; le modèle Backstage s'appelle **`nouvelle-equipe`**. Le fichier suit ce format (tu peux ajouter des champs ; tu ne renommes pas ceux-ci) :

```yaml
apiVersion: equipes.medisphere.internal/v1
kind: Equipe
metadata:
  nom: <equipe>                 # = nom du fichier ; groupe de l'annuaire et de GitLab, locataire, préfixe des espaces
  ticket: DEV-NNNN              # demande d'origine
spec:
  description: <une phrase>
  type: interne                 # interne | prestataire
  etat: active                  # active | retiree
  responsable: <identifiant>    # une des personnes ci-dessous
  contact: <equipe>@medisphere.internal          # destinataire des alertes
  expiration: AAAA-MM-JJ        # prestataire : obligatoire (fin des accès)
  personnes:
    - identifiant: prenom.nom   # aussi : prenom, nom, courriel, titre
      role: responsable         # responsable | developpeur | lecteur
      # etat: disabled ; expiration: AAAA-MM-JJ (facultatifs)
  identite:
    otp_obligatoire: false      # true obligatoire pour un prestataire
  gitlab:
    groupe: <equipe>
    externe: false              # true obligatoire pour un prestataire
  kubernetes:                   # absent = pas de locataire propre
    environnements:             # un espace <equipe>-<environnement> par entrée
      <environnement>:
        quota: {requests.cpu: …, requests.memory: …, limits.memory: …, pods: "…", persistentvolumeclaims: "…", requests.storage: …}
        signature_exigee: true  # images medisphere/* signées exigées dans cet espace
        synchronisation: automatique   # automatique | manuelle (production)
        alertes: true           # route d'alertes de l'équipe pour cet espace
    libre_service: {espaces: N, quota: {…}}
    budget: {requests.cpu: …, requests.memory: …, limits.memory: …, pods: "…"}   # plafond de tout le locataire
    classes_priorite: {autorisees: [medisphere-…], defaut: medisphere-standard}
    classes_stockage: [ceph-rbd]
  secrets:
    ecriture: [<environnement>…]  # kv/<equipe>/<environnement>/* écrits par l'équipe elle-même
  services: [<service>…]          # services livrés par le chemin balisé (rôles CI : signature, promotion)
  observabilite:
    grafana: {titre_dossier: <titre>}
```

Les équipes de ce final et leurs environnements : `medivisio` (`dev`, `recette`, `prod` → espaces `medivisio-dev`, `medivisio-recette`, `medivisio-prod`) ; `data` (`traitements` → `data-traitements`) ; `ext-axiomdev` (S10 : pas de locataire propre, un espace `mediagenda-axiomdev` dans le locataire `mediagenda`).

## Faits techniques du final

| Élément | Valeur |
|---|---|
| Versions | celles du bloc G et de F1 ([`annexes/versions-finaux-F1-F4.md`](../../../annexes/versions-finaux-F1-F4.md)) : F2 n'introduit aucun outil. Rappels utiles : Capsule 0.15 (`Tenant` `capsule.clastix.io/v1beta2`), Argo CD 3.5 (ApplicationSet, `goTemplate`), Backstage 1.56 (*scaffolder*), OpenBao 2.7 (fournisseur OpenTofu `hashicorp/vault ~> 5.13`), Keycloak 26.8 (`keycloak/keycloak ~> 5.10`), FreeIPA 4.13 (`freeipa.ansible_freeipa`), Grafana 13.2 (fournisseur 4.50.x), kube-prometheus-stack 92.x (Alertmanager 0.34), Pyrra 0.10, Kyverno 1.19 (politiques CEL), ESO 2.13 |
| Projets GitLab nouveaux | `plateforme/equipes` (S02) ; groupes `medivisio`, `data` (S02) ; `medivisio/consultation` et `medivisio/consultation-deploiement` (S04, noms de référence) |
| Espaces | `medivisio-dev`, `medivisio-recette`, `medivisio-prod` (locataire `medivisio`) ; `data-traitements` (locataire `data`) ; `mediagenda-axiomdev` (locataire `mediagenda`, S10) |
| Adresses publiées (référence) | `https://consultation-dev.apps.par1.medisphere.internal`, `https://consultation-recette.apps.par1.medisphere.internal`, `https://consultation.apps.par1.medisphere.internal` (production) |
| Coffre | `kv/<equipe>/<environnement>/<secret>` (convention du M25) ; MédiVisio : `kv/medivisio/<env>/consultation` |
| Alertes | Mailpit : `medivisio@medisphere.internal`, `data@medisphere.internal` ; critiques aussi vers `astreinte@` (règle du M21) |
| Tickets | `PLAT-32xx`, `DEV-32xx`, `SEC-32xx` (`xx` = numéro du scénario) |
| Documentation | `docs/accueil/` de `plateforme/medisphere` (ci-dessous) ; ADR `ADR-0320` et suivants, runbooks `RB-320` et suivants |
| Étiquette de fin | **`day1-v1`** sur `plateforme/medisphere` (S13) |

### `docs/accueil/`

```
docs/accueil/
├── README.md                    # index du dossier (créé en S01)
├── offre-de-service.md          # S01
├── parcours-accueil.md          # S01 (arrivée et départ)
├── capacite.md                  # S02 (bilan de capacité, mis à jour à chaque arrivée)
├── reponses/                    # S03 (questions de conception), S09 (réponse à DEV-3209)
├── mesures/                     # S04, S05 (délais mesurés), S08 (refacturation)
├── journal/                     # journaux de diagnostic : AAAA-MM-JJ-F2-SXX-<sujet>.md
├── departs/                     # S12 (preuves de départ)
├── adr/                         # ADR-0320…
├── runbooks/                    # RB-320…
└── retour-experience.md         # S14
```

### Variables de `lab/lab.env`

Facultatives ; les valeurs par défaut conviennent si tu gardes les noms de référence :

```
WB_F2_DOC=docs/accueil                                   # dossier de la documentation dans plateforme/medisphere
WB_F2_PROJET_EQUIPES=plateforme/equipes                  # projet de l'équipe en code (S02)
WB_F2_EQUIPES="medivisio data"                           # équipes vérifiées par check-S02
WB_F2_PROJET_CODE=medivisio/consultation                 # projet du code de MédiVisio (S04)
WB_F2_PROJET_DEPLOIEMENT=medivisio/consultation-deploiement
WB_F2_COMPOSANT=medivisio-consultation                   # entité Component du catalogue
WB_F2_IMAGE=medisphere/medivisio-consultation            # dépôt Harbor (projet/dépôt)
WB_F2_DEPLOIEMENT=consultation                           # nom du Deployment dans medivisio-<env>
WB_F2_URL_DEV=https://consultation-dev.apps.par1.medisphere.internal
WB_F2_URL_RECETTE=https://consultation-recette.apps.par1.medisphere.internal
WB_F2_URL_PROD=https://consultation.apps.par1.medisphere.internal
```

Les checks réutilisent `WB_GITLAB_*`, `WB_K8S_KUBECONFIG`, `WB_ARGOCD_*`, `WB_HARBOR_*`, `WB_GRAFANA_*`, `WB_AM_URL`, `WB_PROM_URL`, `WB_IPA_CHECKS_FILE`, `WB_OPENBAO_CHECKS_FILE`, `WB_KEYCLOAK_CHECKS_FILE`, `WB_BACKSTAGE_*` ; la panne de S06 lit `WB_GITLAB_ADMIN_TOKEN_FILE` et `WB_K8S_ADMIN_KUBECONFIG`.

---

## Règles du final

1. **Rien à la main.** Tout ce qu'une équipe reçoit vient d'un changement relu dans Git, appliqué par une CI ou par Argo CD. Une exception est écrite (ticket, journal, date de fin).
2. **Une seule source par équipe.** Après S02, une personne, un quota ou un droit d'équipe ne se change que dans `equipes/<equipe>.yaml`. Tu ne corriges jamais un fichier produit par ton mécanisme dans un dépôt cible.
3. **Moindre privilège, des deux côtés.** Les équipes ne voient que leur périmètre ; ton mécanisme n'a pas une identité qui peut tout faire.
4. **Les données de santé ne quittent pas la production.** Aucune personne de Data ni d'AxiomDev n'y accède ; tout ce qui en sort est pseudonymisé (phase 3).
5. **Rien de destructif par un automate.** Un départ retire des droits ; supprimer un espace, un volume ou une base est un geste explicite, après sauvegarde vérifiée.
6. **Mesurer.** Délai d'accueil, délai jusqu'au premier déploiement, interventions de la Plateforme : notés au fil de l'eau (S04, S14 s'en servent).

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check F2 <XX>`. Elles sont en lecture seule, ne lisent jamais un Secret ni une valeur du coffre, et vérifient des **résultats** (ce qu'une équipe a reçu), pas ta façon de faire — sauf les noms fixés ci-dessus.
- Les pannes s'injectent par `lab/bin/break F2 <XX>` (S06 en phase 2, S11 en phase 4) ; `--annuler` remet l'état sain.
- Le corrigé (`corrige/`) donne **une** solution de référence par scénario libre, ses raisons, ses alternatives et ses pièges. Les fichiers complets sont dans `corrige/fichiers/SXX/` : `equipes/` reproduit `plateforme/equipes`, `cibles/` les changements faits une fois dans les dépôts existants, `medisphere/` la documentation.

## Ordre conseillé

```
S01 ─ S02 ─ S03 ─ S04 ─ S05 ─ S06 ─┬─ S07 ─ S08 ─ S09
                                     └─ S10 ─ S11 ─ S12 ─── S13 ─ S14
```

S03 peut se faire à tout moment après S02 ; S06 après S05 (la panne vise la recette de MédiVisio) ; les phases 3 et 4 sont indépendantes l'une de l'autre ; S12 avant S13 (la recette vérifie qu'AxiomDev est parti).

## Pour aller plus loin

- *CNCF Platforms White Paper* et *Platform Engineering Maturity Model* : <https://tag-app-delivery.cncf.io/whitepapers/>
- Capsule (locataires, réplications) : <https://projectcapsule.dev/docs/> ; Argo CD ApplicationSet (générateurs Git et matrice, `templatePatch`, sécurité) : <https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/>
- *Team Topologies* (M. Skelton, M. Pais) : plateformes comme produit, « X-as-a-Service »
