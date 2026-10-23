# RB-356 — Le cluster de secours `k8s-par2`

| | |
|---|---|
| Ticket | PLAT-3506 ; changement de la production : CHG-3506 (topologie distribuée de `mediagenda-db`, repère de site) |
| Cluster | `k8s-par2`, nœud unique `k8s-par2-n01` (1054, 10.20.20.50, 5 Go), API `k8s-api.par2.medisphere.internal:6443` |
| Accès | `admin.conf` de `k8s-par2` (enveloppe E7) sur `adm02` ; vérifications : `~/.config/workbook/k8s-par2-checks.kubeconfig` |
| Durée de référence | construction complète : 3 h 30 (nœud 40 min, couche de base 1 h, base 45 min, applications 45 min) |

## 1. Même code, fichiers de site

| Domaine | Code commun (PAR1 et PAR2) | Fichier de site de PAR2 |
|---|---|---|
| VM | `vm-par2` (`envs/par2`) — équivalent local de `vm-noeud` | `envs/par2/hotes.tf` (`k8s-par2-n01`) |
| Nœud | rôles `containerd`, `k8s_noeud`, `k8s_plan_controle` | `group_vars/k8s_par2/{kubernetes,containerd}.yml` (nœud unique sans *taint*, miroir `reg02`, pas de VIP) |
| Couche de base | `helmfile.yaml`, `releases/*.yaml.gotmpl`, `composants/*/values.yaml` | environnement `par2` : `environnements/par2.yaml`, `composants/cilium/values-par2.yaml` (L2, pas de BGP), stockage local |
| Réseau, certificats, passerelle | (gw-par1 : M15) | `sites/par2/reseau/lb-par2.yaml`, `sites/par2/certificats/autorite-par2.yaml`, `sites/par2/passerelles/gw-par2.yaml` |
| Base | `components/dependances` (Cluster de prod) | `sites/par2/mediagenda-prod/` : `mediagenda-db-par2`, ObjectStores, Services, ExternalSecrets |
| Applications | overlays `prod` (et `recette` de MédiDoc) | overlays `prod-par2` (`recette-par2`) : base retirée, réplicas 0, routes et repère, témoin suspendu |
| Livraison | `plateforme/gitops` (`projets/`) | `sites/par2/` (racine et ApplicationSet sur les miroirs) |
| Secrets | `SecretStore` par espace (M25) | serveur et méthode `k8s-par2` ; `outils/amorcer-par2.sh` |

Différences assumées (ADR-0350) : pas de Ceph (stockage local), pas d'observabilité, pas de Kyverno (les images n'arrivent sur `reg02` qu'après vérification de leur signature par le job de copie), pas de CI, pas d'ExternalDNS (joker `*.apps.par2` dans le DNS).

## 2. Construire

1. VM : `absentes` sans `k8s-par2-n01` dans `envs/par2` ; `tofu apply` depuis `adm02`.
2. Nœud : `uv run ansible-playbook playbooks/k8s-noeuds.yml --limit k8s_par2` (playbook du M14, groupe de site) ; `kubeadm init` par le rôle `k8s_plan_controle` (configuration v1beta4 rendue avec les valeurs du groupe) ; `admin.conf` copié dans l'enveloppe.
3. Couche de base : `helmfile -e par2 apply` (Cilium avec `values-par2.yaml`, cert-manager, CloudNativePG et son plugin, ESO, Argo CD, stockage local) ; `kubectl apply --server-side -f sites/par2/{reseau,certificats,passerelles,rbac}/`.
4. Amorçage : `outils/amorcer-par2.sh ~/src/ansible` (autorité, identifiants des miroirs, tirage `reg02`, kubeconfig des vérifications).
5. Méthode `k8s-par2` dans le coffre de PAR1 : MR sur `plateforme/secrets` (`tofu/k8s-par2.tf`), apply par le pipeline ; ExternalSecrets `Ready`.
6. Base : `kubectl apply --server-side -f sites/par2/mediagenda-prod/` ; suivi `kubectl cnpg status mediagenda-db-par2 -n mediagenda-prod` (récupération depuis la sauvegarde de base copiée, puis rejeu continu).
7. PAR1 (fenêtre, CHG-3506, sonde de continuité) : correctif `topologie-distribuee.yaml` et repère `par1` dans `mediagenda/deploiement` ; synchronisation manuelle de `mediagenda-prod` ; contrôles : `kubectl cnpg status mediagenda-db -n mediagenda-prod` primaire, archivage continu, réponse `X-MediSphere-Site: par1`.
8. Applications de PAR2 : `kubectl apply -f sites/par2/racine-par2.yaml` (Argo CD de `k8s-par2`) ; synchronisation manuelle de chaque application ; aucun pod applicatif ne démarre (réplicas 0).

## 3. Contrôler la veille

