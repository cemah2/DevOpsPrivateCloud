# RB-355 — Coffre de secours : `kms01` restauré et `bao-par2`

| | |
|---|---|
| Ticket | PLAT-3505 |
| Objets | `kms01` restauré (VMID **3501**, **10.20.20.24**, nom `kms01-par2`), `bao-par2` (1055, 10.20.20.21) |
| Durées de référence (répétition du <AAAA-MM-JJ>) | restauration de 3501 : 6 min ; neutralisation : 5 min ; descellement : 4 min ; `bao-par2` initialisé et restauré : 9 min ; contrôles : 6 min ; **total : 30 min** |
| Prérequis | enveloppe (E1, E2, E4, E9) ; stockage `pbs-local` sur `hp01` (RB-353 §4) avec la clé PBS ; set `isoles` de `inet par2` contenant 10.20.20.24 |

> ⚠️ **Jamais** de geste sur le `kms01` de PAR1 (1024, `pve01`). La copie 3501 n'a **jamais** de chemin vers PAR1 : premier démarrage carte coupée, puis carte sur `vmbr2` où `inet par2` interdit toute sortie de 10.20.20.24 (set `isoles`). Ce runbook sert à la **répétition** (§1-§6) et au **PRA** (différences au §7).

## 1. Préalables (go)

- `nft list set inet par2 isoles` sur `hp01` contient 10.20.20.24.
- **Répétition seulement** (PAR1 vivant) : `bao-par2` devient une **copie de la production** dès la restauration de l'instantané. Au démarrage, OpenBao révoque les baux expirés qu'il trouve : pour le moteur `db-mediagenda`, c'est un `DROP ROLE` exécuté… sur la base de **production** si elle est joignable. On isole donc aussi 10.20.20.21 pendant toute la répétition (la bordure ne laisse rien passer de PAR2 INFRA vers la base, c'est la seconde ceinture) :
  ```
  root@pbs01:~# nft add element inet par2 isoles '{ 10.20.20.21 }' && nft list set inet par2 isoles
  ```
  Le set revient à son contenu de référence (10.20.20.24 seul) au prochain rechargement de `nftables-par2` (§6). En PRA, PAR1 est isolé : inutile.
- Dernière sauvegarde de 1024 visible dans `pbs-local` ; son **âge** est noté (il borne la validité du jeton de seal, §5).
- Trois gardiens de parts présents (ou joignables pour saisir leur part sur `adm02` l'un après l'autre).
- Répétition seulement : écrire à PAR1, **après** le dernier instantané horaire, un secret témoin `bao kv put -mount=kv wb-essais/rpo-par2 ecrit_a="$(date +%T)"` : il doit être **absent** de la copie (mesure du RPO du coffre).

## 2. Restaurer `kms01` en 3501

```
root@pbs01:~# /root/f5/restaurer-kms01-par2.sh          # plateforme/infra outils/par2/
instantané : pbs-local:backup/vm/1024/2026-11-12T01:10:04Z
adresse 10.20.20.24 vérifiée, carte coupée.
```

Toujours carte coupée, neutraliser dans la copie ce qui chercherait à sortir (deux ceintures : `inet par2` le bloque aussi) :
```
root@pbs01:~# qm guest exec 3501 -- systemctl list-timers --all --no-pager
root@pbs01:~# qm guest exec 3501 -- systemctl disable --now <MINUTERIES-QUI-SORTENT>     # instantanés, ACME, journaux
root@pbs01:~# qm guest exec 3501 -- openssl x509 -noout -enddate -in <CERTIFICAT-TLS-D-OPENBAO>
root@pbs01:~# qm set 3501 --net0 virtio=<MAC>,bridge=vmbr2
```
Les noms d'unités et le chemin du certificat sont ceux des rôles `openbao_kms`, `alloy`, `certificats_acme` de ton dépôt : lis-les dans la copie. Le certificat doit être **encore valide** (ACME, 30 jours) au nom `kms01.par1.medisphere.internal`.

Contrôle d'isolement **avant** le descellement (la copie a gardé le nom `kms01` et ses noms de PAR1 se résolvent toujours vers PAR1 par `dns03` : seule l'adresse **10.20.20.24** désigne la copie dans les commandes, jamais `kms01.par1.medisphere.internal`, qui est la production) : depuis la copie, `qm guest exec 3501 -- curl -sS -m 5 https://s3-01.par1.medisphere.internal:8333` **échoue** ; les compteurs des règles `isoles` (`nft list chain inet par2 forward`) augmentent.

## 3. Desceller la copie

