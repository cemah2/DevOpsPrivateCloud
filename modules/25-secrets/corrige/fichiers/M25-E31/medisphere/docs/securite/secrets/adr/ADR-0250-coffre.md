# ADR-0250 — Le coffre de MédiSphère : OpenBao en grappe Raft, auto-descellement par `kms01`, instantanés éprouvés

| | |
|---|---|
| Statut | Acceptée |
| Date | <DATE> |
| Décideurs | Claire Morel, Sophie Laurent, Karim Benali ; rédaction : <MOI> |
| Ticket | PLAT-2631 (M25-E31) |
| Remplace / complète | complète ADR-0240 (identité), ADR-0200 (GitOps : Secrets hors Git jusqu'au M25) ; remplace la « cible Vault » des ADR-0160 et du M14 (voir ADR-0251) |

## Contexte

- Exigences : HDS et ISO 27001 (traçabilité des accès aux secrets, sauvegarde testée, séparation des pouvoirs), souveraineté (aucune dépendance à un fournisseur étranger pour une brique qui détient les clés), configuration en code relue (MR), astreinte d'une petite équipe, lab sur **un** hyperviseur (≈ 111 Go sur 128).
- Situation de départ : secrets dans Ansible Vault, variables de CI, Secrets Kubernetes créés hors Git ; incident du `.env` collé dans un ticket sans pouvoir dire qui avait lu quoi (README du module).
- Mesures et constats du module :
  1. **Bascules** (E24) : passage de témoin `<MESURE>` (souvent aucune écriture perdue), arrêt propre `<MESURE>`, arrêt brutal `<MESURE>` (≈ 8 s dans notre essai, plus le délai de keepalived).
  2. **Auto-descellement** (E25) : redémarrage simultané des trois nœuds sans intervention en `<MESURE>` ; sans `kms01`, un nœud ne démarre pas et systemd abandonne après trois essais.
  3. **Restauration** (E26) : RPO `<MESURE>`, RTO `<MESURE>` sur une grappe neuve isolée ; une copie vivante peut révoquer de vrais identifiants si elle joint PostgreSQL.
  4. **Montée de version** (E29) : 2.6.4 → 2.7.1 en roulement, une seule indisponibilité (passage de témoin) ; redescendre un nœud n'est pas un retour arrière.
  5. **Vault 2.2** (E30) : même API pour nos clients ; espaces de noms, réplication, HSM réservés à l'édition Enterprise ; un instantané d'OpenBao n'est pas relisible par Vault.

## Options et évaluation

### Produit

Critères : (a) licence et souveraineté ; (b) fonctions dont nous avons besoin sans licence commerciale (espaces de noms, contrôles à plusieurs) ; (c) compatibilité de nos clients (OpenTofu, ESO, Ansible, CI, cert-manager, Cosign) ; (d) exploitation sur site (HA, sauvegarde, montée de version) ; (e) coût ; (f) pérennité (communauté, cycle de versions) ; (g) sortie.

| Option | (a) | (b) | (c) | (d) | (e) | (f) | (g) |
|---|---|---|---|---|---|---|---|
| **OpenBao 2.7** | MPL 2.0, fondation (OpenSSF) | espaces de noms, *Control Groups* | même API (fournisseur `hashicorp/vault`, ESO alpha, hashi_vault) — essayé | Raft, instantanés à planifier soi-même | 0 € | communauté plus petite, versions mensuelles | coût croissant (divergence d'API) |
| HashiCorp Vault 2.2 communautaire | **BUSL 1.1** (IBM) : usage interne permis, clause de non-concurrence, évolution unilatérale | non (Enterprise) | natif | idem | 0 € | grande communauté, cycle IBM | — |
| Vault Enterprise | commerciale | oui + réplication, HSM, instantanés automatiques | natif | le plus complet | licence par client/nœud (`<MONTANT>` à demander) | support éditeur | verrou commercial |
| Coffre d'un nuage public (KMS + gestionnaire de secrets) | hors souveraineté (données de santé : hébergeur HDS et juridiction) | selon offre | ESO oui ; le reste à refaire | rien à exploiter | à l'usage | — | dépendance réseau et contractuelle |
| CyberArk Conjur OSS / Infisical | Conjur : LGPL ; Infisical : MIT + édition commerciale | partiel | API différentes : ESO oui, OpenTofu et CI à refaire | à vérifier | 0 € à commercial | à vérifier | — |

### Seal

| Option | Redémarrage seul | Vol d'un disque de nœud | Vol d'un instantané | Ce qu'il faut garder | Retenu |
|---|---|---|---|---|---|
| Shamir seul | non (3 dépositaires **par nœud**) | inutile au voleur | inutile | parts | non (incident E25 : nœud scellé toute une nuit) |
| **`transit` (second OpenBao `kms01`)** | oui (si `kms01` répond) | inutile sans `kms01` | inutile sans `kms01` | parts de `kms01`, sa sauvegarde PBS, clés de récupération | **oui** |
| `static` (clé AES dans un fichier ou une variable) | oui | **la clé est à côté des données** : le voleur d'une VM complète a tout | inutile sans la clé | la clé, sur chaque nœud | non |
| HSM / PKCS#11 (greffon KMS depuis 2.7) | oui | inutile | inutile | un HSM (matériel, coût, pas dans le lab) | réexamen (§ Révision) |

## Décision

1. **OpenBao 2.7**, configuré exclusivement par `plateforme/secrets` (OpenTofu) et `plateforme/ansible`.
2. **Trois nœuds Raft** (`vault01-03`) derrière la **VIP** 10.10.20.200 (keepalived suit le nœud actif) ; autopilot `cleanup_dead_servers` avec `min_quorum = 3`.
3. **Seal `transit`** servi par **`kms01`** (OpenBao mononœud, Shamir 5/3, aucune autre fonction, filtrage strict) ; les parts de la grappe deviennent des clés de récupération ; aucun jeton racine permanent (`procedure-jeton-racine.md`).
4. **Sauvegarde** : instantané Raft horaire chiffré `age` vers `s3-01` (30 jours), VMs dans PBS (`par1/secrets`, `kms01` compris), restauration sur grappe neuve **essayée chaque trimestre** (RB-252).
5. Vault reste une option de sortie documentée (E30), pas une cible.

## Conséquences

- ✅ Redémarrages sans personne ; perte d'un nœud sans coupure perceptible (passage de témoin) ou de quelques secondes (arrêt brutal) ; restauration mesurée ; disque ou instantané volés inexploitables seuls.
- ⚠️ **`kms01` est un point unique pour les démarrages** : s'il est scellé ou absent, aucun nœud ne redémarre. Action : `kms01` sauvegardé par PBS, supervisé (`OpenBaoScelle`), redémarrages coordonnés (RB-251), dépositaires joignables.
- ⚠️ **Un seul hyperviseur** : trois nœuds sur `pve01` ne protègent pas contre sa perte. Action : instantanés hors de `pve01` (`s3-01`, et copie vers PAR2 au F5), grappe de PAR2 au F5.
- ⚠️ Pas de réplication entre sites (Enterprise) : PAR2 sera une grappe indépendante alimentée par instantanés (RPO 1 h). Acceptation : Sophie Laurent.
- ⚠️ ESO classe OpenBao en *alpha* ; Cosign `hashivault://` non documenté avec OpenBao. Action : essais à chaque mineure (M25-E12, E20), repli documenté.
- ⚠️ Divergence d'API avec Vault (audit déclaratif, `generate-root` authentifié) : scripts et documentation tiers à vérifier ; retour vers Vault plus coûteux chaque année.
- ⚠️ Les sauvegardes du coffre dépendent de secrets **hors** du coffre (identité S3, `secret_id`, clé `age`) : Ansible Vault `critique` reste nécessaire (amorçage, bris de glace).

## Révision

Réexaminer si : un HSM devient disponible (seal PKCS#11) ; la direction ouvre le site PAR2 (F5) ; OpenBao n'a publié aucune corrective de sécurité pendant 6 mois ou ESO retire son fournisseur ; le coût d'une licence Enterprise devient inférieur à `<N>` jours d'exploitation par an ; plus de 5 000 baux actifs en régime normal (dimensionnement).