- `kubectl get nodes` (`Ready`), mémoire du nœud < 4,5 Go utilisés (`kubectl top node` si metrics-server, sinon `free -m` sur le nœud).
- `curl -sI --resolve mediagenda.medisphere.internal:443:10.20.20.200 https://mediagenda.medisphere.internal/sante` : réponse de la Gateway (503 attendu : aucun pod), certificat émis par l'autorité de PAR2.
- Retard du réplica : `kubectl cnpg status mediagenda-db-par2 -n mediagenda-prod` (dernier WAL rejoué) et requête du témoin (§6) des deux côtés ; écart attendu ≤ 10 min.
- `lab/bin/check F5 6`.

## 4. Secrets : en veille et en PRA

| | Veille | PRA |
|---|---|---|
| Source d'ESO | coffre de **PAR1** (`openbao.par1`, méthode `k8s-par2`, par `wg0`) | **`bao-par2`** (même méthode, restaurée dans l'instantané) |
| Comment on passe de l'un à l'autre | — | paramètre de l'Application (sans commit) qui remplace `server` des `SecretStore`, ou commit sur le miroir (forge du PRA) ; `kubectl annotate externalsecret --all force-sync=$(date +%s) -n <espace>` |
| Secrets statiques (S3, AMQP, racine…) | créés et tenus à jour | **déjà là** : ESO ne les efface pas quand la source ne répond pas (`deletionPolicy: Retain`) |
| Identifiants dynamiques de la base | émis par le coffre de PAR1 (utilisateurs créés sur le primaire de PAR1, présents à PAR2 par réplication) ; inutiles en veille (API à 0) | **périmés** (baux d'une heure) : moteur `db-mediagenda` de `bao-par2` repointé vers `10.20.20.205:5432` (Service `mediagenda-db-par2-openbao`), rôle `openbao` inchangé (son mot de passe est dans la base répliquée) ; puis nouveaux identifiants par ESO |
| Autorité de certificats | `medisphere-par2-ca` (amorçage) | inchangé |

Commande de repointage (PRA, `bao-par2`) : `bao write db-mediagenda/config/mediagenda-prod connection_url='postgresql://{{username}}:{{password}}@10.20.20.205:5432/mediagenda?sslmode=verify-ca' …` — reprends **exactement** les autres paramètres de la configuration existante (`bao read db-mediagenda/config/mediagenda-prod`), dont le certificat d'autorité de la base : celui de `mediagenda-db-par2` est différent de celui de PAR1 (CloudNativePG en génère un par cluster).

## 5. Bascule de la base (rappel de la documentation CloudNativePG 1.30)

- **PAR1 perdu (sinistre)** : sur `mediagenda-db-par2`, `spec.replica.primary: mediagenda-db-par2` **sans** jeton (et `source` inchangée). Promotion immédiate ; l'ancien primaire de PAR1 devra être **reconstruit** comme réplica de PAR2 au retour (RB-351). C'est un **point de non-retour** (RB-350).
- **Bascule contrôlée (PAR1 vivant, retour ou exercice planifié)** : sur le primaire, `primary` → l'autre cluster ; lire `.status.demotionToken` ; sur l'autre, `primary` **et** `promotionToken` **dans la même modification**. Le cluster promu attend d'avoir rejoué jusqu'au jeton. `minApplyDelay` est incompatible avec `promotionToken`.

## 6. Le témoin et la requête du RPO

```
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-prod -- -d mediagenda -Atc \
    "SELECT max(cree_le), max(motif) FROM rendez_vous WHERE praticien = 'PRA-TEMOIN'"
2026-11-14 10:41:00.512+01|2026-11-14T09:41:00Z
admin@adm02:~$ kubectl --context k8s-par2 cnpg psql mediagenda-db-par2 -n mediagenda-prod -- -d mediagenda -Atc \
    "SELECT max(cree_le), max(motif) FROM rendez_vous WHERE praticien = 'PRA-TEMOIN'"
2026-11-14 10:36:00.498+01|2026-11-14T09:36:00Z
```

Retard en veille = 5 min (un segment de WAL non encore archivé). **RPO de l'exercice** = dernier témoin écrit à PAR1 avant T0 (lu au retour, sur l'ancien primaire, ou dans les journaux du CronJob) − dernier témoin présent à PAR2 après la promotion. Le témoin est un **écrivain réel** (API → pooler → base) : il mesure ce qu'un patient aurait perdu, pas seulement l'état de la réplication.

## 7. Retour arrière

- PAR2 : `helmfile -e par2 destroy` et `tofu destroy -target` de la VM : rien à PAR1 n'en dépend.
- PAR1 : retirer `topologie-distribuee.yaml` et le repère de `overlays/prod` (MR), synchroniser : la base redevient une base simple, sans redémarrage ; l'archive de PAR1 n'a jamais changé de nom.
