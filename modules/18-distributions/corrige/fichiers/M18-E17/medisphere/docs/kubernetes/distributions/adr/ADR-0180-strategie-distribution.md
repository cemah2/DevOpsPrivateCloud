# ADR-0180 — Stratégie de distribution et de cycle de vie des clusters Kubernetes

| | |
|---|---|
| Statut | Proposé (comité d'architecture du <AAAA-MM-JJ>) |
| Décideurs | Claire Morel ; consultés : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit |
| Remplace / complète | Complète ADR-0140 (distribution et topologie de `k8s-par1`) et ADR-0141 (cycle de vie des versions) |
| Mesures | M18-E02 à E18 : `docs/kubernetes/distributions/comparatif.md`, `tests/cycle-de-vie-capi.md`, `tests/restaurations.md`, `durcissement.md`, `capo.md` |

## Contexte et problème

Trois besoins :
1. **Production** : `k8s-par1`, kubeadm 1.36, 3 + 3 nœuds, construit et exploité par l'équipe (ADR-0140, RB-140 à RB-149).
2. **Agence de Lyon** : deux ou trois machines, personne sur place, liaison WireGuard avec PAR1 (M07), quelques applications locales.
3. **Recettes éphémères** pour les équipes : une journée à une semaine, à la demande.

Contraintes : données de santé (HDS, ISO 27001), souveraineté (tout depuis Harbor, aucun service géré), équipe de cinq personnes, socles Proxmox VE 9 et OpenStack 2026.1, budget mémoire du lab, écosystème du bloc C (Cilium 1.20, ceph-csi 3.18, CloudNativePG 1.30) qui suit Kubernetes 1.36.

## Critères (poids sur 5)

| Critère | Poids | Source de la mesure |
|---|---|---|
| Sauvegarde et restauration (RTO, étapes manuelles) | 5 | E14 |
| Montée de version (durée, risque, retour arrière) | 4 | M14-E25, E06, E07, E13 |
| Compétences et outillage communs (kubectl, Helm, Ansible, GitOps M20) | 4 | équipe, M14 à M17 |
| Durcissement par défaut et effort pour le CIS | 4 | E15 |
| Pérennité, dépendance à un éditeur | 3 | maturité des projets, licences |
| Empreinte mémoire au repos | 3 | `comparatif.md` (E03 à E05) |
| Temps d'installation | 2 | `comparatif.md`, E18 |
| Réparation automatique | 2 | E13 |
| Compatibilité de l'écosystème du bloc C | 3 | notes de version (PLAN §6) |

## Options évaluées

Distribution : **kubeadm + Ansible**, **k3s**, **RKE2**, **Talos**. Outil de cycle de vie : **Cluster API** (CAPMOX, CAPO) ou **outils propres à la distribution** (rôles Ansible et RB-142 ; system-upgrade-controller ; `talosctl` ; `k3d`/`kind`). Rappel : Cluster API n'est pas une distribution ; un cluster CAPMOX est un cluster kubeadm.

Notes (1 à 5) par besoin, pondérées (détail des mesures dans `comparatif.md`) :

| Option | Production | Lyon | Recette éphémère |
|---|---|---|---|
| kubeadm + Ansible | **4,1** (acquis, runbooks, mais PKI et etcd à la main : E14) | 2,6 (trop lourd sans personne sur place) | 2,0 |
| k3s (+ system-upgrade-controller) | 3,2 (conforme, mais s'écarte du savoir-faire et du durcissement acquis) | **4,3** (≈ 0,5 Go au repos, etcd et S3 intégrés, montée automatique : E07, E14) | 3,8 (sur VM) |
| RKE2 | 3,9 (profil CIS, restauration simple ; mais SELinux, Canal et Traefik à réaligner sur Cilium) | 3,4 (1,5 Go au repos) | 2,8 |
| Talos | 3,5 (surface minimale, mais astreinte sans SSH à apprendre, extensions pour ceph-csi) | 3,9 (rien à administrer sur place ; dépannage par `talosctl` seulement) | 2,7 |
| Cluster API + CAPMOX (kubeadm) | 2,8 (fournisseur 0.x, PVE 9 non documenté, cluster de gestion de plus) | 2,5 | 3,4 (8 à 15 min, VMs réelles) |
| k3d sur VM partagée | — | — | **4,4** (2 min, aucune adresse ni VMID : E18) |

## Décision

1. **Production : kubeadm + Ansible, sans changement de distribution** pendant la durée du programme. `k8s-par1` garde ADR-0140 et ADR-0141. RKE2 sera réexaminé lors de la prochaine refonte du cluster, sur la base de l'effort de durcissement mesuré au M26.
2. **Agence de Lyon : k3s**, trois serveurs en etcd intégré, montées par system-upgrade-controller (plans versionnés), instantanés toutes les 6 h vers `s3-01` par la liaison inter-sites, configuration par le rôle `k3s`. Talos reste l'alternative si l'agence ne peut garantir aucun accès console.
3. **Recettes éphémères : k3d** sur une VM partagée dédiée, pilotée par `task recette:creer|detruire` (E18), avec un port publié par équipe. Cluster API est réservé aux recettes qui doivent tourner **sur des VMs** (essais de panne de nœud, stockage) ; il n'est **pas** retenu pour la production.
4. **Cycle de vie** : Cluster API n'est pas adopté comme outil standard tant que CAPMOX n'est pas en 1.x, documenté sur Proxmox VE 9 et compatible avec la Cluster API courante (E16 : CAPMOX bloque Cluster API en 1.12). On garde Ansible + runbooks pour `k8s-par1` et system-upgrade-controller pour k3s.
5. **Fin de module** :
   - `k3s01` et le cluster de gestion sont détruits, après une dernière archive (RB-181 §5) conservée 30 jours ;
   - les templates 9060 et 9061 sont supprimés (reconstructibles par le code d'image-builder) ;
   - le compte `wb-capi@pve` et son jeton sont supprimés (recréés par le code de M18-E08 si l'ADR est révisé) ;
   - toutes les VMs 2181-2188, 5180-5193 sont détruites, les flux provisoires fermés.

## Conséquences

Positives :
- une seule distribution de production et un seul savoir-faire d'astreinte ;
- le cas de Lyon reste simple ;
- les équipes ont des recettes en minutes, sans toucher au VLAN 40.

Négatives et actions :

| Conséquence | Action | Échéance |
|---|---|---|
| Deux distributions à suivre (kubeadm, k3s) : deux politiques de versions | Étendre ADR-0141 à k3s ; Renovate sur les plans system-upgrade-controller | M19 |
| Deuxième chaîne de sauvegarde (k3s S3 natif) | Alerte sur l'âge du dernier instantané, restauration trimestrielle (RB-181) | M21 |
| La VM de recettes partagée est un point unique, et tous ses utilisateurs sont administrateurs | Contrôle d'accès, quotas ; évaluer vCluster dans `k8s-par1` | M24, M28 |
| Recettes éphémères créées à la main | Pipeline ou `ApplicationSet` | M19, M20 |
| Durcissement de k3s à faire soi-même (pas de profil) | Guide de durcissement k3s, kube-bench | M26 |
| Cluster API écarté : la promesse « un cluster comme un Deployment » est perdue pour la production | Réexamen à chaque version majeure de CAPMOX | 2027-T2 |

## Critères de réexamen

- CAPMOX publie une 1.0, documente Proxmox VE 9 et suit la Cluster API courante.
- L'équipe passe à plus de trois clusters de production, ou à plusieurs sites actifs.
- Le M26 montre que porter `k8s-par1` au référentiel CIS coûte plus qu'une migration vers RKE2.
- Un incident d'OS sur les nœuds (CVE, dérive) qu'une distribution immuable (Talos) aurait évité.
