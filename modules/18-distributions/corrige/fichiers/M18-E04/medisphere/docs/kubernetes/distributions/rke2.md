# RKE2 — fiche de l'essai `rke2` (profil CIS)

> M18-E04 (SEC-1904). Code : rôle `rke2`, `rke2/` de `plateforme/distributions`.

## Topologie

Trois serveurs Rocky Linux 10 (`rke2-01..03`), tous nœuds de contrôle et membres etcd. Adresse
d'enregistrement : superviseur de `rke2-01` (`https://rke2-01.par1.medisphere.internal:9345`).
**Limite** : sans répartiteur ni VIP, la perte de `rke2-01` empêche les **nouveaux** nœuds de
rejoindre, et le kubeconfig de `adm01` (qui vise `rke2-01`) ne répond plus ; les deux autres
serveurs continuent (quorum 2/3). En production : VIP (keepalived ou kube-vip) ou répartiteur
TCP devant 9345 et 6443.

## Prérequis de l'hôte

OS supporté (RHEL 10 et dérivés ; pas Debian), `kernel-modules-extra`, utilisateur `etcd`,
paramètres noyau CIS chargés avant le premier démarrage, firewalld arrêté (conflit avec Canal),
NetworkManager configuré pour ignorer `flannel*`, `cali*`…, SELinux *enforcing* avec
`rke2-selinux` (installé par le RPM).

## Effets du profil observés

- `ps -o user= -C etcd` → `etcd` ; `/var/lib/rancher/rke2/server/db/etcd` à `etcd:etcd` (700).
- `/etc/rancher/rke2/rke2-pss.yaml` : `enforce`, `audit`, `warn` à `restricted` par défaut,
  exemptions `kube-system`, `compliance-operator-system`, `tigera-operator`.
- NetworkPolicies dans `kube-system`, `kube-public` et `default` : trafic limité à l'espace, sauf
  DNS, metrics-server, Ingress et webhook de snapshots. **Les nouveaux espaces n'en ont pas** :
  c'est à nous de les écrire.
- Le compte de service `default` sans montage automatique de jeton dans `kube-system` (pas dans
  les espaces que nous créons : à faire nous-mêmes).
- Un pod sans `securityContext` est **refusé** dans un espace applicatif ; un pod conforme passe.
- Processus `rke2 server` dans le domaine SELinux `container_runtime_t`.

## Ce que je montre à l'auditeur

1. le `config.yaml` (`profile: cis`) et la version (`rke2 --version`) ;
2. le guide d'auto-évaluation CIS v2.0 de RKE2 (versions ≥ 1.35) et les contrôles « manuels » qu'il
   laisse à notre charge, avec, pour chacun, la mesure MédiSphère ;
3. au palier 3, un passage de kube-bench (aperçu) et l'écart restant.

## Accès

`~/.config/workbook/m18/rke2.kubeconfig` (600), contexte `rke2`.
