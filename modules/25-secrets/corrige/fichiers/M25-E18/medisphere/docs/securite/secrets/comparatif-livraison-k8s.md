# Livrer des secrets à Kubernetes : comparaison et décision

> Propriétaire : équipe Plateforme · Relu par : Karim Benali · Ticket : PLAT-2618 (M25-E18)
> **Version d'E18** : SOPS comparé à External Secrets Operator. Sealed Secrets et le pilote CSI
> s'ajoutent en M25-E19 (version complète : `fichiers/M25-E19/`).

## 1. SOPS face à External Secrets Operator

| | External Secrets Operator 2.13 (M25-E12) | SOPS 3.13 + age / transit (M25-E18) |
|---|---|---|
| Ce qui est dans Git | une **référence** (`ExternalSecret`) | le secret **chiffré** (valeurs `ENC[…]`, `apiVersion`, `kind`, `metadata` lisibles, MAC sur tout le fichier) |
| Où vit la valeur | OpenBao | Git, pour toujours (historique) |
| Qui déchiffre | OpenBao, pour le contrôleur | tout poste ou job qui a un droit sur `transit/decrypt/sops-plateforme` ou une clé age destinataire |
| Arrivée dans le cluster | native (le contrôleur crée le Secret) | il faut un outil qui déchiffre au déploiement : Argo CD ne le fait pas seul (greffon KSOPS ou helm-secrets, qui reçoit alors le droit de déchiffrer **tous** les fichiers) |
| Rotation d'une valeur | dans OpenBao, sans commit ; rafraîchissement automatique | un commit (`sops edit`), une MR, un déploiement |
| Retrait d'un destinataire | politique OpenBao | `.sops.yaml` → `sops updatekeys` → `sops rotate` → **et** rotation des valeurs : l'ancien destinataire déchiffre toujours les anciens commits |
| Secrets dynamiques | oui | non |
| Si OpenBao est perdu | dépend des instantanés (E26) | clé age de secours hors ligne : les fichiers restent lisibles |
| Revue de MR | on relit une référence | on relit un chiffré : la valeur ne se relit pas (seulement sa présence et ses métadonnées) |

## 2. Décision provisoire (confirmée en E19)

- **ESO** pour tout Secret de `k8s-par1`.
- **SOPS** : non retenu pour le cluster ; autorisé pour `formation/sops-labo` (clé `sops-plateforme`, politique `sops-plateforme`, clé age « secours » hors ligne, `SOPS_HC_VAULT_ALLOWLIST` sur les postes, contrôle `outils/verifier-chiffres.sh` en CI).
- **Ansible Vault** reste pour les fichiers d'amorçage (avant que le coffre existe).
