# MédiSphère durcie v1 — fiche de livraison

> État `durcissement-v1` (étiquette sur `plateforme/medisphere`). Ce que le bloc G et le final F6
> trouvent, et ce qu'ils devront traiter.

## Ce qui est couvert

- **Mesure** : OpenSCAP (CIS Debian 13 v1.0.0, CIS RHEL 10, ANSSI-BP-028 intermédiaire) + Lynis,
  hebdomadaire, rapports dans `s3-01/conformite`, métriques `medisphere_conformite_*`, alertes.
  Score ≥ 85 % CIS niveau 1 hors exceptions.
- **Hôtes** : rôle `durcissement` par famille (Debian/Rocky), appliqué par vagues (SSH, PAM, sudo,
  noyau, systemd, auditd, AIDE, AppArmor/SELinux) ; exceptions déclarées et signées (`exceptions.md`).
- **Admission** : PSA `restricted` partout sauf exceptions écrites ; Kyverno (CEL `policies.kyverno.io/v1`)
  en refus sur recette/prod (signature, registres, digest, limites, étiquettes, identifiants URL,
  seccomp, NetworkPolicy par défaut) ; VAP/MAP natives en complément ; tests `kyverno test` en CI.
- **Détection** : Falco (tous les nœuds) + Tetragon, acheminés vers Alertmanager et Loki (`audit`).
- **Réseau** : chiffrement WireGuard du trafic des pods (M15) et des nœuds (`nodeEncryption`, E26) ; pare-feu d'hôte Cilium (RB-264) ; quarantaine prête.
- **Kubelets** : certificats de service vérifiés, approbation par kubelet-csr-approver.
- **Réponse à incident** : RB-262 répété ; preuves dans `s3-01/preuves`.

## Ce qui n'est PAS couvert (limites assumées)

| Limite | Risque | Ce qui le détecte | Traité par |
|---|---|---|---|
| Un seul hyperviseur, une seule salle | perte du site | supervision (M21) | F5 (PRA) |
| Pas de SIEM ni de corrélation centralisée | détection cloisonnée (Loki `audit`, pas de corrélation multi-sources) | règles Loki ruler (M22) | F6 (conformité/sécurité) |
| Alertes de sécurité par courriel | pas d'escalade automatique | essai hebdomadaire | F6 |
| Isolation par noyau partagé (pas de gVisor/Kata) | évasion sur faille noyau | Falco, PSA, seccomp | bloc G (si besoin) |
| FreeIPA sans réplica permanent (M24) | indisponibilité de l'annuaire | sauvegarde + PBS | F5 |
| `ContainerCheckpoint` / verrouillage d'objet S3 à vérifier | collecte de preuves incomplète | — | F6 |

## Ce que le bloc G et F6 consommeront

- La clé publique Cosign et `exiger-signature-medisphere` (chaîne d'approvisionnement).
- Le journal `audit` (Loki) et les détections Falco/Tetragon (corrélation, SIEM en F6).
- Les référentiels, le registre d'exceptions et les rapports de conformité (dossier d'audit HDS).
- La quarantaine et RB-262 (réponse à incident à l'échelle).
