# Chronologie de la reconstruction de `k8s-par1` (CHG-3107)

> Modèle du corrigé de F1-S07 (complété en S08 à S13). Les heures et durées sont les **tiennes** :
> elles viennent du journal de la fenêtre (`~/day0/chronologie.tsv`, écrit par `plateforme/k8s/outils/day0/*.sh`)
> et de tes notes. Une ligne par étape ; « attente » = temps passé à attendre une machine (installation,
> tirage d'images, convergence), pas un humain. Les gestes manuels sont marqués **GESTE** : chacun
> devient une ligne de dette du rapport (S15) ou une MR citée.

| | |
|---|---|
| Fenêtre | CHG-3107, ouverte le <AAAA-MM-JJ> à <HH:MM> (go de Claire Morel sur CHG-3104) |
| Fin de la coupure | <AAAA-MM-JJ HH:MM> (réouverture annoncée par Nadia, F1-S11) |
| Coupure totale | <durée> |
| Référence | `reference-avant.md` (S04) et section « Gel » ajoutée en S07 |

## Phase 3 — S07 : gel et nœuds

| Heure | Étape | Durée | dont attente | Remarque |
|---|---|---|---|---|
| <HH:MM> | Contrôle du filet (`lab/bin/check F1 4`) | | | vert, sauvegardes de moins de 24 h |
| <HH:MM> | Point Nadia : début du gel | — | — | centres prévenus |
| <HH:MM> | **GESTE** Argo CD arrêté (contrôleurs à 0 réplique) | | | sinon l'auto-réparation de la recette remet des réplicas ; cluster détruit ensuite |
| <HH:MM> | Écritures arrêtées (Rollouts `mediagenda` recette et prod à 0, `portail` à 0, CronJobs suspendus) | | | HPA inactif sur une cible à 0 |
| <HH:MM> | Files `notifications` vidées par MédiNotif | | | 0 et 0 messages |
| <HH:MM> | Compteurs du gel | | | rendez-vous prod <N>, recette <N> ; écart avec S04 : <N> rendez-vous pris entre S04 et le gel |
| <HH:MM> | `pg_switch_wal()` + sauvegarde de base des trois bases | | | `…-gel-<horodatage>` completed |
| <HH:MM> | **Point de non-retour** : `tofu apply` (remplacement des cinq VMs clonées) | | | plan relu : 5 remplacements, rien d'autre |
| <HH:MM> | Retrait de `k8s-w03` de `module.noeud` (`apply -destroy -target`) | | | plan relu : objets de `k8s-w03` seulement |
| <HH:MM> | Installation de `k8s-w03` par l'usine (`noeuds_usine` installation, job `provisionner`, `noeuds_usine` service, `--apres-bascule`) | | | VLAN 60 puis VLAN 40 |
| <HH:MM> | **GESTE** anciennes clés d'hôte SSH retirées de `~/.ssh/known_hosts` | | | clés d'hôte neuves, certificats SSH d'hôte pas encore posés |
| <HH:MM> | Inscription FreeIPA nœud par nœud | | | ré-inscription forcée (hôtes déjà présents) |
| <HH:MM> | `k8s-reconstruction.yml` : nœuds, durcissement, fichiers de l'API | | | |
| <HH:MM> | Amorçage (`kubeadm init` sur `k8s-cp01`) et jonctions | | | une seule VIP |
| <HH:MM> | `admin.conf` du nouveau cluster, compte `wb-checks` recréé | | | ancien `admin.conf` invalide |
| <HH:MM> | Point Nadia : nœuds prêts | — | — | |

## Phase 3 — S08 à S11

| Heure | Étape | Durée | dont attente | Remarque |
|---|---|---|---|---|
| <HH:MM> | S08 : CRD Gateway API, Cilium, BGP, LB IPAM | | | |
| <HH:MM> | S08 : **amorçage des secrets** (`outils/amorcer-secrets.sh appliquer`) | | | <N> Secrets, lus dans OpenBao avec ma session OIDC |
| <HH:MM> | S08 : **GESTE** approbation des CSR de kubelets (`outils/approuver-csr-kubelet.sh`) | | | <N> demandes vérifiées |
| <HH:MM> | S08 : cert-manager, ExternalDNS, stockage, CNPG, Velero, metrics-server, CI, Argo CD | | | |
| <HH:MM> | S09 : MR `plateforme/secrets` (autorité du nouveau cluster), pipeline | | | |
| <HH:MM> | S09 : ESO, adoption des Secrets d'amorçage | | | <N>/<N> adoptés |
| <HH:MM> | S10 : application racine, convergence | | | <N> Applications ; bloquées : … |
| <HH:MM> | S11 : récupération des trois bases, secours, OpenBao, RabbitMQ | | | |
| <HH:MM> | S11 : **réouverture du service** (Nadia) | — | — | fin de la coupure |

## Amorçage des secrets (S08) et reprise par ESO (S09)

| Secret (espace/nom) | Chemin OpenBao | Lu par | Heure | ExternalSecret repreneur | Adopté |
|---|---|---|---|---|---|
| `external-dns/tsig-externaldns-k8s` | `kv/plateforme/external-dns/tsig` | `<MOI>` (OIDC) | <HH:MM> | `external-dns/tsig-externaldns-k8s` | oui |
| … | | | | | |

## MR de la fenêtre

| MR | Dépôt | Objet | Fusionnée à |
|---|---|---|---|
| !<N> | `plateforme/k8s` | <ex. ordre des CRD Gateway API avant Cilium dans le Taskfile> | <HH:MM> |
