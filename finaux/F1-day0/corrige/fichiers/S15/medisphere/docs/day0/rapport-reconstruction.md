# Rapport de reconstruction de `k8s-par1` — Day 0 (CHG-3107)

> Modèle du corrigé de F1-S15 : la structure et le niveau de détail attendus. Les chiffres entre
> chevrons sont les **tiens** (chronologie) ; les exemples de constats sont ceux qu'on rencontre
> typiquement sur ce lab, à remplacer par ce qui t'est arrivé.

| | |
|---|---|
| Demande | Sophie Laurent (RSSI), audit HDS ; décision de Claire Morel (CHG-3104 go/no-go, CHG-3107 fenêtre) |
| Périmètre | `k8s-par1` détruit et reconstruit à blanc (VMID 2141-2146), `lb02` et `dns02` reconstruits (phase 2), `k8s-w03` installé par l'usine PXE |
| Rédaction | <MOI> ; relu par Karim Benali, Nadia Roussel |
| Sources | `chronologie.md`, `reference-avant.md`, `donnees-apres.md`, `recette-day0.md`, post-mortem INC-5712 |

## 1. Résumé

Le <AAAA-MM-JJ>, `k8s-par1` a été détruit puis reconstruit **depuis le code seul** (OpenTofu, Ansible,
Helmfile, OpenBao, Argo CD) en <durée> de coupure du service MédiAgenda (estimation de la carte
d'amorçage : <durée>, écart <+N %>). **Aucune donnée perdue** : <N> rendez-vous en production au gel
comme après, files vides des deux côtés. <N> gestes manuels ont été nécessaires ; <N> sont devenus du
code pendant la fenêtre, <N> restent en dette (§4). Un incident d'après-reconstruction (INC-5712,
<cause en une ligne>) a été corrigé en <durée>. La recette `day0-v1` est prononcée le <AAAA-MM-JJ>.

## 2. Durées mesurées et écart à l'estimation (S01)

| Phase / étape | Estimation S01 | Mesuré | dont attente machine | Écart | Explication |
|---|---|---|---|---|---|
| Gel (écritures, files, sauvegardes après gel) | <h:mm> | <h:mm> | <h:mm> | <±N %> | <ex. sauvegarde de base de la prod plus longue que prévu (taille)> |
| Destruction + création des six VMs (OpenTofu) | | | | | |
| `k8s-w03` par l'usine (PXE, preseed, bascule VLAN) | | | | | <ex. étape oubliée de l'estimation : bascule de VLAN> |
| Ansible : inscription FreeIPA, durcissement, kubeadm | | | | | <ex. durcissement un nœud à la fois : 6 × N min> |
| Couche de base (Helmfile) | | | | | <ex. tirage des images par le cache Harbor à froid> |
| Identité et secrets (MR, pipeline, ESO) | | | | | <ex. attente d'approbation de MR> |
| Plateforme par Argo CD (convergence) | | | | | |
| Données (récupérations, secours, OpenBao) | | | | | |
| **Coupure totale** (gel → réouverture) | | | | | |
| Recette (hors coupure) | | | | | |

Lecture : <ex. 60 % du temps est de l'attente machine, dont 40 % de tirages d'images et 20 % de
récupérations PostgreSQL ; les écarts viennent surtout d'étapes absentes de l'estimation, pas de
lenteur des étapes connues.>

## 3. Dépendances circulaires : prévues (S01) et rencontrées

| Boucle | Prévue en S01 | Rencontrée | Comment elle a été cassée | Coût |
|---|---|---|---|---|
| ESO ← Argo CD ← identifiants de dépôts ← ESO | oui | oui | amorçage de deux Secrets d'Argo CD et des Secrets de la couche de base (`outils/amorcer-secrets.sh`), repris par ESO en S09 | <N min>, <N> lectures humaines dans OpenBao |
| OpenBao ← autorité du cluster ← cluster neuf | oui / non | oui | MR de `plateforme/secrets` (fichier `racine/k8s-par1-ca.crt`) | <N min> |
| Kubelets ← approbateur (Argo CD) ← metrics-server, `kubectl logs` | <…> | oui | approbation vérifiée à la main (`outils/approuver-csr-kubelet.sh`) | <N> gestes |
| OpenBao ← autorité propre à chaque base CNPG | <…> | oui | copie dans `plateforme/ansible` + `coffre.yml` | <N min> |
| Migrations (hook Sync) ← base de production | <…> | oui | synchronisation sélective de la base d'abord | <N min> |
| <…> | | | | |

## 4. Gestes manuels

| # | Heure | Geste | Raison | Statut | Responsable | Échéance |
|---|---|---|---|---|---|---|
| G1 | <HH:MM> | Argo CD arrêté au gel | l'auto-réparation remettait des réplicas en recette | **dette** : intégrer au gel une mise en pause d'Argo CD par le code (ApplicationSet) | <MOI> | <AAAA-MM-JJ> |
| G2 | <HH:MM> | Anciennes clés d'hôte SSH retirées | VMs neuves, certificats SSH d'hôte posés plus tard | **dette** : poser le certificat d'hôte par cloud-init/preseed | | |
| G3 | <HH:MM> | Secrets d'amorçage lus dans OpenBao | boucle ESO/Argo CD | **assumé** (amorçage justifié, inventaire des secrets) ou dette (ADR-0310 option B) | | |
| G4 | <HH:MM> | CSR de kubelets approuvées | approbateur absent | **dette** : approbateur dans Helmfile | | |
| G5 | <HH:MM> | Racine d'Argo CD et Applications d'amorçage d'ESO appliquées | seul objet à la main prévu | assumé | | |
| G6 | <HH:MM> | Nouvel `admin.conf` dans le Vault `critique` | bris de glace | assumé (procédure RB-310 §6) | | |
| <…> | | | | | | |

## 5. Ce qui a cassé, ce qui a surpris, ce qui a bien marché

- **Cassé** : <ex. tâche du dépôt qui créait les bases CNPG avec le reste de `espaces/` ; corrigée par MR !N>.
- **Surpris** : <ex. la ré-inscription FreeIPA d'hôtes déjà connus ; l'archive d'origine protégée par « Expected empty archive »>.
- **Incident INC-5712** : <cause, détection, durée ; renvoi au post-mortem>.
- **Bien marché** : <ex. Argo CD a reconstruit N Applications sans intervention ; Thanos a rendu tout l'historique ; aucune donnée perdue>.

## 6. Actions

| Action | Responsable | Échéance | Ticket |
|---|---|---|---|
| <ex. ADR-0310 : options retenues mises en œuvre> | <MOI> | <AAAA-MM-JJ> | PLAT-<N> |
| <ex. Purge des volumes et archives de l'ancien cluster (revue)> | Claire Morel | <AAAA-MM-JJ> | CHG-<N> |
| <ex. Exercice annuel de reconstruction inscrit au PCA> | Nadia Roussel | <AAAA-MM-JJ> | PLAT-<N> |
