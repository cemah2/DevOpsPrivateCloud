<!-- EXTRAIT de docs/socle/iac.md (plateforme/medisphere), section écrite en M05-E28. -->

## Dérive de l'infrastructure

### Détection

Chaque nuit à 02:17 (Europe/Paris), le pipeline planifié `PLANIF=derive` de `plateforme/infra`
lance `outils/derive.sh` sur `socle/`, `envs/lab-m05/` et `envs/recette-m05/`, chaque
configuration dans le `resource_group` de son apply. Deux plans en lecture par configuration :

| Résultat | Signification | Code |
|---|---|---|
| conforme | état, code et réalité concordent | 0 |
| **dérive** | la réalité a changé hors d'OpenTofu (`plan -refresh-only` non vide) | 2 |
| **écart de code** | une MR fusionnée n'a pas été appliquée (plan ordinaire non vide, pas de dérive) | 3 |
| erreur | la détection n'a pas pu conclure (backend, droits, réseau) | 1 |

Le rapport (adresses et **noms** d'attributs, jamais de valeurs) est conservé 90 jours en artefact
du job ; toute issue autre que « conforme » ouvre ou commente l'unique ticket `derive` du projet
(jeton `DERIVE_TOKEN`, registre des secrets). Sur `adm01`, le même outil :
`. outils/charger-acces.sh && outils/derive.sh [configuration…]`.

### Que faire d'une dérive

| Cas | Voie | Qui décide | Délai |
|---|---|---|---|
| Modification d'urgence **à garder** (ex. mémoire de `s3-01` montée la nuit) | MR qui fait entrer la valeur dans le code, plan relu **vide** sur la ressource, puis apply (rien ne change) | l'auteur de l'urgence propose, un Maintainer fusionne | jour ouvré suivant |
| Modification **non voulue** ou non expliquée | apply du code existant (job `apply:<configuration>`), qui remet la valeur du code | Maintainer de garde | jour ouvré suivant ; immédiat si la sécurité est en cause (Sophie informée) |
| Écart de code (MR fusionnée non appliquée) | lancer le job `apply:` du dernier pipeline de `main` | auteur de la MR | 2 jours ouvrés |
| Erreur de détection | diagnostic (RB-050 si verrou) ; deux nuits en erreur = incident | astreinte | jour ouvré suivant |

On ne « corrige » **jamais** une dérive à la main dans Proxmox : on décide entre le code et la
réalité, et c'est OpenTofu qui écrit. Le ticket `derive` est fermé par un humain, après une
détection conforme, avec la décision prise et le lien vers la MR ou le job.
