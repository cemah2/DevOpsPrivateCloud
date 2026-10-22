# Référentiels de durcissement des hôtes

> SEC-2704 — décision du <AAAA-MM-JJ>, `<MOI>` avec Sophie Laurent (RSSI). Révision à chaque nouvelle version de ComplianceAsCode ou de référentiel CIS, et au moins une fois par an.

## Référentiels retenus

| Référentiel | Version | Niveau retenu | Pourquoi |
|---|---|---|---|
| CIS Debian Linux 13 Benchmark | v1.0.0 (16/12/2025) | **niveau 1 – serveur** | référentiel international attendu par l'auditeur HDS et ISO 27001 ; le niveau 1 vise une sécurité raisonnable sans perte de fonction |
| CIS Red Hat Enterprise Linux 10 Benchmark (appliqué à Rocky 10) | v1.0.1 | **niveau 1 – serveur** | même raison, pour `ipa01` et les nœuds `ceph0x` |
| ANSSI-BP-028 (*Recommandations de configuration d'un système GNU/Linux*) | v2.0 | **intermédiaire** | référence française, attendue d'un hébergeur de données de santé ; le niveau intermédiaire couvre comptes, droits, journalisation, réseau sans exiger de matériel particulier |

## Contenu et profils (ComplianceAsCode 0.1.82)

| Système | Contenu | *Datastream* | Profil CIS | Profil ANSSI |
|---|---|---|---|---|
| Debian 13 | archive amont `scap-security-guide-0.1.82.zip` (SHA-512 publiée, vérifiée), dépliée dans `/usr/local/share/scap/ssg-0.1.82/` | `ssg-debian13-ds.xml` | `xccdf_org.ssgproject.content_profile_cis_level1_server` | `xccdf_org.ssgproject.content_profile_anssi_bp28_intermediary` |
| Rocky 10 | paquet `scap-security-guide` 0.1.82 d'AppStream (reconstruit par Rocky) | `/usr/share/xml/scap/ssg/content/ssg-rl10-ds.xml` | `xccdf_org.ssgproject.content_profile_cis_server_l1` | `xccdf_org.ssgproject.content_profile_anssi_bp28_intermediary` |

**Pourquoi deux origines.** Debian 13 empaquette `ssg-debian` 0.1.76, qui ne contient **aucun** produit Debian 13 (seulement 11 et 12) : le contenu vient donc de l'archive amont, épinglée par version et par empreinte. Rocky 10 a le paquet à jour, qui ajoute un *datastream* `ssg-rl10` dont la plate-forme CPE reconnaît Rocky (`cpe:/o:rocky:rocky:10`) ; le `ssg-rhel10-ds.xml` du même paquet, ou de l'archive amont, ne reconnaît que RHEL : sur Rocky, ses règles sortiraient `notapplicable` et le score ne voudrait rien dire.

**Volume.** Profil CIS niveau 1 serveur : environ 400 règles sur Debian 13, environ 320 sur Rocky 10 ; ANSSI intermédiaire : environ 230 règles sur chacun (décompte des règles corrigeables du profil, ComplianceAsCode 0.1.82). Le contenu Debian 13 est marqué *draft* par le projet : certaines règles peuvent encore évoluer d'une version à l'autre.

## Scores de départ (VMs d'essai, images dorées)

| VM | Profil | Score | pass | fail | notapplicable | notchecked |
|---|---|---|---|---|---|---|
| `durci-deb` | CIS niveau 1 serveur | `<SCORE>` | `<N>` | `<N>` | `<N>` | `<N>` |
| `durci-deb` | ANSSI intermédiaire | `<SCORE>` | | | | |
| `durci-rocky` | CIS niveau 1 serveur | `<SCORE>` | | | | |
| `durci-rocky` | ANSSI intermédiaire | `<SCORE>` | | | | |

Résultats bruts : `/var/lib/conformite/essais/` des VMs d'essai (détruites en E14) ; rapports HTML archivés dans `~/m26/e04/`.

## Profils écartés

| Profil | Pourquoi pas (maintenant) |
|---|---|
| CIS niveau 2 | `/var`, `/var/log`, `/var/log/audit`, `/home` sur des partitions séparées (nos images ont une partition unique) ; désactivation de fonctions utiles à l'exploitation ; à réexaminer pour les hôtes les plus sensibles (`vault0x`, `kms01`, `ca01`) |
| ANSSI renforcé et élevé | exigent des mesures matérielles ou de démarrage (IOMMU, mot de passe du chargeur de démarrage, noyau durci, chiffrement complet) que les VMs du lab ne portent pas ; « élevé » suppose des équipes dédiées |
| DISA STIG (Rocky) | référentiel de l'administration américaine, sans valeur pour notre auditeur, et plus contraignant que CIS niveau 2 |
| PCI-DSS, HIPAA | hors de notre contexte réglementaire (HIPAA est l'équivalent américain d'HDS, il ne le remplace pas) |

## Ce que ces profils ne mesurent pas

- L'état des **correctifs** : la règle correspondante de Debian lit un flux OVAL distant de `www.debian.org`, que l'analyse ne télécharge **pas** (pas de sortie Internet depuis les VMs du socle pour cela) : elle reste `notchecked`. Les correctifs sont suivis à part (E30).
- La configuration **applicative** (GitLab, Harbor, Keycloak, OpenBao…) : chacune a ses propres recommandations, revues dans leurs modules.
- Kubernetes : mesuré par kube-bench et kubescape (`mesure-k8s-par1.md`).

## Exceptions

Toute règle écartée est une **exception** déclarée dans `durcissement_exceptions` (rôle `durcissement`, E10), inscrite au registre `exceptions.md` (E23) et exclue de l'analyse par un profil adapté (*tailoring*), jamais par la suppression silencieuse d'une règle.
