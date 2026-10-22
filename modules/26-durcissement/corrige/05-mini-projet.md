# Module 26 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M26-E46 — Mini-projet : MédiSphère durcie v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, les points de contrôle de chaque étape, la préparation des démonstrations et la **grille de revue** avec laquelle Claire, Karim, Sophie (auditeur HDS), Nadia et Julien évaluent la livraison. Le fichier nouveau est le modèle de fiche de livraison [`fichiers/M26-E46/medisphere/docs/securite/durcissement/durcissement-v1.md`](fichiers/M26-E46/medisphere/docs/securite/durcissement/durcissement-v1.md).

**Solution**

*Plan de travail recommandé* (on prouve d'abord, on nettoie ensuite, on documente à la fin)

1. **État des lieux** (1 h) : `lab/bin/check 26 46`, puis `lab/bin/check 26 43` (tout le palier 4) et les contrôles détaillés rouges. Inventaire des restes : `ls ~/.local/state/workbook/pannes-actives/` ; exceptions périmées (`kubectl get policyexceptions -A`, registre `exceptions.md`) ; politiques en `Audit` qui devraient être en `Deny` ; espaces en `privileged` (`kubectl get ns -L pod-security.kubernetes.io/enforce`) ; VMs d'essai 2261/2262 (`pvesh get /cluster/resources --type vm`).
2. **Démonstrations, répétition** (2 h) : voir plus bas. Faites **avant** le nettoyage.
3. **Conformité** (2 h) : `medisphere_conformite_score` par référentiel et par hôte dans la vue globale ; pour chaque hôte sous la cible, lire le rapport HTML de `s3-01/conformite` et corriger par le rôle `durcissement` (ou inscrire une exception justifiée). Score CIS niveau 1 ≥ 85 % hors exceptions.
4. **Admission** (2 h) : chaque politique de refus en `Deny` sur recette/prod, testée (`kyverno test`) ; PSA `restricted` partout sauf exceptions écrites ; aucune exemption de groupe ; une charge non conforme refusée (`--dry-run=server`).
5. **Détection** (1 h) : Falco couvre tous les nœuds ; un essai (shell + lecture de jeton) remonte dans Loki (`audit`) et en alerte ; Tetragon observe.
6. **Réseau et kubelets** (1 h) : `cilium encrypt status` cohérent ; pare-feu d'hôte appliqué et documenté (RB-264) ; aucune CSR de kubelet en attente ; Prometheus sans `--kubelet-insecure-tls`.
7. **Nettoyage** (1 h) : pannes closes (`--annuler`), exceptions périmées retirées, aucun contrôle désactivé, VMs d'essai détruites, objets manuels retirés et reportés dans le code.
8. **Documentation et livraison** (2 à 3 h) : `durcissement-v1.md`, ADR-0260, `exceptions.md`, runbooks RB-260 à RB-265, matrice des flux ; MR, pipelines verts, étiquette `durcissement-v1`.

*Démonstration de Karim — une charge non conforme refusée* (répétée avant la revue)

| Étape | Action | Attendu |
|---|---|---|
| 1 | `kubectl apply --dry-run=server -f` d'un pod avec `image: docker.io/library/nginx` dans `mediagenda-recette` | refus `registres-autorises` : image hors `registry.par1.medisphere.internal/*` |
| 2 | idem avec `securityContext.privileged: true` | refus PSA `restricted` (+ politique) |
| 3 | idem avec une image `medisphere/*` **non signée** en `mediagenda-prod` | refus `exiger-signature-medisphere` |
| 4 | une charge **conforme** (image signée, digest, non-root, limites) | admise |
| 5 | question à préparer | que se passe-t-il si le contrôleur Kyverno est en panne ? (VAP natives tiennent ; webhooks selon `failurePolicy`) |

*Démonstration de Nadia — la détection fonctionne* : ouvre un shell dans un pod de `wb-essais` (`kubectl exec`), lis `/etc/shadow` ; suis dans Loki (`{service="falco"}`, locataire `audit`) et dans `astreinte@` (Mailpit) l'alerte Falco en quelques minutes. Montre qu'elle contient le pod, le processus et la règle.

*Score pour Claire* : `medisphere_conformite_score` par référentiel (vue globale), rapport HTML de `s3-01/conformite`, et la liste des exceptions (`exceptions.md`). Les écarts restants sont justifiés (ex. `ip_forward=1` sur passerelles/nœuds K8s, `/tmp` exécutable pour un outil) avec compensation et date de revue.

*Réponse à incident (Sophie, auditeur)* : rejoue M26-E42 ou montre RB-262 et le journal `INC-5342` : détection, quarantaine, collecte dans `s3-01/preuves`, éradication (y compris persistance), rétablissement.

*Grille de revue*

| Relecteur | Points | Attendu |
|---|---|---|
| Sophie (auditeur HDS) | référentiel, preuve de mesure, écarts signés, réponse à incident | CIS + ANSSI mesurés chaque semaine, rapports dans `s3-01/conformite`, `exceptions.md` signé et daté, RB-262 exécuté, preuves dans `s3-01/preuves` |
| Karim | `plateforme/politiques`, `plateforme/ansible`, `plateforme/k8s` | politiques CEL `policies.kyverno.io/v1` (jamais `ClusterPolicy`), tests `kyverno test` en CI, rôle `durcissement` par famille et par vagues, versions épinglées, charge non conforme refusée |
| Nadia | astreinte, détection, runbooks | le durcissement ne casse pas l'astreinte (M26-E38 à E41 compris), Falco couvre tous les nœuds et crie à l'essai, RB-260 à RB-265 utilisables à 4 h |
| Julien | équipes, livraison | ses charges conformes passent (sondes, limites, non-root), les refus ont un message lisible, la recette déploie normalement |
| Claire | ensemble | score de conformité ≥ cible, limites assumées et écrites, feuille de route vers F6 (SIEM, corrélation, conformité continue) et le bloc G |

**Explications**

Le contrôle global ne remplace pas les contrôles détaillés : il vérifie l'**état de livraison** (couverture, admission, détection, chiffrement, conformité, documentation, étiquette) et rejoue ce qui casse le plus souvent en silence. Les démonstrations portent sur ce qu'aucun contrôle automatique ne prouve : qu'une charge non conforme est **réellement** refusée avec un message clair, et qu'un humain est **réellement** prévenu d'une activité suspecte, en minutes.

**Alternatives**

Démonstration de la charge refusée par une vraie MR (plutôt qu'un `--dry-run`) : plus réaliste, mais plus lente ; le `--dry-run=server` prouve l'admission sans bruit. Rapport de conformité exporté depuis `s3-01` plutôt que lu dans Grafana : les deux doivent concorder.

**Pièges classiques**
- Faire les démonstrations après le nettoyage, puis découvrir qu'une politique a été retirée.
- Laisser une politique en `Audit` qui devait passer en `Deny`, ou un espace en `privileged`.
- Laisser une exception périmée, ou une exemption d'administrateur « temporaire ».
- Désactiver un contrôle la veille de l'audit « pour que tout soit vert ».
- Poser l'étiquette `durcissement-v1` avant que les pipelines de `main` soient verts.

**En production chez MédiSphère**

La livraison `durcissement-v1` devient la référence des changements suivants ; l'essai de la chaîne de détection devient hebdomadaire et automatique ; la revue des exceptions entre dans le rituel mensuel ; le final F6 reprend cette brique pour la conformité et la réponse à incident à l'échelle (SIEM, corrélation), et le bloc G la consomme (chaque nouvelle brique arrive avec ses politiques, sa détection et son runbook, sinon elle n'est pas en production).
