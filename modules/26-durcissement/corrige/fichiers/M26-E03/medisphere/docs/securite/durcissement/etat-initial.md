# État initial du durcissement du socle

> SEC-2703 — mesure du <AAAA-MM-JJ> par `<MOI>`, avant toute modification (module 26, palier 1). Ligne de départ du rapport à l'auditeur HDS ; la même mesure est refaite à la fin du module (M26-E46). Document interne, diffusion restreinte.

## Outils et méthode

| Outil | Version | Mode |
|---|---|---|
| Lynis | 3.1.7 (archive CISOfy, SHA-256 vérifiée) | `lynis audit system --quick --no-colors`, en root, depuis l'archive dépliée dans `/root/`, supprimée après ; aucune installation |
| ssh-audit | 3.9.0 (`uv tool`, sur `adm01`) | lecture libre, puis politique intégrée `Hardened Debian 13 (version 1)` ou `Hardened Rocky Linux 10 (version 1)` |

Rapports bruts : `/var/log/lynis-report.dat` de chaque VM (non versionnés ici : ils contiennent des noms de comptes et des versions de paquets).

## Résultats

Les valeurs ci-dessous sont **celles de ton lab** : remplace les `<…>`. Les ordres de grandeur observés sur une Debian 13 issue de l'image dorée sont donnés à titre indicatif.

| VM | Système | Indice Lynis | Avertissements | Suggestions | ssh-audit (politique) |
|---|---|---|---|---|---|
| `gw01` | Debian 13 | `<IDX>` (≈ 60-65) | `<N>` | `<N>` | `<PASS/FAIL>` : `<écarts>` |
| `git01` | Debian 13 | `<IDX>` | `<N>` | `<N>` | `<PASS/FAIL>` |
| `mon01` | Debian 13 | `<IDX>` | `<N>` | `<N>` | `<PASS/FAIL>` |
| `ipa01` | Rocky 10 | `<IDX>` | `<N>` | `<N>` | `<PASS/FAIL>` |

## Trois constatations

1. **Le durcissement des VMs est hétérogène.** Les indices s'étalent selon le module qui a créé la VM et ce qu'il a durci (bordure en M00/M07, `ipa01` en M24 sur une autre famille d'OS). Rien ne garantit qu'un réglage posé à la main sur une VM existe sur les autres. → rôle `durcissement` unique, par famille (E10), appliqué par vagues (E14), mesuré chaque semaine (E24).
2. **SSH : bon socle, détails à aligner.** Les clés d'hôte et les certificats du M06 sont modernes (Ed25519) ; ssh-audit signale en revanche des algorithmes laissés par défaut par OpenSSH (par exemple des échanges de clés ou des MAC que la politique « Hardened » retire, et l'absence de limitation du débit de connexion). Aucun n'est une faille exploitable aujourd'hui, mais ils écartent la politique de référence. → E11 (configuration SSH commune, `ssh-audit` vert).
3. **Pas de traçabilité locale.** Lynis relève l'absence d'auditd (pas de journal des appels sensibles), d'intégrité des fichiers (pas d'AIDE) et de comptabilité des processus ; c'est ce que l'auditeur demandera pour « qui a fait quoi sur le serveur ». → E12 (auditd, AIDE, envoi vers Loki `audit`).

## Ce qui n'est pas mesuré ici

Lynis donne une tendance, pas une conformité à un référentiel (voir `referentiels.md`, E04) ; ssh-audit ne juge que la cryptographie et le débit, pas l'authentification (SSO, certificats, `AllowGroups`). Le cluster est mesuré à part (`mesure-k8s-par1.md`, E05).
