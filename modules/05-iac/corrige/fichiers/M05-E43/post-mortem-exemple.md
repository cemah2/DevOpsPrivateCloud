# Post-mortem — INC-3250 — Chaîne IaC indisponible : backend d'état injoignable depuis le bastion, puis état du socle supprimé

> Exemple de corrigé (M05-E43), paire **E37 variante 3** (règle de filtrage temporaire sur `gw01`) + **E42 variante 1** (objet d'état du socle supprimé). Les heures, VersionId et compteurs sont illustratifs. Ton post-mortem décrit **ta** paire, avec **tes** preuves.

| | |
|---|---|
| **Statut** | Relu |
| **Date de l'incident** | 2026-10-15 |
| **Rédacteur** | <MOI> (astreinte Plateforme) |
| **Relecteurs** | Nadia Roussel, Karim Benali |
| **Sévérité** | P2 : aucun service applicatif touché, mais plus aucun changement d'infrastructure possible depuis le bastion, et un apply du socle aurait pu tenter de recréer ou d'importer toutes les VMs permanentes |
| **Durée d'impact** | 07:50 → 09:41 (1 h 51) ; gel des apply sur `socle` de 07:58 à 09:44 |
| **Services touchés** | `plateforme/infra` (plans et apply depuis `adm01`), état OpenTofu `socle` |

## 1. Résumé

Le 15 octobre au matin, aucun plan OpenTofu ne pouvait être lancé depuis le bastion `adm01` : le backend d'état (`s3-01`, port 8333) ne répondait plus. La cause était une règle de filtrage ajoutée à chaud sur le routeur `gw01` lors d'un test de charge la veille, jamais retirée. Une fois l'accès rétabli, le plan du socle proposait d'importer et de créer toutes les VMs permanentes : l'objet d'état du socle avait été supprimé dans la nuit. Le compartiment étant versionné, l'état a été restauré à l'identique, sans perte. Aucune VM n'a été modifiée ; la démonstration de 14 h a eu lieu.

## 2. Impact

- Équipe Plateforme et équipe MédiAgenda : plus de plan ni d'apply depuis `adm01` pendant 1 h 51. Les pipelines de `plateforme/infra` (exécutés sur `runner01`, même VLAN que `s3-01`) fonctionnaient pour la partie réseau, mais le plan du socle y aurait montré le même état vide à partir de 02:13.
- Données : **aucune perte**. L'objet supprimé était masqué par un marqueur de suppression ; les 23 versions de `socle/terraform.tfstate` sont intactes (liste enregistrée à 09:12, annexe A). Aucune copie en clair de l'état n'a été produite pendant l'incident.
- Conformité : la traçabilité de qui a supprimé l'objet est **incomplète** (pas de journal d'accès S3 sur `s3-01`) : voir actions 3 et 4.

## 3. Chronologie

| Heure | Événement | Source |
|---|---|---|
| J-1 18:05 | Règle `ip saddr 10.10.10.0/24 ip daddr 10.10.20.14 tcp dport 8333 counter drop` ajoutée en tête de `inet filter forward` sur `gw01` (« isolement s3-01 pendant tests de charge ») | `nft -a list chain`, commentaire de la règle |
| 02:13 | Version courante de `socle/terraform.tfstate` remplacée par un marqueur de suppression | `list-object-versions` (`DeleteMarkers`, `LastModified`) |
| 07:50 | Julien : `tofu plan` échoue dans `envs/lab-m05` (« dial tcp 10.10.20.14:8333: i/o timeout ») | ticket INC-3250 |
| 07:58 | Gel des apply sur `socle` annoncé ; 1re communication | `#astreinte` |
| 08:04 | Matrice de tests : DNS OK (`getent`/`dig` = 10.10.20.14), TCP/8333 KO depuis `adm01`, OK depuis `runner01` → panne sur le chemin routé MGMT → INFRA | journal |
| 08:11 | Compteur de la règle `drop` de `gw01` qui monte à chaque essai : cause 1 trouvée | `nft list chain inet filter forward` |
| 08:16 | Règle retirée par le rôle `pare_feu` (pipeline de `plateforme/ansible`, rechargement complet du jeu de règles) ; `tofu state list` répond… **vide** dans `socle/` | journal |
| 08:28 | 2e communication : accès rétabli, second problème sur l'état du socle | `#astreinte` |
| 08:34 | `.terraform/terraform.tfstate` (clé `socle/terraform.tfstate`) et `tofu workspace show` (`default`) écartent l'hypothèse « OpenTofu regarde ailleurs » | journal |
| 08:41 | `list-object-versions` : marqueur de suppression courant (02:13), version précédente du J-1 17:20 (dernier apply connu, pipeline !812) | journal, annexe A |
| 09:12 | Liste des versions enregistrée, version du J-1 17:20 copiée en `600` hors dépôt ; marqueur de suppression retiré (`delete-object --version-id` sur le **marqueur**) | journal |
| 09:20 | `tofu state list` : 5 VMs du socle ; `tofu plan` : « No changes » ; `serial` identique à celui du pipeline !812 | journal |
| 09:28 | 3e communication : rétabli, gel maintenu jusqu'au contrôle complet | `#astreinte` |
| 09:41 | `lab/bin/check 05 35` à `05 42` verts | journal |
| 09:44 | Levée du gel ; fin d'incident | `#astreinte` |

## 4. Causes

### 4.1 Causes racines

