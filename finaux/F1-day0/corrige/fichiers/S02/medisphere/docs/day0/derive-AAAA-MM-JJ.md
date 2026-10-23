# Chasse à la dérive du <AAAA-MM-JJ> (PLAT-3102)

> Modèle de référence (corrigé F1-S02). Renomme le fichier avec la date du jour de la chasse
> (`derive-2026-11-03.md`). Les lignes d'exemple du tableau des écarts sont des écarts **plausibles** :
> remplace-les par les tiens. Aucune valeur secrète : des noms d'objets et d'attributs seulement.

## 1. Méthode par couche

| Couche | Contrôle | Lancé par | Résultat lisible dans | Planifié |
|---|---|---|---|---|
| VMs (`socle`, `envs/k8s`, `envs/ceph`, `envs/provisioning`, `registre`, environnements vides) | `outils/derive.sh` : plan `-refresh-only` (dérive) puis plan ordinaire (écart de code) | pipeline planifié `PLANIF=derive` de `plateforme/infra`, jobs `derive:*` | artefacts `rapports/derive-*/derive.md`, ticket `derive` | oui (02 h 17), étendu aux nouveaux états |
| Configuration des VMs | `ansible-playbook site.yml --check --diff` | pipeline planifié `PLANIF=derive` de `plateforme/ansible`, job `derive` | journal du job, rapport JUnit | oui (M04) |
| Couche de base du cluster | `helmfile diff --detailed-exitcode --suppress-secrets --context 3` **avec** `--diff-args "--three-way-merge"` | pipeline planifié de `plateforme/k8s` (M17, palier 3) | journal du job | oui, option ajoutée |
| Plateforme et applications | état des Applications d'Argo CD (`argocd app list`, interface) | Argo CD en continu | interface, notifications Mailpit | continu |
| Identité | plan de l'état `identite` ; `annuaire.yml --check --diff` | pipeline planifié `PLANIF=derive` de `plateforme/identite` (**nouveau**) | jobs `tofu:plan`, `derive:identite`, `annuaire:verifier` | oui (02 h 41) |
| Coffre | plan de l'état `secrets` | pipeline planifié de `plateforme/secrets` (**nouveau**) | jobs `tofu:plan`, `derive:secrets` | oui (02 h 47) |
| Registre | plan de l'état `registre` | job `derive:registre` de `plateforme/infra` (**nouveau**) | rapport de dérive | oui |
| Inventaire | `ansible-inventory` NetBox face à l'inventaire Proxmox (contrôle de cohérence du M06) ; `medictl dns sync --simulation` | à la main ce jour, puis dans le pipeline planifié de `plateforme/ansible` | journal | oui (ajouté) |

## 2. Écarts trouvés et décisions

| # | Couche | Objet | Ce qui diffère | Cause probable | Décision | MR |
|---|---|---|---|---|---|---|
| 1 | VMs (`envs/k8s`) | `module.noeud["k8s-w02"].proxmox_virtual_environment_vm.vm` | `memory.dedicated` | redimensionnement à la main pendant l'incident du M28 | **corrigé** (retour à 10240 par apply, nœud drainé) | infra!<N> |
| 2 | Configuration | `lb01` : `/etc/haproxy/haproxy.cfg` | `timeout server` | essai de l'astreinte non reporté | **codifié** (`haproxy_timeout_server` dans `group_vars/role_lb`, raison écrite) | ansible!<N> |
| 3 | Couche de base | release `velero` | `schedules.quotidien.template.ttl` | `helm upgrade --reuse-values` lancé à la main | **corrigé** (`helmfile apply -l composant=velero`) | — (aucun code changé) |
| 4 | Identité | `keycloak_openid_client.grafana` | `web_origins` | ajout dans la console d'administration | **codifié** | identite!<N> |
| 5 | Inventaire | VM `m27-essai` (NetBox) | présente dans NetBox, absente de Proxmox | reste du M27 | **corrigé** (objet retiré par le code qui l'avait créé) | infra!<N> |

## 3. Contrôles finaux (après les MR)

| Couche | Résultat | Preuve |
|---|---|---|
| VMs | conforme, toutes configurations | pipeline planifié n° <N>, jobs `derive:*` verts |
| Configuration | `changed=0` | pipeline planifié n° <N> |
| Couche de base | `helmfile diff` vide (code 0) | pipeline n° <N> |
| Argo CD | <N> Applications, toutes `Synced/Healthy` | `lab/bin/check F1 2` |
| Identité, coffre | « No changes » | pipelines planifiés n° <N>, <N> |
| Registre | « No changes » | job `derive:registre` |
| Inventaire | NetBox = Proxmox | journal du job |

## 4. Ce qui n'est pas contrôlé

- Réglages de Proxmox hors VMs (SDN, comptes, pare-feu du datacenter) : pas d'état OpenTofu ; ticket PLAT-31<NN>.
- Configuration interne de GitLab (paramètres d'instance) : pas de code ; ticket PLAT-31<NN>.

## 5. Incidents rattachés

- **INC-5703** (F1-S03) : voir la section ajoutée après l'incident.
