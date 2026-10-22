# Cloisonnement des jobs de CI

| | |
|---|---|
| Ticket | SEC-2024 (M19-E24) |
| Propriétaire | Équipe Plateforme |
| Dernière revue | AAAA-MM-JJ, relue par Sophie Laurent |
| Code | `plateforme/k8s` : `espaces/ci-jobs/`, `espaces/ci-jobs-protege/`, `composants/gitlab-runner*/values.yaml` |

## Deux mondes

| | Runner `k8s-par1` | Runner `k8s-par1-protege` |
|---|---|---|
| Étiquettes | `k8s`, `kubernetes` | `protege` |
| Références | toutes (`not_protected`) | protégées seulement (`ref_protected`) |
| Espace des jobs | `ci-jobs` | `ci-jobs-protege` |
| Secrets remis par le runner | aucun | clé Cosign (`cosign-medisphere`, volume en lecture seule) |
| Sorties réseau | DNS, `git01:443`, Harbor `:443`, `s3-01:8333`, buildkitd `:1234`, Internet `:443` hors réseaux privés | DNS, `git01:443`, Harbor `:443` |
| Cache | S3 `ci-cache`, chemin `k8s-par1` | aucun |
| Images autorisées | `registry.par1.medisphere.internal/**` | `registry.par1.medisphere.internal/plateforme/**` |

Communs : Pod Security `restricted` (enforce), utilisateur 1000:1000, `fsGroup` 1000, seccomp `RuntimeDefault`, aucune capacité, pas d'élévation de privilège, pas de mode privilégié, compte `ci-job` sans droit et sans jeton (deux verrous : le compte et le runner), aucune surcharge `KUBERNETES_*` de l'espace ni du compte ; gestionnaire limité à une Role dans l'espace des jobs (pods, attach/exec, journaux, Secrets de job, Services, événements).

## Sondes (pipeline `sondes-cloison` de `formation/ci-labo`)

| Sonde | Avant (AAAA-MM-JJ) | Après `k8s` | Après `protege` |
|---|---|---|---|
| Identité | `uid=0(root)` | `uid=1000` | `uid=1000` |
| `CapEff` | `00000000a80425fb` (capacités par défaut du moteur) | `0000000000000000` | `0000000000000000` |
| `NoNewPrivs` / `Seccomp` | 0 / 0 | 1 / 2 | 1 / 2 |
| Jeton de compte de service | absent (compte `ci-job`, E04) | absent | absent |
| API Kubernetes (Service 443, VIP 8443) | OUVERT | FERMÉ | FERMÉ |
| PostgreSQL de `mediagenda-dev` | OUVERT | FERMÉ | FERMÉ |
| NetBox 443, SSH `dns01`/`git01` | OUVERT | FERMÉ | FERMÉ |
| `git01` 443 | OUVERT | OUVERT | OUVERT |
| Harbor 443 | OUVERT | OUVERT | OUVERT |
| `s3-01` 8333 | OUVERT | OUVERT | FERMÉ |
| buildkitd 1234 | OUVERT | OUVERT | FERMÉ |
| Internet 443 | OUVERT | OUVERT | FERMÉ |
| Internet 80 | OUVERT | FERMÉ | FERMÉ |
| Mailpit 25 | OUVERT | FERMÉ | FERMÉ |

(Les valeurs « avant » sont celles relevées sur le lab ; remplace-les par les tiennes.)

## Exceptions

| # | Exception | Pourquoi | Compensation | Fin prévue | Responsable |
|---|---|---|---|---|---|
| 1 | Variables de **groupe** `COSIGN_PRIVATE_KEY` / `COSIGN_PASSWORD` (M13-E07 : groupes `mediagenda`, `medidoc`, `medinotif`, `legacy`) encore présentes | consommées par les pipelines v1 sur `runner02` : signature du chart (`mediagenda/chart`), de MédiDoc (`medidoc/medidoc`) et du worker MédiNotif (`medinotif/worker`, `sc:signature` de M13-E12) ; aucun consommateur dans `legacy` | protégées (références protégées seulement) ; `COSIGN_PASSWORD` masquée, `COSIGN_PRIVATE_KEY` de type fichier (non masquable) ; `mediagenda/api` n'en dépend plus ; variables de `legacy` supprimées dès E24 | `medidoc/medidoc` : M19-E33 ; `mediagenda/chart` et `medinotif/worker` : mini-projet M19-E46 (suppression des variables de groupe restantes) | Plateforme |
| 2 | Services de job (PostgreSQL, Valkey, E14) forcés en UID 999 | les images officielles démarrent en root puis changent d'utilisateur ; `restricted` interdit root | `service_container_security_context` (999:999) ; images par le cache Harbor | permanente (revue annuelle) | Plateforme |
| 3 | (si utilisée) Sortie vers la Gateway (`toEntities: ingress`, 443) | analyse SonarQube (E16) par `sonarqube.apps…` | limitée au port 443 | mini-projet M19-E46 (retrait de SonarQube) | Plateforme |

Ce qui n'est **pas** une exception et ne le sera pas : `apt-get install` dans un job (utiliser une image outillée de `bibliotheque/` ou `plateforme/`), Docker-in-Docker, mode privilégié, montage d'un chemin de l'hôte.

## Essai inverse

Un job étiqueté `protege` sur la branche non protégée `sondes-cloison` reste **en attente** : « This job is stuck because you don't have any active runners online or available with any of these tags assigned to them: protege » (aucun runner disponible pour cette référence). C'est voulu : le runner protégé ne prend jamais une référence non protégée, et GitLab ne bascule pas le job vers un autre runner. RB-190 traite ce cas (« runner protégé seul candidat d'un job de branche non protégée »).

## Ce que ces cloisons ne couvrent pas

- Un job de `main` (référence protégée) sur le runner `k8s` reçoit encore les variables protégées du projet et du groupe : c'est pourquoi la clé Cosign n'est plus une variable (exception 1 mise à part) et pourquoi `DEPLOIEMENT_TOKEN` a une portée d'environnement (E25).
- Un développeur qui peut pousser sur `main` peut faire exécuter du code sur le runner protégé : la protection, c'est la revue de MR et les règles de branche protégée, pas le runner (E31 Q1).
- Les jobs d'un même espace partagent les nœuds et le démon buildkitd (E31 Q2 et Q4).