1. **Filtrage oublié sur `gw01`.** Une règle `drop` vers `s3-01:8333` depuis le VLAN MGMT a été insérée à chaud pour un test, sans échéance ni ticket, et n'a pas été retirée. Preuve : la règle (commentaire « temp LM 0412… ») et son compteur qui augmente pendant un `curl https://s3-01.par1.medisphere.internal:8333/` depuis `adm01`, alors que le même `curl` depuis `runner01` (même VLAN que `s3-01`, sans passer par `gw01`) répond.
2. **Suppression de l'objet d'état courant.** À 02:13, un `DeleteObject` sans `VersionId` a été fait sur `socle/terraform.tfstate` avec des identifiants autorisés à écrire dans `tofu-state`. Preuve : marqueur de suppression `IsLatest: true` daté de 02:13, version de données précédente intacte. L'auteur n'a pas pu être déterminé (pas de journal d'accès S3).

### 4.2 Facteurs contributifs

- Le rôle `pare_feu` est la seule source des règles de `gw01`, mais une règle à chaud n'est vue que par la détection de dérive **d'Ansible**, qui ne tourne que la nuit et n'alertait que par courriel.
- L'identité `tofu-etat` a le droit de supprimer n'importe quel objet de `tofu-state` ; rien ne distingue « supprimer un verrou » de « supprimer un état ».
- La première panne **masquait** la seconde : tant que le backend était injoignable, l'état vide était invisible. Sans le gel, un apply lancé juste après la réparation réseau aurait tenté d'importer les VMs du socle et de recréer `s3-01`.

## 5. Détection et diagnostic

- Détection par un utilisateur (Julien), environ 13 h après l'ajout de la règle et 5 h 30 après la suppression de l'état. Aucune sonde ne surveillait l'accès au backend depuis `adm01`, ni la présence de l'objet d'état.
- Ce qui a accéléré : la comparaison `adm01` / `runner01` (une case de la matrice a éliminé DNS, TLS et identités) ; le versionnage, qui a rendu la restauration triviale et sûre.
- Ce qui a ralenti : l'hypothèse initiale « s3-01 est en panne » (20 min perdues sur le service SeaweedFS, sain).
- Sondes qui auraient détecté avant l'utilisateur : parcours S3 complet depuis `adm01` toutes les 5 min (M05-E37) ; contrôle quotidien « l'objet courant de chaque état est une version de données, de moins de N jours » ; plan de dérive du socle (il aurait échoué ou montré un état vide dès 02:13).

## 6. Ce qui a bien fonctionné

- Gel des apply annoncé dès le triage : aucune écriture sur l'état pendant l'incident.
- Compartiment versionné et procédure de restauration (RB-051) : aucune version perdue, restauration à l'identique.
- Matrice de tests remplie avant toute correction.

## 7. Actions

| # | Action | Type | Responsable | Échéance | Ticket |
|---|---|---|---|---|---|
| 1 | Toute règle temporaire sur `gw01` passe par le rôle `pare_feu` avec une date d'expiration (variable `expire_le`) ; un contrôle CI refuse une règle expirée | prévenir | Karim | 2026-10-31 | PLAT-6xx |
| 2 | Sonde S3 complète (résolution, TLS, lecture, écriture conditionnelle) depuis `adm01` et `runner01`, toutes les 5 min, alerte dans `#astreinte` | détecter | <MOI> | 2026-10-24 | PLAT-6xx |
| 3 | Journal d'accès S3 de `s3-01` activé et conservé 1 an (exigence HDS de traçabilité) | détecter | <MOI> | 2026-10-31 | SEC-6xx |
| 4 | Séparer les droits : suppression des objets `*.tfstate` interdite à `tofu-etat` (seuls les `*.tflock` restent supprimables), étudier un verrouillage d'objet (*object lock*) sur `tofu-state` | prévenir | Sophie | 2026-11-15 | SEC-6xx |
| 5 | Contrôle quotidien « objet courant de chaque état = version de données récente » ajouté au pipeline de dérive | détecter | <MOI> | 2026-10-24 | PLAT-6xx |
| 6 | RB-050 et RB-051 : ajouter « vérifier que la panne n'en masque pas une autre : `tofu state list` complet avant de lever le gel » | documenter | Nadia | 2026-10-20 | — |

## 8. Enseignements

- Une panne d'accès à l'état en cache toujours une autre : après avoir rétabli l'accès, on **relit** l'état avant de reprendre les apply.
- Le versionnage a transformé une perte potentielle de l'état du socle en une opération de cinq minutes ; il ne protège pas de la **suppression d'une version** (`--version-id`) : les droits doivent l'interdire.
- Une modification à chaud non tracée est une dette avec intérêts : elle finit toujours par être découverte au pire moment.

## Annexes

**A. Versions de `socle/terraform.tfstate` (extrait, VersionId tronqués)**

```
admin@adm01:~$ aws --profile s3-socle s3api list-object-versions --bucket tofu-state --prefix socle/terraform.tfstate \
  --query '{V: Versions[?Key==`socle/terraform.tfstate`].[LastModified,VersionId,Size,IsLatest], M: DeleteMarkers[?Key==`socle/terraform.tfstate`].[LastModified,VersionId,IsLatest]}'
{
    "V": [
        ["2026-10-14T17:20:41Z", "v_1b7c…", 41873, false],
        ["2026-10-14T09:02:13Z", "v_9e02…", 41851, false]
    ],
    "M": [
        ["2026-10-15T02:13:07Z", "v_4fa0…", true]
    ]
}
```

**B. Règle en cause sur `gw01` (avant retrait)**

```
root@gw01:~# nft -a list chain inet filter forward | head -n 4
table inet filter {
	chain forward {
		type filter hook forward priority filter; policy drop;
		ip saddr 10.10.10.0/24 ip daddr 10.10.20.14 tcp dport 8333 counter packets 412 bytes 24720 drop comment "temp LM 0412 : isolement s3-01 pendant tests de charge" # handle 87
```
