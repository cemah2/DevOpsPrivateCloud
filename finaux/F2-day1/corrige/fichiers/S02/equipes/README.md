# plateforme/equipes

**Une équipe en un changement** (F2-S02, PLAT-3202 ; décision : ADR-0320 ; procédure : RB-320). Chaque équipe de MédiSphère qui reçoit des droits sur la plateforme est décrite par **un fichier** `equipes/<equipe>.yaml`. Une MR sur ce fichier, relue par la Plateforme, suffit à créer, modifier ou retirer tout ce que l'équipe reçoit ; la CI de ce projet valide, mesure le coût en capacité, puis **propage** le rendu dans les dépôts qui appliquent déjà chaque brique. Le modèle Backstage `nouvelle-equipe` n'est qu'une **interface** : il ouvre cette même MR.

| Dossier | Contenu |
|---|---|
| `equipes/` | un fichier par équipe (format : `schema/equipe.schema.json`, ci-dessous) |
| `schema/` | schéma JSON (draft 2020-12) du fichier d'équipe |
| `config/plateforme.yaml` | noms réservés, relevé de capacité, cibles de la propagation, chemins possédés |
| `gabarits/` | gabarits Jinja2 des manifestes (Tenant Capsule, espaces, cloison Cilium, AppProject, ApplicationSet, identifiants de dépôt, utilisateurs Capsule) |
| `outils/rendre.py` | validation (schéma + cohérence) et rendu complet dans `rendu/<cible>/` |
| `outils/capacite.py` | bilan des budgets contre l'allouable relevé (bloquant) |
| `outils/gitlab_equipes.py` | groupe GitLab, projet `<equipe>/gitops`, jetons de groupe rangés dans OpenBao |
| `outils/propager.py` | une MR par dépôt cible, fusion automatique si son pipeline réussit |
| `tests/` | tests du générateur (pytest, sans réseau) |

## Ce qu'un fichier d'équipe produit

