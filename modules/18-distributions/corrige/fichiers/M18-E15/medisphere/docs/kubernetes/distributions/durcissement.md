# Durcissement comparé des distributions (M18-E15)

> Observations faites sur le lab le <AAAA-MM-JJ>. kube-bench **0.16.0** utilisé en aperçu : aucun de ses référentiels ne couvre Kubernetes 1.36 (générique : `cis-1.12` = 1.32-1.34 ; RKE2 : `rke2-cis-1.9` ; k3s : `k3s-cis-1.9`). Rapports bruts dans [`durcissement/`](durcissement/). Rien n'a été corrigé ici, sauf le chiffrement des Secrets de `k3s01` (SEC-1915).

| Critère | kubeadm (`k8s-par1`) | k3s (`k3s01`) | RKE2 (`rke2-01..03`, profil `cis`) | Talos (`talos-essai`) |
|---|---|---|---|---|
| Accès à l'OS | SSH + sudo (Debian 13, certificats SSH M06) | SSH + sudo | SSH + sudo (Rocky 10) | **aucun** : API `apid` 50000, TLS mutuel, rôles `os:*` |
| Ports exposés par nœud de contrôle | 22, 6443, 8443 (HAProxy), 2379-2380, 10250, 10257, 10259 | 22, 6443 (API + superviseur), 10250, 8472/udp | 22, 6443, 9345, 2379-2380, 10250, ports Canal | 50000, 50001, 6443, 2379-2380, 10250, ports du CNI |
| Utilisateur d'etcd | root (pod statique) | in-process dans `k3s` (root) | **`etcd`** (exigé par le profil) | service système de Talos (utilisateur dédié, à relever) |
| Pod Security par défaut | aucune (posée par espace en M14-E18) | aucune | **`restricted`** partout sauf `kube-system` et deux espaces | **`baseline`** imposé, `restricted` en audit et avertissement |
| NetworkPolicy par défaut | aucune (Cilium, M15) | aucune (contrôleur kube-router présent) | `kube-system`, `kube-public`, `default` limités à l'espace | aucune |
| Chiffrement des Secrets | `aescbc` (M14-E28) | **activé en E15** (`aescbc`, `k3s secrets-encrypt`) | à activer (même mécanisme que k3s) | activé par défaut (`secretbox`, clé dans les secrets Talos) — à confirmer sur ta version |
| Audit | politique M14-E27 | non configuré | politique par défaut du profil (journal sous `/var/lib/rancher/rke2/server/logs/`) | politique par défaut de Talos (`KubeAuditPolicyConfig`) |
| Confinement de l'OS | AppArmor (Debian) | AppArmor | **SELinux enforcing** (`rke2-selinux`) | système immuable, SquashFS en lecture seule, KSPP |
| Mises à jour de l'OS | `apt` + rôles Ansible | `apt` | `dnf` | image entière (`talosctl upgrade`), retour arrière A/B |
| kube-bench (référentiel) | non relancé ici (M26) | `k3s-cis-1.9` : PASS __ / FAIL __ / WARN __ | `rke2-cis-1.9` : __/__/__ ; `cis-1.12` : __/__/__ (FAIL surtout de chemin) | non pertinent : chemins absents, pod privilégié contraire à `baseline` |
| Effort estimé pour atteindre le CIS | élevé (tout à poser) | moyen (guide de durcissement k3s) | **faible** (profil + hôte) | faible côté Kubernetes, nul côté OS (pas d'OS à durcir) |

## Classement des FAIL de kube-bench (RKE2, `rke2-cis-1.9`)

| Contrôle | Résultat | Classement (vrai écart / faux positif chemin ou version / manuel) | Raison |
|---|---|---|---|
| | | | |

## Ce que le module 26 devra traiter

1. Industrialiser kube-bench (référentiel adapté à la version, exceptions écrites, passage planifié) et le compléter par Kubescape.
2. Admission (Kyverno) et détection (Falco, Tetragon) : aucune distribution ne les fournit.
3. Durcissement de l'OS des nœuds kubeadm et k3s (CIS Debian, Lynis, OpenSCAP), que seul Talos rend inutile.
