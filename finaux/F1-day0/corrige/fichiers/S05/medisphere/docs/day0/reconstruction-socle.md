# Reconstruction de `lb02` et `dns02` depuis le code (F1-S05, CHG-3105)

> Modèle (corrigé F1-S05) : les durées sont des EXEMPLES de forme ; remplace-les par tes mesures.

## 1. Durées mesurées

| Étape | `lb02` | `dns02` |
|---|---|---|
| Préalables (P1 à P5) | 10 min | 15 min (état HA de Kea) |
| MR 1 + plan relu + apply (destruction) | 12 min | 12 min |
| MR 2 + plan relu + apply (création, VM démarrée) | 9 min | 9 min |
| Premier SSH (cloud-init terminé) | 2 min | 2 min |
| Playbooks (base, rôle, annuaire, supervision, journaux, durcissement) | 24 min | 31 min (zones transférées, Kea resynchronisé) |
| Conformité (analyse lancée) | 6 min | 6 min |
| Vérifications | 8 min | 10 min |
| **Total** | **1 h 11** | **1 h 25** |

## 2. Gestes manuels (dette)

| Geste | Prévu ? | Temps perdu | Ticket | Correction proposée |
|---|---|---|---|---|
| `qm set --startup order=3` / `order=2` | oui (D1) | 2 min | PLAT-31<NN> | rôle personnalisé avec `Sys.Modify` limité, ou ordre de démarrage porté par un rôle Ansible `pve_*` |
| `ipa host-disable` | oui (D2) | 1 min | — | gardé : décision humaine |
| `ssh-keygen -R` sur `adm01`, `runner01` | oui (D3) | 3 min | PLAT-31<NN> | `known_hosts` réduit à la ligne `@cert-authority` (rôle `ssh_ca_client`) |
| analyse de conformité à la main | oui (D4) | 6 min | PLAT-31<NN> | `conformite-mesure.yml` dans le playbook d'accueil d'une VM neuve |
| exemple d'imprévu : transfert d'une zone relancé à la main (`pdns_control retrieve`) | **non** | 8 min | PLAT-31<NN> | comprendre pourquoi le NOTIFY n'a pas suffi, corriger le rôle `powerdns_auth` |

## 3. Écarts au plan

- <écart>, <cause>, <décision>.

## 4. Ce que ça dit pour la phase 3

- Une VM du socle revient en ≈ 1 h 15 dont 45 min de configuration : pour six nœuds, la configuration Ansible en parallèle (pas de `serial: 1` sur la préparation des nœuds) est la condition pour tenir l'estimation de la carte (§1, étape 13-14).
