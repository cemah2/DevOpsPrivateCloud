### M25-E37 — Panne : un ExternalSecret en erreur  `BF` `★★`

> **Ticket INC-5237** — *De : Julien Petit*
> En recette, Argo CD affiche `mediagenda-recette` en *Degraded* : l'ExternalSecret `harbor-pull` est en `SecretSyncedError` et le Secret n'est plus mis à jour depuis le coffre. On n'a rien changé dans l'overlay de recette (vous pouvez vérifier l'historique). Tant que ça ne bouge pas, je bloque la rotation du robot Harbor de recette. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Diagnostiquer une synchronisation d'ESO en échec **sans lire les données du Secret** : condition, événements de l'ExternalSecret **et** du magasin, journaux du contrôleur, audit d'OpenBao.
- Situer la panne dans la chaîne ExternalSecret → SecretStore → connexion `k8s-par1` (compte de service, rôle, audience) → réseau → chemin KV lu dans le coffre, en commençant par la **portée** (un objet, un espace, tout le cluster).
- Comprendre deux mécanismes d'ESO qui trompent le diagnostic : le message générique de la condition (le détail n'est que dans les événements) et le **cache de jetons** OpenBao (un changement côté coffre peut ne se voir qu'au bout d'un quart d'heure).
- Corriger par le bon dépôt (`plateforme/k8s`, `plateforme/secrets` ou `plateforme/gitops`) et ajouter l'alerte qui aurait prévenu avant Julien.

**Prérequis** : M25-E12, M25-E13, M25-E14 ; `lab/bin/check 25 13` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique**
- ESO 2.13 (espace `external-secrets`, un seul contrôleur pour tout le cluster, cache de jetons OpenBao activé : `vault.enableTokenCache`, jetons de 15 min). Dans chaque espace applicatif, le compte `eso` et le SecretStore `openbao` sont posés par **`plateforme/k8s`** (`espaces/<espace>/80-openbao.yaml`, `task appliquer`, gestionnaire de champs `plateforme-k8s`) ; les ExternalSecret sont dans les overlays de `mediagenda/deploiement`, synchronisés par Argo CD (`selfHeal`).
- Côté coffre (**`plateforme/secrets`**, `tofu/eso-espaces.tf`) : rôle `eso-mediagenda-recette` de la méthode `k8s-par1` (compte `eso`, espace `mediagenda-recette`, audience `openbao.medisphere.internal`), politique `eso-mediagenda-recette` (lecture de `kv/data/mediagenda/recette/*` et des chemins `creds` de M25-E14).
- Réseau : la CiliumNetworkPolicy `external-secrets-sorties` (**`plateforme/gitops`**, `manifestes/external-secrets/`) n'autorise en sortie d'ESO que l'API, le DNS et `10.10.20.200:8200`. Hubble est disponible (M15).
- `harbor-pull` se rafraîchit toutes les heures ; les deux ExternalSecret d'identifiants dynamiques (`mediagenda-db-api`, `mediagenda-db-migrateur`) toutes les 30 min, pour des baux d'une heure.
- La panne peut toucher le cluster (objets **hors** de leur dépôt) ou le coffre. L'injection pose sur `harbor-pull` l'annotation `force-sync` pour que l'erreur apparaisse tout de suite : c'est une métadonnée, pas la cause.

> ⚠️ **Attention** : ne lis pas le contenu des Secrets (`kubectl get secret -o yaml`, `-o jsonpath='{.data}'`) pour diagnostiquer : statuts, événements et métadonnées suffisent. Ne corrige pas en modifiant l'ExternalSecret à la main : Argo CD le remettrait, et la cause resterait.

**Injection** : `lab/bin/break 25 37` (4 variantes ; jusqu'à 6 min d'attente pour constater la panne).

**Travail demandé**
1. **Mesure la portée.** ExternalSecret de `mediagenda-recette`, puis de tout le cluster ; état de **tous** les magasins (SecretStore de chaque espace, ClusterSecretStore `openbao`). Un objet, un espace, ou tout le cluster ? Note l'heure du dernier `refreshTime` réussi.
2. **Lis le vrai message.** La condition `Ready` ne donne qu'un message générique : trouve le détail dans les événements de l'ExternalSecret, puis dans ceux du magasin, puis dans les journaux du contrôleur d'ESO. Classe-le : refus du coffre sur un chemin, connexion refusée, compte introuvable, délai réseau.
3. **Remonte la chaîne** selon ce message, en comparant chaque maillon à son dépôt : `task diff` dans `plateforme/k8s` (magasin), `tofu plan` dans `plateforme/secrets` (rôle), les politiques Cilium de l'espace d'ESO face à `plateforme/gitops`. Si le coffre refuse, retrouve dans l'audit (Loki, locataire `audit`) le **chemin exact** que lit ESO et compare-le à ce que la politique `eso-mediagenda-recette` ouvre.
4. **Corrige par le bon dépôt**, puis obtiens une synchronisation immédiate sans toucher à la spec de l'ExternalSecret. Vérifie : magasin `Valid`, `harbor-pull` `SecretSynced` avec un `refreshTime` récent, application Argo CD saine, et que les identifiants dynamiques de recette ont repris leur rotation.
5. **Préviens** : alerte sur les ExternalSecret et les magasins en erreur dans `plateforme/observabilite` (règle testée par `promtool`), fiche réflexe « ExternalSecret en erreur » dans `docs/securite/secrets/`. Tiens ton journal de diagnostic.

**Critères de réussite**
- [ ] Le SecretStore `openbao` de `mediagenda-recette` est identique au dépôt (KV v2, montage `kv`, méthode `k8s-par1`, rôle `eso-mediagenda-recette`, compte `eso`, audience `openbao.medisphere.internal`) et `Ready` ; le rôle d'OpenBao attend la même audience ; aucun `egressDeny` ne vise la sortie d'ESO.
- [ ] Aucun magasin du cluster en erreur ; tous les ExternalSecret de `mediagenda-recette` `SecretSynced`, `harbor-pull` synchronisé depuis moins de 70 min.
- [ ] Une alerte sur `externalsecret_status_condition` est chargée dans Prometheus ; ton journal de diagnostic (un fichier dont le nom contient `INC-5237`, dans le dossier des journaux du palier) cite le message exact (sans valeur de secret) et la cause.

**Vérification** : `lab/bin/check 25 37`

<details><summary>Indice 1</summary>

`kubectl -n mediagenda-recette describe externalsecret harbor-pull` montre les événements `UpdateFailed`. S'ils disent seulement « SecretStore "openbao" is not ready », le détail est dans `kubectl -n mediagenda-recette describe secretstore openbao`. Si **tous** les magasins du cluster sont en erreur en même temps, l'overlay de recette n'y est pour rien.
</details>

<details><summary>Indice 2</summary>

Dans le SecretStore, `path` désigne le **moteur** (`kv`) et `version` dit à ESO comment construire le chemin : en `v2`, il insère `data/`. Un 403 sur `…/v1/kv/mediagenda/recette/…` n'est pas un problème de politique trop étroite. Côté connexion, OpenBao compare l'audience du jeton projeté (`serviceAccountRef.audiences`) à l'`audience` du rôle : `bao read auth/k8s-par1/role/eso-mediagenda-recette`.
</details>

<details><summary>Indice 3</summary>

Dans Cilium, un `egressDeny` l'emporte sur toute autorisation, quelle que soit la politique qui la donne. `kubectl -n external-secrets get cnp` liste aussi ce qu'Argo CD ne gère pas ; `hubble observe -n external-secrets --to-ip 10.10.20.200 --verdict DROPPED` montre les paquets refusés. Pense à calculer les plages : quelles adresses couvre un `/26` ?
</details>

**Pour aller plus loin** (facultatif) : la [référence du fournisseur Vault d'ESO](https://external-secrets.io/latest/provider/hashicorp-vault/) (cache de jetons, `version`, méthode `kubernetes`) et la page [Metrics](https://external-secrets.io/latest/api/metrics/) d'ESO ; les [politiques de refus de Cilium](https://docs.cilium.io/en/stable/security/policy/deny/). Mesure le délai entre une modification de l'audience du rôle dans un coffre d'essai et la première erreur d'un magasin qui l'utilise, avec et sans cache de jetons.
