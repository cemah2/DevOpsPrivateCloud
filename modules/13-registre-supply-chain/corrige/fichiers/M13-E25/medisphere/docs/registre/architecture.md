# Architecture du registre MédiSphère (v1)

> Modèle de corrigé (M13-E25). Livré avec l'étiquette `registre-v1` de `plateforme/medisphere`.

## Vue d'ensemble

```
          Docker Hub · Quay · GHCR · registry.k8s.io          (Internet, par la bordure)
                              ▲ caches (proxy cache, publics)
  runner02 (CI) ── 443 ──►  reg01 : Harbor 2.15  ◄── 443 ── adm01, VLAN 40 (k8s-par1, M14)
  (build → scan → sbom      registry.par1.medisphere.internal (CNAME → reg01, 10.10.20.18)
   → push → sign → verify)   │  nginx · core · portal · registry · registryctl · jobservice
                             │  harbor-db (PostgreSQL 18) · redis (Valkey) · trivy-adapter · exporter
                             ├─ /data (200 Go, XFS) : registry/, database/, secret/, redis/, trivy-adapter/
                             ├─► pbs01 (par1/registre) : sauvegarde applicative 01:40 (wb-backup-harbor)
                             └─► :9090/metrics, /api/v2.0/health ◄── ms-verif-registre (adm01, 5 min)
```

## Composants et données

| Composant | Rôle | Données | Si il tombe |
|---|---|---|---|
| `nginx` (proxy) | TLS (certificat ACME step-ca), routage, métriques 9090 | `/data/secret/cert` | plus rien sur 443 : CI et tirages échouent |
| `harbor-core` | API, jetons, politiques, authentification | — | idem (jetons refusés) |
| `registry` / `registryctl` | API Distribution, stockage des blobs | `/data/registry` | tirages et poussées échouent ; l'interface fonctionne |
| `harbor-db` | état : projets, robots, artefacts, politiques, audit | `/data/database` | tout échoue (cœur sans base) |
| `redis` (Valkey) | cache, files de tâches | `/data/redis` (éphémère) | tâches (réplication, analyses, GC) en attente |
| `harbor-jobservice` | réplication, analyses, GC, rétention | `/data/job_logs` | tâches en attente ; tirages et poussées continuent |
| `trivy-adapter` | analyse (Trivy 0.74 embarqué) | base dans `/data/trivy-adapter` | pas de nouvelle analyse → images non analysées **refusées** dans `medisphere` |
| `harbor-exporter` | métriques Prometheus | — | sonde : métriques KO, service rendu |

## Confiance

Politique : ADR-0130 et `politiques.md`. Chaîne : `templates/supply-chain.yml` (E09) → `templates/verification.yml` (E14) → admission Kubernetes (M14 VAP, M26 Kyverno). Clé de signature : Vault `critique` + variable de CI protégée ; clé publique `docs/registre/cosign.pub`.

## Ce qui n'est PAS redondant

- **Un seul registre, une seule VM, un seul site** : RTO mesuré `<…>` (RB-131) ; la réplication d'essai vers `reg02` a été retirée, la copie à PAR2 arrive aux finaux.
- **Une seule clé de signature**, sans horodatage ni journal de transparence (risques acceptés, ADR-0130).
- **Un seul hyperviseur physique** (`pve01`) : une panne matérielle arrête tout le lab.

## Ce que les modules suivants traitent

| Module | Sujet |
|---|---|
| M14 | tirage par containerd via les caches (`caches.md`, `hosts.toml`), robot `k8s-pull`, flux VLAN 40 → 443 |
| M17 | charts Helm OCI dans `charts`, signés |
| M19-M20 | gabarits de CI sur Kubernetes, promotion par digest (GitOps) |
| M21 | alertes Prometheus sur les métriques de Harbor |
| M24 | authentification OIDC (Keycloak) des humains ; plus de comptes locaux hors `admin` |
| M25 | clé de signature dans Vault (Transit), secrets des robots par External Secrets |
| M26 | admission : signature par clé, digest, registre imposés |
