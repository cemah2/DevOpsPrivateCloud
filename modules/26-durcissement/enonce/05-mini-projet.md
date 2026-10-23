# Module 26 — Palier 5 : Mini-projet

Le module a mesuré, durci, imposé, détecté, chiffré, et appris à diagnostiquer ce que le durcissement casse. Il reste à **livrer** « MédiSphère durcie v1 » comme une brique de la plateforme, et à la présenter à l'auditeur HDS : un parc mesuré chaque semaine contre un référentiel avec un score cible, des exceptions écrites et signées, une admission qui refuse ce qui n'est pas conforme en recette et en prod, une détection à l'exécution qui alerte en minutes et qui est acheminée, un chiffrement entre nœuds, des kubelets à certificats vérifiés, et une réponse à incident répétée. Sophie Laurent jouera l'auditeur HDS ; Nadia Roussel vérifiera que l'astreinte tient ; Claire Morel présentera le tout à la DSI. C'est l'étiquette `durcissement-v1` sur `plateforme/medisphere`.

---

### M26-E46 — Mini-projet : MédiSphère durcie v1  `LIBRE` `★★★`

> **Ticket PLAT-2746** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette du durcissement v1 dans deux semaines, puis l'auditeur HDS. Je veux un contrôle global sans un seul rouge, **sans rien de provisoire** (aucune panne ouverte, aucune exception périmée, aucune VM d'essai, aucun contrôle désactivé « temporairement »), et une sécurité qu'on peut prouver : mesurée, appliquée par le code, détectée, et répétée.
> Pendant la revue : **Sophie joue l'auditeur HDS** et pose ses questions (référentiel, preuve de mesure, écarts signés, réponse à incident) ; Karim relira `plateforme/politiques`, `plateforme/ansible` (rôle `durcissement`) et `plateforme/k8s`, puis tentera devant nous de déployer une charge non conforme (image hors registre, pod privilégié) qui doit être **refusée** ; Nadia lancera l'essai de détection (un shell dans un pod, la lecture d'un jeton) et attendra l'alerte ; je demanderai le score de conformité du parc et la liste des exceptions. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider le durcissement du module en une brique cohérente, pilotée par le code (Argo CD, Ansible, OpenTofu), sans dette provisoire.
- Prouver ce qui a été construit : mesure continue, admission en refus, détection acheminée, chiffrement, kubelets vérifiés, réponse à incident.
- Livrer l'état `durcissement-v1` : documentation, runbooks, exceptions signées, étiquette, et ce que le bloc G et le final F6 consommeront.

**Prérequis** : M26-E01 à M26-E45 (au minimum tous les `LAB`, `LIBRE`, `BF`, `REV`, `RED`, `Q` et le `CHRONO`).
**Durée indicative** : 8 à 12 h, plus 30 min de revue.

**Contexte technique**
- Périmètre et adresses figés (PLAN §4.12) : référentiels CIS Debian 13 v1.0.0 (niveau 1 serveur), CIS RHEL 10 (Rocky), ANSSI-BP-028 (intermédiaire), contenu ComplianceAsCode 0.1.82, OpenSCAP 1.4 ; rôle `durcissement` ; Kyverno 1.19 (espace `kyverno`, politiques CEL `policies.kyverno.io/v1`) ; Falco 0.45 (`falco`), Tetragon 1.7 (`tetragon`) ; kubelet-csr-approver 1.2.15 ; Cilium 1.20 (WireGuard, pare-feu d'hôte). Vue globale 10.10.41.60, Loki locataire `audit`, compartiments `s3-01` `conformite` et `preuves`.
- Dépôts : `plateforme/politiques` (Kyverno, Falco, Tetragon, valeurs des chartes, tests, CI), `plateforme/k8s` (étiquettes PSA des espaces, pare-feu d'hôte Cilium, valeurs des releases Cilium et kubelet), `plateforme/ansible` (rôle `durcissement`, conformité continue), `plateforme/gitops` (Applications `kyverno`, `politiques`, `falco`, `tetragon`, `kubelet-csr-approver`), `plateforme/medisphere` (documentation `docs/securite/durcissement/`).
- Le contrôle global `lab/bin/check 26 46` rejoue les contrôles clés des paliers 1 à 4 (s'ils sont présents), puis vérifie la couverture, l'admission, la détection, le chiffrement, la conformité, la documentation et l'étiquette. Il prend quelques minutes.

**État livré `durcissement-v1`** — ce que le bloc G et le final F6 trouveront. Rien de ce tableau ne doit manquer, rien ne doit porter un autre nom.

| Élément | État attendu à la livraison |
|---|---|
| Mesure du parc | Analyse OpenSCAP hebdomadaire (minuterie systemd) sur tout le socle et les nœuds, rapports ARF+HTML vers `s3-01/conformite`, métriques `medisphere_conformite_*` à node_exporter (collecteur *textfile*), alertes `ConformiteDegradee` et `ConformiteAnalyseAbsente` ; Lynis hebdomadaire en complément ; score **≥ 85 % CIS niveau 1 hors exceptions** |
| Durcissement des hôtes | Rôle `durcissement` appliqué par vagues à tout le socle (SSH, PAM, sudo, noyau, systemd, auditd, AIDE, AppArmor/SELinux), exceptions déclarées dans `durcissement_exceptions` (jamais `ip_forward=0` sur `gw01`/`gw02` ni les nœuds K8s, exception documentée) ; auditd → Loki `audit` (`service="auditd"`) ; VMs d'essai `durci-deb`/`durci-rocky` détruites |
| Admission | PSA `restricted` sur tous les espaces applicatifs et de plateforme (exceptions écrites : `supervision-noeuds`, `falco`, `tetragon`, `kube-system`, `cilium`) ; Kyverno en refus sur recette/prod (`exiger-signature-medisphere` avec la clé de transit `cosign-medisphere` du M25, `docs/registre/cosign.pub`, `registres-autorises`, `exiger-digest`, `exiger-limites`, `exiger-etiquettes`, `interdire-identifiants-url`), mutation `seccomp-par-defaut` et génération `networkpolicy-par-defaut` actives, exceptions datées dans `kyverno-exceptions` seulement, tests `kyverno test` en CI ; `ValidatingAdmissionPolicy`/`MutatingAdmissionPolicy` natives en complément ; aucune politique en `Ignore` ni exemption d'administrateurs |
| Détection | Falco (tous les nœuds, règles MédiSphère, falcosidekick → Alertmanager `:9093` et Loki `audit`), Tetragon (observation + application sûre), acheminement vérifié ; RB-260 |
| Réseau | Chiffrement WireGuard du trafic des pods **et** des nœuds (`nodeEncryption`, `cilium encrypt status` cohérent), pare-feu d'hôte Cilium (`hote-commun`, `hote-plan-controle`, `hote-travailleurs` de `plateforme/k8s/composants/cilium/hote/`, tous les nœuds étiquetés `medisphere.internal/pare-feu-hote: "oui"`, VRRP préservé par `enable-extended-ip-protocols`) appliqué nœud par nœud (RB-264) ; politique de quarantaine `quarantaine` posée à l'avance |
| Kubelets | `serverTLSBootstrap: true`, `seccompDefault: true`, kubelet-csr-approver (`providerRegex` qui couvre exactement les nœuds de `k8s-par1`, préfixe 10.10.40.0/24), aucune CSR en attente ; metrics-server et Prometheus vérifient les certificats des kubelets |
| Réponse à incident | RB-262 (réponse à incident conteneur) répété (M26-E42), compartiment `preuves`, quarantaine éprouvée |
| Documentation | `docs/securite/durcissement/` : `modele-menace.md`, `referentiels.md`, `exceptions.md` (registre signé), `adr/ADR-0260-durcissement-et-detection.md`, runbooks RB-260 à RB-265, `analyses/sous-le-capot-ebpf-lsm-admission.md`, `durcissement-v1.md` (fiche de livraison, limites assumées, ce que consomment le bloc G et F6) ; matrice des flux à jour (conformité vers `s3-01`, pare-feu d'hôte) ; étiquette **`durcissement-v1`** sur `plateforme/medisphere` |

**Travail demandé**
1. **Rien de provisoire.** Aucune panne `M26` ouverte, aucune exception périmée (toutes datées, avec valideur et prochaine revue), aucune VM d'essai (`durci-deb` 2261, `durci-rocky` 2262) restante, aucun contrôle désactivé (`setenforce 0`, webhook `Ignore`, politique en `Audit` censée être en `Deny`), aucun objet posé à la main dans un espace géré par Argo CD.
2. **Le parc est mesuré.** Chaque VM et chaque nœud a un score récent (< 8 jours), les métriques remontent, les alertes de conformité sont chargées ; le score CIS niveau 1 est ≥ 85 % hors exceptions, et chaque écart restant est au registre.
3. **L'admission refuse.** Une charge non conforme (image hors registre, pod privilégié, image non signée en prod) est **refusée** ; les politiques en refus sont testées en CI ; aucune exemption d'administrateur ni espace applicatif en `privileged`.
4. **La détection fonctionne et est acheminée.** L'essai de Nadia (shell + lecture d'un jeton) remonte dans Loki (`audit`) et en alerte en minutes ; Falco couvre tous les nœuds ; Tetragon observe.
5. **Le réseau est durci.** WireGuard chiffre aussi le trafic des nœuds (pas seulement celui des pods), le pare-feu d'hôte est appliqué et documenté (RB-264), la quarantaine est prête.
6. **Les kubelets sont vérifiés.** Aucune CSR en attente, certificats de service valides, Prometheus et metrics-server sans `--kubelet-insecure-tls`.
7. **La réponse à incident est répétée.** RB-262 est écrit et a été exécuté (M26-E42) ; les preuves vont dans `s3-01/preuves`.
8. **Documentation et exceptions.** `durcissement-v1.md` (architecture, couverture, **limites assumées**, ce que consomment le bloc G et F6), ADR-0260, `exceptions.md` signé, runbooks RB-260 à RB-265, matrice des flux.
9. **Livraison.** Tout est fusionné, les pipelines de `main` sont verts, l'étiquette **`durcissement-v1`** est posée sur `plateforme/medisphere`.
10. **La revue.** 10 minutes de présentation (architecture, choix et compromis, limites), les démonstrations de Karim (charge refusée) et de Nadia (détection), le score de conformité pour Claire, les questions d'auditeur de Sophie.

**Contraintes**
- Tout passe par le code (Argo CD, Ansible, OpenTofu) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Aucun secret dans un dépôt, une politique, une annotation ou la documentation : des **emplacements**, jamais des valeurs.
- Jamais `kube-system`, `kyverno`, `argocd`, `cilium` dans une politique de refus ; jamais `ip_forward=0` sur les passerelles ni les nœuds K8s ; aucun contrôle désactivé comme « correctif ».
- Les choix qui s'écartent d'un exercice du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 26 46` est entièrement vert.
- [ ] Démonstration de Karim : une charge non conforme (image hors registre, pod privilégié) est refusée à l'admission, avec un message lisible ; une charge conforme passe.
- [ ] Démonstration de Nadia : un shell ouvert dans un pod et la lecture d'un jeton remontent une alerte Falco dans `astreinte@`/Loki en quelques minutes.
- [ ] Le score de conformité (parc et cluster) est lu dans la vue globale et dans un rapport de `s3-01/conformite`, cohérent avec l'énoncé, les écarts expliqués et au registre.
- [ ] `durcissement-v1.md` dit ce qui n'est **pas** couvert (un hyperviseur, un site, pas de SIEM central, détection par courriel seulement…) et ce que le bloc G et F6 traiteront ; la revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 26 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 26 46` dès le début : la liste des points rouges est ton plan de travail. `lab/bin/check 26 43` rejoue d'un coup les contrôles du palier 4, qui sont aussi des contrôles de santé de la sécurité.
</details>

<details><summary>Indice 2</summary>

Répète les démonstrations **avant** de nettoyer. Pour la charge refusée de Karim : prépare deux manifestes (un conforme, un non conforme) et montre le `--dry-run=server` ou l'échec d'une MR. Pour la détection de Nadia : un pod d'essai dans `wb-essais`, un `kubectl exec`, et le suivi dans Loki (`{service="falco"}`, locataire `audit`).
</details>

<details><summary>Indice 3</summary>

« Ce qui n'est pas couvert » : un seul hyperviseur et une seule salle ; pas de SIEM ni de corrélation centralisée (les journaux `audit` sont dans Loki, pas dans un SIEM) ; la détection alerte par courriel ; pas de gVisor/Kata (isolation par le noyau partagé) ; FreeIPA sans réplica. Écris pour chacun le risque, ce qui le détecte (ou rien), et le module ou le final qui le traite (F6 sécurité/conformité, bloc G).
</details>

**Pour aller plus loin** (facultatif) : un tableau de bord Grafana « posture de sécurité » (score de conformité par référentiel et par vague, alertes Falco par équipe, exceptions qui approchent de leur revue) ; une revue mensuelle automatisée des exceptions (script qui alerte sur celles dont la date de revue est dépassée), publiée dans `docs/securite/durcissement/revues/`.