Chaque gardien saisit sa part sur `adm02` (saisie masquée, jamais dans un fichier ni dans l'historique) :
```
admin@adm02:~$ export BAO_ADDR=https://10.20.20.24:8200 BAO_TLS_SERVER_NAME=kms01.par1.medisphere.internal
admin@adm02:~$ bao operator unseal          # ×3, une part par gardien
admin@adm02:~$ bao status | grep -E 'Sealed|Seal Type'
Seal Type       shamir
Sealed          false
```

## 4. Restaurer le coffre dans `bao-par2`

```
root@pbs01:~# qm start 1055
admin@adm02:~$ export BAO_ADDR=https://bao-par2.par2.medisphere.internal:8200
admin@adm02:~$ ssh bao-par2 'sudo systemctl start openbao' && bao status        # « Initialized false »
admin@adm02:~$ bao operator init -recovery-shares=1 -recovery-threshold=1 -format=json > "$XDG_RUNTIME_DIR/par2-init.json"
admin@adm02:~/src/ansible$ WB_M25_S3_URL=https://s3-02.par2.medisphere.internal:8333 \
    WB_M25_S3_INSTANTANES_FILE=~/.config/workbook/s3-02-restauration.env \
    ../secrets/outils/instantane-vers-restauration.sh bao-par2
admin@adm02:~$ jq -r .root_token "$XDG_RUNTIME_DIR/par2-init.json" | bao login -no-print -
admin@adm02:~$ ssh bao-par2 'BAO_ADDR=https://127.0.0.1:8200 BAO_TLS_SERVER_NAME=bao-par2.par2.medisphere.internal BAO_TOKEN=<JETON-INITIAL> \
    bao operator raft snapshot restore -force /var/tmp/restauration.snap && shred -u /var/tmp/restauration.snap'
admin@adm02:~$ ssh bao-par2 'sudo systemctl restart openbao' && bao status | grep -E 'Sealed|Seal Type'
Seal Type       transit
Sealed          false
```

`instantane-vers-restauration.sh` (M25) lit l'instantané avec l'identité de lecture `restauration-par2` de `s3-02` et refuse une cible `vault0*` ou `kms01*` (garde-fou du M25). Le jeton initial cesse d'exister à la restauration (constat du M25) : ensuite, un jeton de la production encore valide, ou `generate-root` avec les **clés de récupération de la production** (elles viennent de l'instantané).

## 5. Contrôles et mesures

- Lecture d'un secret ancien (répétition : métadonnées seulement, `bao kv metadata get -mount=kv mediagenda/prod/<SECRET>`) : présent.
- `bao kv get -mount=kv wb-essais/rpo-par2` : **absent** → RPO du coffre = heure d'écriture − heure de l'instantané restauré.
- Validité du jeton de seal, **sur la copie de `kms01`** : `bao token lookup -accessor <ACCESSEUR>` → `expire_time`. S'il expire avant la fin prévisible du PRA : jeton racine régénéré sur la copie (`generate-root`, parts Shamir), nouveau jeton périodique de politique `kms-autodescellement`, posé dans la configuration de `bao-par2`, jeton racine révoqué.
- Méthode `k8s-par2` présente (`bao auth list`) : elle vient de l'instantané (déclarée à PAR1, S06).

Mesures dans `docs/pra/mesures/repetition-coffre-<AAAA-MM-JJ>.md`.

## 6. Retour en veille (fin de répétition)

```
admin@adm02:~$ ssh bao-par2 'sudo systemctl stop openbao && sudo find /var/lib/openbao -mindepth 1 -delete'
root@pbs01:~# qm shutdown 1055
root@pbs01:~# /root/f5/restaurer-kms01-par2.sh --detruire
root@pbs01:~# systemctl reload nftables-par2 && nft list set inet par2 isoles      # 10.20.20.24 seul
admin@adm02:~$ shred -u "$XDG_RUNTIME_DIR/par2-init.json"
```
`bao-par2` revient **non initialisé** : aucune copie du coffre au repos à PAR2 hors PRA. Aucun jeton n'a été créé à PAR1 : rien à révoquer côté production. Enveloppe rescellée (journal de `enveloppe.md`). Puis `lab/bin/check F5 5`.

## 7. En PRA (différences)

- L'instantané est le **dernier arrivé sur `s3-02`** (âge noté dans la main courante : RPO du coffre).
- 3501 et `bao-par2` restent en service tout le PRA ; 3501 n'est détruite qu'après le retour (RB-351).
- Après la restauration : connexion du moteur `db-mediagenda` repointée vers la base de PAR2 (Service `LoadBalancer` `mediagenda-db-par2-openbao`, 10.20.20.205, RB-356 §4) ; SecretStores de `k8s-par2` repointés vers `bao-par2` (RB-356 §4).
- Si le `kms01` de PAR1 revient pendant le PRA : rien ne change ici (même clé de transit, coffres séparés) ; c'est au retour que l'on décide quel coffre fait foi (RB-351).
