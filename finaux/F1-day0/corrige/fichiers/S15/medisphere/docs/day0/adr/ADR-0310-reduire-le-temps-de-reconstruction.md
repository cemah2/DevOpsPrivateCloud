# ADR-0310 — Réduire le temps de reconstruction de `k8s-par1`

| | |
|---|---|
| Statut | Proposé par <MOI> le <AAAA-MM-JJ> ; décidé par Claire Morel le <AAAA-MM-JJ> |
| Contexte | Day 0 (CHG-3107, `rapport-reconstruction.md`) : coupure de <h:mm>, dont <N> % d'attente machine et <N> gestes manuels |
| Relecteurs | Karim Benali, Sophie Laurent (amorçage des secrets), Nadia Roussel (exploitation) |

## Contexte

Mesures du Day 0 (à reporter des tiennes) : nœuds <h:mm> (dont durcissement <mm> min, usine <mm> min),
couche de base <h:mm> (dont tirages d'images à froid <mm> min), identité et secrets <mm> min (dont
attente de MR et de pipeline <mm> min), Argo CD <mm> min, données <h:mm> (récupérations PostgreSQL
<mm> min). Gestes manuels : <N> (rapport §4). Objectif fixé par Claire : RTO de reconstruction ≤ <h:mm>
pour le plan de continuité, sans affaiblir la sécurité.

## Options

| | A. Statu quo outillé | B. ESO avant la couche de base | C. Images préchargées et nœuds « dorés » | D. Récupérations en parallèle et `serverName` versionnés |
|---|---|---|---|---|
| Idée | garder l'ordre du Day 0, enchaîner les scripts `outils/day0/` sans pause | installer ESO et le ClusterSecretStore par Helmfile juste après Cilium : plus aucun Secret d'amorçage lu par une personne | image dorée `k8s-noeud` (M03) avec containerd, kubeadm et les images de la couche de base préchargées (`ctr images import`) ; durcissement appliqué à l'image | les trois récupérations CNPG lancées ensemble ; `serverName` suffixé d'une génération (`-g2`, `-g3`…) écrit d'avance dans les dépôts |
| Gain estimé (mesures du Day 0) | <−N min> (pauses) | <−N min> et −<N> gestes ; amorçage limité aux identifiants d'Argo CD | <−N min> (tirages, durcissement) | <−N min> |
| Coût | nul | ESO sort d'Argo CD (une release Helmfile de plus) ; la méthode `k8s-par1` doit être à jour **avant** la couche de base (ordre §4 → §3) | un pipeline d'images de plus ; images à reconstruire à chaque montée ; `k8s-w03` (usine) ne profite pas du préchargement | discipline de nommage ; plus de charge sur `s3-01` pendant la récupération |
| Risques | aucun nouveau | ESO sans Argo CD : sa dérive se voit par `helmfile diff` seulement | images périmées (CVE) si le pipeline s'arrête | archive d'origine toujours protégée par le contrôle « Expected empty archive » |
| Sécurité (Sophie) | inchangée | **meilleure** : plus de valeur de secret dans un terminal | neutre si l'image est signée et analysée | neutre |

## Décision

<Exemple de décision argumentée : **B + D**, et C limité aux images (pas au durcissement). B supprime
la principale dépendance circulaire et les lectures humaines de secrets (exigence HDS de Sophie) pour
un coût faible ; D est presque gratuit. C est reporté : le gain est réel mais le coût de maintenance
d'une image de plus n'est pas justifié pour un exercice annuel ; on précharge seulement les images de
Cilium et de cert-manager par le cache Harbor (déjà là).>

## Conséquences

- `plateforme/k8s` : release `external-secrets` dans `releases/15-secrets.yaml.gotmpl` ; Application
  Argo CD retirée (reprise sans recréation : mêmes objets) ; `amorcage.conf` réduit aux identifiants
  de dépôts d'Argo CD (ou supprimé si Argo CD lit ses dépôts par l'ESO déjà installé).
- RB-310 : §4 (OpenBao) passe avant §3 ; durées de référence mises à jour après le prochain exercice.
- Exercice de reconstruction **annuel**, inscrit au plan de continuité (Nadia) ; prochain le <AAAA-MM-JJ>.

## Ce qu'on accepte de ne pas faire

- Pas de second cluster chaud (bleu/vert) : mémoire du lab, et le besoin est couvert par la
  reconstruction + le secours de la base (RB-275).
- Pas de sauvegarde/restauration d'etcd comme chemin de reconstruction : elle ramène l'ancien monde
  (identités, autorité) ; elle reste le filet de RB-141.
