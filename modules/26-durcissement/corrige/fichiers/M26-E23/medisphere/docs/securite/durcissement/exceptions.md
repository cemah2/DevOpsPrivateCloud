# Registre des exceptions de sécurité

> `plateforme/medisphere` — `docs/securite/durcissement/exceptions.md` (M26-E23, SEC-2723).
> Procédure : [RB-261 — Dérogation](runbooks/RB-261-derogation.md). Propriétaire du registre : Sophie Laurent (RSSI).
> Ce registre est la **source de vérité** que l'on montre à l'auditeur HDS. Chaque exception codée
> (`durcissement_exceptions`, `PolicyException`, liste Falco, étiquette Pod Security, liste `hostPath`)
> y a une ligne, et inversement. Un écart entre les deux est un défaut (contrôle mensuel, § « Revue »).

## Comment lire une ligne

- **ID** : `EXC-H-nnn` (hôtes), `EXC-K-nnn` (Kubernetes : Pod Security, admission), `EXC-D-nnn` (détection :
  Falco, Tetragon). Jamais réutilisé.
- **Règle** : identifiant exact du référentiel ou de la politique (règle XCCDF, numéro CIS, nom de politique Kyverno
  ou de VAP, nom de règle Falco).
- **Périmètre** : le plus étroit possible (hôte, espace, pod par étiquette, image, conteneur).
- **Risque résiduel** : ce que l'exception laisse possible, dit simplement.
- **Compensation** : ce qui réduit ce risque à la place du contrôle absent.
- **Codée dans** : fichier et clé, pour retrouver l'exception dans le code.
- **Revue** : date à laquelle on décide de la prolonger, la réduire ou la supprimer (≤ 3 mois pour les
  exceptions temporaires, ≤ 12 mois pour les permanentes).

## Exceptions en vigueur

### Hôtes (rôle `durcissement`, référentiels CIS niveau 1 et ANSSI-BP-028 intermédiaire)

| ID | Règle | Périmètre | Justification | Risque résiduel | Compensation | Codée dans | Valideur | Revue |
|---|---|---|---|---|---|---|---|---|
| EXC-H-001 | `xccdf_org.ssgproject.content_rule_sysctl_net_ipv4_ip_forward` | `gw01`, `gw02` | Ce sont des routeurs : sans transfert IP, plus de réseau | Un hôte compromis route du trafic | nftables en refus par défaut, matrice des flux, VRRP surveillé | `host_vars/gw0*/durcissement.yml` | sophie.laurent | 2027-10-01 |
| EXC-H-002 | `xccdf_org.ssgproject.content_rule_sysctl_net_ipv4_ip_forward` | nœuds `k8s-par1` | Réseau des pods (Cilium) | Idem | Politiques Cilium, pare-feu d'hôte (E27) | `group_vars/k8s_par1/durcissement.yml` | sophie.laurent | 2027-10-01 |
| EXC-H-003 | `xccdf_org.ssgproject.content_rule_mount_option_tmp_noexec` | `runner01`, `runner02` | Les jobs CI exécutent des scripts dans `/tmp` | Exécution d'un binaire déposé dans `/tmp` | auditd (`execve` depuis `/tmp`), runners éphémères | `host_vars/runner0*/durcissement.yml` | sophie.laurent | 2027-01-31 |

### Kubernetes — Pod Security et admission

| ID | Règle | Périmètre | Justification | Risque résiduel | Compensation | Codée dans | Valideur | Revue |
|---|---|---|---|---|---|---|---|---|
| EXC-K-001 | Kyverno `exiger-digest` | image `…/ghcr/cloudnative-pg/cloudnative-pg:1.30.1`, pods d'instance CNPG de `mediagenda-prod` | Image de l'opérateur dans `bootstrap-controller`, fixée par l'opérateur (CHG-2718 planifié) | Une étiquette déplacée changerait le code exécuté à l'amorçage | Image du cache Harbor analysée par Trivy ; périmètre limité à une image et aux pods d'instance ; échéance courte, correction planifiée | `plateforme/politiques/kyverno/exceptions/cnpg-operateur-sans-condense.yaml` (`expiresAt`) | sophie.laurent | 2027-01-08 |
| EXC-K-002 | Norme « charge sûre » C6 (jeton non monté) | pods `cnpg.io/podRole=instance` | Le gestionnaire d'instance CNPG parle à l'API | Jeton volé = droits du rôle CNPG de l'instance | RBAC de l'opérateur limité à l'espace, Falco `medisphere_lecteurs_jeton` limité au binaire `manager` | `plateforme/k8s/outils/audit-charges-sures.sh` | sophie.laurent | 2027-10-01 |
| EXC-K-003 | Pod Security `restricted` | espaces `supervision-noeuds`, `falco`, `tetragon` (`privileged`) | Agents de nœud (node-exporter, eBPF) | Un pod de ces espaces a les droits de l'hôte | VAP `medisphere-interdire-hostpath` (chemins listés), espaces sans accès des équipes, images signées de la bibliothèque | `plateforme/k8s/espaces/*.yaml` | sophie.laurent | 2027-10-01 |
| EXC-K-004 | VAP `medisphere-interdire-hostpath` | chemins listés par espace | Voir la ConfigMap `medisphere-hostpath` | `falco` lit `/etc` de l'hôte (dont `/etc/kubernetes/pki` sur les nœuds de contrôle) | Montage en lecture seule, réduction des moteurs de conteneurs (à faire) | `plateforme/k8s/admission/20-interdire-hostpath.yaml` | sophie.laurent | 2027-04-01 |

### Détection

| ID | Règle | Périmètre | Justification | Risque résiduel | Compensation | Codée dans | Valideur | Revue |
|---|---|---|---|---|---|---|---|---|
| EXC-D-001 | Falco « lecture du jeton de compte de service » | processus `manager` (pods CNPG) | Lecture légitime et permanente | Un attaquant qui nomme son binaire `manager` passe inaperçu | Tetragon `fichiers-sensibles` voit le chemin du binaire, pas seulement son nom | liste `medisphere_lecteurs_jeton` | sophie.laurent | 2027-04-01 |

## Exceptions closes

| ID | Règle | Ouverte | Close | Comment |
|---|---|---|---|---|
| — | `exiger-limites` (conteneur d'initialisation de valkey, DEV-2718) | — | refusée | Corrigé par `valkey.initResources` du chart : une exception n'était pas nécessaire |

## Revue

- **Mensuelle** (premier lundi, 30 min, Sophie + un membre de l'équipe Plateforme) : comparer le registre
  au code (`grep -r durcissement_exceptions`, `kubectl get policyexceptions -n kyverno-exceptions`, listes
  `medisphere_*` de Falco, espaces `privileged`), traiter les échéances du mois.
- **À chaque échéance** : prolonger (nouvelle date, justification relue), réduire le périmètre, ou fermer.
  Une exception échue n'est pas prolongée « en silence » : la `PolicyException` cesse de s'appliquer à sa
  date (`expiresAt`) et le pipeline planifié de `plateforme/politiques` échoue 14 jours avant.
- **Indicateurs** pour le comité sécurité : nombre d'exceptions ouvertes par catégorie, âge moyen, nombre
  d'exceptions prolongées plus de deux fois (elles cachent un problème de fond).