| Brique | Dépôt qui applique | Fichiers rendus (possédés par ce projet) | Appliqué par |
|---|---|---|---|
| Personnes, groupe de l'annuaire (FreeIPA) | `plateforme/identite` | `annuaire/equipes/personnes.yml`, `annuaire/equipes/groupes.yml` | `annuaire:appliquer` (Ansible `freeipa.ansible_freeipa`) |
| Appartenances GitLab (responsable Maintainer, développeurs Developer) | `plateforme/identite` | `outils/synchro-gitlab.d/equipes.yml` | `synchro:gitlab` (outil du M24-E11) |
| OTP obligatoire (prestataires) | `plateforme/identite` | `tofu/equipes.auto.tfvars.json` | `tofu:apply` (flux conditionnel du M24-E21) |
| Groupe GitLab, projet `<equipe>/gitops`, jetons de groupe | GitLab lui-même | — | job `gitlab:equipes` de ce projet |
| Groupe externe, politique `<equipe>-equipe`, rôles `eso-<espace>`, rôles CI des services | `plateforme/secrets` | `tofu/equipes.auto.tfvars.json` | `tofu:apply` (`tofu/equipes.tf`) |
| Dossier et équipe Grafana | `plateforme/infra` | `observabilite-grafana/equipes.auto.tfvars.json` | `tofu apply` de l'état `observabilite-grafana` |
| Locataire Capsule, espaces, quotas, LimitRange, coffre, route d'alertes, cloison | `plateforme/k8s` | `equipes/<equipe>/…` | Argo CD, Application `equipes-k8s` |
| AppProject, ApplicationSet des services, identifiants de dépôt ; utilisateurs Capsule | `plateforme/gitops` | `equipes/<equipe>/…`, `valeurs/capsule/utilisateurs-equipes.yaml` | Argo CD, Applications `equipes-gitops` et `capsule` |
| Entité `Group` du portail | (aucun fichier) | — | découverte LDAP de Backstage (le groupe de l'annuaire suffit) |

## Format du fichier d'équipe (v1)

Le format de référence est **`schema/equipe.schema.json`** ; exemples : `equipes/medivisio.yaml`, `equipes/data.yaml`. Résumé :

```yaml
apiVersion: equipes.medisphere.internal/v1
kind: Equipe
metadata:
  nom: <equipe>              # = nom du fichier ; groupe annuaire/GitLab, locataire, préfixe d'espace
  ticket: DEV-NNNN           # demande d'origine
spec:
  description: <une phrase>
  type: interne              # interne | prestataire
  etat: active               # active | retiree (désactive, vide, retire les droits ; jamais les données)
  responsable: <identifiant> # doit figurer dans personnes
  contact: <equipe>@medisphere.internal   # alertes, équipe Grafana
  expiration: "AAAA-MM-JJ"   # prestataire seulement (obligatoire) : fin des accès
  personnes:                 # identifiant, prenom, nom, courriel, titre, role (responsable|developpeur|lecteur),
    - …                      # etat (present|disabled), expiration (AAAA-MM-JJ, sinon celle de l'équipe)
  identite: {otp_obligatoire: false}      # vrai obligatoire pour un prestataire
  gitlab: {groupe: <equipe>, externe: false}   # externe vrai obligatoire pour un prestataire
  kubernetes:                # facultatif : absent = pas de locataire
    environnements:          # un espace <equipe>-<env> par entrée
      <env>: {quota: {…}, signature_exigee: bool, synchronisation: automatique|manuelle, alertes: bool}
    libre_service: {espaces: N, quota: {…}}
    budget: {requests.cpu, requests.memory, limits.memory, pods}   # GlobalResourceQuota du locataire
    classes_priorite: {autorisees: […], defaut: medisphere-standard}
    classes_stockage: [ceph-rbd]
  secrets: {ecriture: [<env>…]}           # kv/<equipe>/<env>/* écrits par l'équipe (OIDC)
  services: [<service>…]                  # rôles CI d'OpenBao (signature, promotion) par service
  observabilite: {grafana: {titre_dossier: <titre>}}
```

### Évolutions du format après S02

Le format v1 ci-dessus est celui que livre F2-S02. Il ne change ensuite que par **ajout** (jamais de renommage), avec schéma, générateur, gabarits et tests dans la même MR :

| Scénario | Ajout | Effet du rendu | Fichiers du corrigé |
|---|---|---|---|
| F2-S07 (DEV-3207) | `spec.kubernetes.environnements.<env>.base_openbao: true` (facultatif, défaut `false`) | `services.loadbalancers: "1"` dans le `ResourceQuota` de l'espace (base jointe par OpenBao ; le Service lui-même reste à la plateforme) | `fichiers/S07/equipes/` |
| F2-S10 (SEC-3210) | bloc `spec.hebergement` (prestataire seulement, exclut `kubernetes`) : `locataire`, `espace`, `quota`, `role` (`prestataire-developpeur` ou `prestataire-lecteur`), `gitlab_projets` (`<groupe>/<projet>: developer\|reporter`) | espace `<locataire>-<nom sans ext->` (gabarit `k8s/prestataire.yaml.j2`, **non** protégé de l'élagage), `identite/outils/gitlab-prestataires.d/equipes.yml` (job `gitlab:prestataires` de `plateforme/identite`) ; chemin possédé ajouté à `config/plateforme.yaml` | `fichiers/S10/equipes/` |

Ce que le format ne dit pas (identifiants dynamiques d'une base d'équipe, politiques en plus d'un groupe) est déclaré par la plateforme à côté du rendu, dans `plateforme/secrets` (`tofu/equipes-complements.auto.tfvars`, F2-S07), jamais dans un fichier rendu.

Les dates (`expiration`) s'écrivent entre guillemets ; `outils/rendre.py` lit de toute façon les dates YAML comme du texte.

Règles vérifiées en plus du schéma (`outils/rendre.py`) : nom ni réservé ni préfixe d'une autre équipe ; responsable parmi les personnes ; une personne décrite à l'identique si elle est dans deux équipes ; environnements + libre-service tiennent dans le budget ; une production (`synchronisation: manuelle`) exige `medisphere-critique` ; un prestataire n'a pas de production ; `secrets.ecriture` et `services` exigent un bloc `kubernetes`.

## Travailler ici

```
admin@adm01:~/src/equipes$ uv sync
admin@adm01:~/src/equipes$ uv run outils/rendre.py --valider && uv run pytest -q
admin@adm01:~/src/equipes$ uv run outils/capacite.py
admin@adm01:~/src/equipes$ uv run outils/rendre.py && tree rendu/
```

- Une équipe qui arrive, change ou part : **MR sur `equipes/<equipe>.yaml`**, rien d'autre (RB-320).
- Les fichiers rendus dans les dépôts cibles portent l'en-tête « GÉNÉRÉ … NE PAS MODIFIER ICI » : une modification à la main y est écrasée au rendu suivant.
- La CI n'efface jamais un espace ni un locataire (`Prune=false`, `preventDeletion`) : un départ retire les droits, la suppression des données est un geste explicite (RB-320, § Départ).
