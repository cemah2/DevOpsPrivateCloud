# Mesure du durcissement de `k8s-par1`

> SEC-2705 — mesure du <AAAA-MM-JJ> par `<MOI>`, avant toute modification du cluster (module 26, palier 1). Résultats bruts : [`mesures/k8s-par1/`](mesures/k8s-par1/). Document interne, diffusion restreinte.

## Outils, versions, référentiels

| Outil | Version | Référentiel | Où |
|---|---|---|---|
| kube-bench | 0.16.0 (image `aquasec/kube-bench:v0.16.0` par le cache Harbor) | **`cis-1.12`** (CIS Kubernetes Benchmark v1.12, prévu pour 1.32 à 1.34) **forcé** | Jobs dans `wb-diagnostic`, sur `k8s-cp01` (cibles `master`, `controlplane`, `etcd`, `node`, `policies`) et `k8s-w01` (`node`) |
| kubescape | 4.0.x (CLI, sans opérateur) | cadres `NSA`, `MITRE`, `cis-v1.12.0` | depuis `adm01`, accès OIDC `plateforme-admins`, `--keep-local` |

**Écart de référentiel (pour l'auditeur).** Le cluster est en Kubernetes **1.36** ; aucun CIS Kubernetes Benchmark publié ne couvre cette version et kube-bench 0.16 n'associe `cis-1.12` qu'aux versions 1.32 à 1.34. Nous mesurons contre `cis-1.12` en connaissance de cause : les contrôles portent sur des fichiers, des drapeaux et des réglages qui n'ont pas changé de sens entre 1.34 et 1.36 ; un contrôle qui viserait une option supprimée ou renommée est classé « faux positif de version ». Nous reprendrons la mesure dès qu'un référentiel 1.36 paraîtra (veille : E24, revue trimestrielle).

## Résultats kube-bench

| Nœud | PASS | FAIL | WARN | INFO |
|---|---|---|---|---|
| `k8s-cp01` | `<N>` | `<N>` | `<N>` | `<N>` |
| `k8s-w01` | `<N>` | `<N>` | `<N>` | `<N>` |

### Classement des FAIL

Classement : **E** vrai écart ; **FP-C** faux positif de chemin ; **FP-V** faux positif de version ; **C** choix assumé (kubeadm ou lab) ; **M** à vérifier à la main. Les lignes ci-dessous sont celles qu'on attend sur un nœud kubeadm Debian 13 du lab : remplace-les par **tes** résultats.

| ID | Contrôle (court) | Nœud | Classement | Justification (vérifiée sur le nœud) | Suite |
|---|---|---|---|---|---|
| 1.1.12 | dossier d'etcd possédé par `etcd:etcd` | cp01 | C | kubeadm lance etcd en pod statique sous root, sans utilisateur `etcd` sur l'hôte ; `stat -c %U:%G /var/lib/etcd` → `root:root`, droits 700 (1.1.11 passe) | exception écrite (E23) ; un etcd externe sous utilisateur dédié est hors périmètre |
| 1.2.15, 1.3.2, 1.4.1 | `--profiling=false` (apiserver, contrôleur, ordonnanceur) | cp01 | E | `ps -o args -C kube-apiserver` : pas de `--profiling` ; le point `/debug/pprof` est exposé aux comptes autorisés | rôle `k8s_plan_controle` (un nœud de contrôle à la fois), avec E25 |
| 1.2.17-1.2.19 | rétention du journal d'audit (`maxage`, `maxbackup`, `maxsize`) | cp01 | C ou E | M14-E27 a posé le journal ; vérifie les trois drapeaux : s'ils manquent, c'est un vrai écart (disque plein) même si Alloy expédie le journal à Loki | E28 |
| 1.2.5 | `--kubelet-certificate-authority` | cp01 | E | l'apiserver ne vérifie pas le certificat de service des kubelets (auto-signé par kubeadm) | **E25** (`serverTLSBootstrap`, kubelet-csr-approver) |
| 4.1.1 | fichier de service du kubelet en 600 | cp01, w01 | E (mineur) | `/lib/systemd/system/kubelet.service` du paquet en 644 ; le drop-in `10-kubeadm.conf` des paquets `pkgs.k8s.io` est sous `/usr/lib/systemd/system/kubelet.service.d/`, chemin que kube-bench ne connaît pas (FP-C pour lui) | rôle `k8s_noeud` ; risque faible (pas de secret dans ces fichiers) |
| 4.2.x (`--read-only-port`, `--make-iptables-util-chains`…) | réglages du kubelet | w01 | FP-C ou PASS | kubeadm règle le kubelet par `/var/lib/kubelet/config.yaml`, pas par des drapeaux : vérifie la clé correspondante (`readOnlyPort: 0` par défaut) avant de conclure | — |
| 4.2.11 / 4.2.12 | certificat de service du kubelet tourné, chiffrements forts | cp01, w01 | E / M | `serverTLSBootstrap` absent ; `tlsCipherSuites` non fixé | E25 |
| 4.2.14 | `seccompDefault: true` | cp01, w01 | E | absent de `config.yaml` du kubelet | E25 (et `seccomp-par-defaut`, E16) |
| 5.x (politiques) | RBAC, Pod Security, NetworkPolicy, Secrets | — | M | contrôles manuels : la réponse est dans `pod-security.md` (E06), la matrice des flux (M15) et l'inventaire des secrets (M25) | E06, E16 |

## Résultats kubescape

| Cadre | Score |
|---|---|
| NSA | `<SCORE>` |
| MITRE | `<SCORE>` |
| cis-v1.12.0 | `<SCORE>` |

Résumé publiable : [`mesures/k8s-par1/kubescape-resume.json`](mesures/k8s-par1/kubescape-resume.json) (contrôles en échec et nombre de ressources ; le rapport complet n'est pas versionné).

**Cinq constatations** (à adapter à ton relevé) :
1. Les contrôles « Non-root containers », « Allow privilege escalation », « Immutable container filesystem » échouent surtout dans les espaces privilégiés par nature (`supervision-noeuds`, `ceph-csi`, `velero`, `journaux`, `wb-diagnostic`) : ils sont **attendus** et deviennent des exceptions écrites (E06, E23).
2. Plusieurs charges de plateforme n'ont ni limites de CPU ni de mémoire (« Resource limits ») → `exiger-limites` (E16), en audit d'abord.
3. Des comptes de service montent leur jeton sans en avoir besoin (« Automatic mapping of service account ») → E21 et règle Falco de lecture du jeton (E19).
4. « Images from allowed registry » passe dans les espaces d'équipes (VAP du M14) mais pas partout : les charts de plateforme tirent par le miroir de containerd sans préfixe Harbor explicite → décision en E07 (registres explicites pour les nouveaux composants).
5. Les contrôles qui demandent les fichiers des nœuds sont **ignorés** par kubescape sans son opérateur : c'est kube-bench qui les couvre.

## Ce que l'absence de référentiel 1.36 implique

Nous ne pouvons pas écrire « conforme au CIS Kubernetes ». Nous écrivons : « mesuré contre CIS Kubernetes 1.12 (dernier publié), écarts classés, faux positifs de version et de chemin justifiés, écarts réels traités par les exercices E06, E16, E25, E28 ». C'est ce que l'auditeur peut vérifier.
