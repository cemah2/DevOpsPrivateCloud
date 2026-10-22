# RB-261 — Demander, accorder et coder une dérogation de sécurité

> `plateforme/medisphere` — `docs/securite/durcissement/runbooks/RB-261-derogation.md` (M26-E23).
> Registre : [`exceptions.md`](../exceptions.md). S'applique à tout contrôle qui refuse ou signale :
> référentiel des hôtes (rôle `durcissement`), Pod Security, VAP, politiques Kyverno, règles Falco.

## Principe

Une dérogation est un contrôle **retiré** quelque part. Elle n'est accordée que si la correction est
impossible ou disproportionnée **à court terme**, pour le périmètre le plus étroit, avec une date de fin
et une mesure qui compense. Elle est écrite au registre **et** codée ; l'une sans l'autre est un défaut.

## 1. Avant de demander (le demandeur)

1. Lire le message de refus en entier et la règle visée (`kubectl get validatingpolicy <nom> -o yaml`,
   rapport `kubectl get policyreports -n <espace>`, règle XCCDF dans le rapport OpenSCAP).
2. Chercher la correction : une valeur du chart (ex. `initResources`), un champ du manifeste, une option
   du logiciel. **La moitié des demandes s'arrêtent ici.**
3. Si la correction existe mais prend du temps : la planifier (ticket `CHG-`) et demander une dérogation
   **temporaire** jusqu'à cette date.

## 2. Demander

Ticket `SEC-` adressé à Sophie Laurent, avec :

| Champ | Contenu |
|---|---|
| Règle | identifiant exact (politique, règle XCCDF, règle Falco) |
| Périmètre | hôtes, espace, sélecteur d'étiquettes, image, conteneur : le plus étroit |
| Justification | pourquoi la correction est impossible maintenant ; lien vers la correction planifiée |
| Risque résiduel | ce qui devient possible (une phrase concrète) |
| Compensation | ce qui détecte ou limite ce risque à la place |
| Durée | date de fin proposée (≤ 3 mois si temporaire, ≤ 12 mois si permanente) |

## 3. Valider (Sophie Laurent ; en son absence, Claire Morel)

- Refuser si une correction raisonnable existe, si le périmètre peut être réduit, ou si aucune
  compensation n'est proposée.
- Accorder par **approbation de la MR** (étape 4) : l'approbation GitLab est la signature.
- Une urgence (incident en cours) peut être accordée par téléphone : la MR est faite dans l'heure, avec
  une échéance de 7 jours au plus, puis la procédure normale reprend.

## 4. Coder (le demandeur, MR relue par l'équipe Plateforme et approuvée par la RSSI)

| Contrôle | Où | Forme |
|---|---|---|
| Référentiel des hôtes | `plateforme/ansible`, `inventories/lab/group_vars/…/durcissement.yml` ou `host_vars/<hôte>/durcissement.yml` | élément de `durcissement_exceptions` : `{regle, hotes, justification, valideur, revue}` ; le rôle l'ajoute au profil adapté d'OpenSCAP (règle « non sélectionnée », visible dans le rapport) |
| Politique Kyverno | `plateforme/politiques`, `kyverno/exceptions/<nom>.yaml` (espace `kyverno-exceptions`, seul lu par Kyverno) | `PolicyException` `policies.kyverno.io/v1` : `policyRefs` précis, `matchConditions` étroites, `images` si la politique gère `exceptions.allowedImages`, `expiresAt`, `properties` (`raison`, `ticket`, `valideur`, `revue`, `registre`), `reportResult: skip` |
| Pod Security | `plateforme/k8s/espaces/<espace>.yaml` | niveau `baseline` ou `privileged` sur l'espace dédié, jamais sur un espace d'équipe ; espace protégé par la VAP `medisphere-etiquettes-espace-protegees` |
| `hostPath` | `plateforme/k8s/admission/20-interdire-hostpath.yaml` | chemin ajouté à la clé de l'espace dans la ConfigMap `medisphere-hostpath` |
| Falco | `plateforme/politiques`, `falco/regles-medisphere.yaml` | élément d'une liste `medisphere_*` ou condition d'une macro `medisphere_*_attendu` ; jamais `enabled: false` ni réécriture de la règle |

Dans la même MR : la ligne du registre `exceptions.md` (ID suivant, toutes les colonnes). Contrôles de la
CI : `kyverno:exceptions` (échéance, périmètre, propriétés), `falco:valider` (aucune règle désactivée),
`kyverno test` (la politique refuse toujours ce que l'exception ne couvre pas : ajoute un cas de test).

## 5. Vérifier après fusion

```
admin@adm01:~$ kubectl get policyexceptions.policies.kyverno.io -n kyverno-exceptions
admin@adm01:~$ kubectl get policyreports -n <ESPACE> -o json | jq '[.items[].results[] | select(.result=="skip")] | length'
admin@adm01:~$ kubectl apply --dry-run=server -f <objet-exempté.yaml>      # accepté
admin@adm01:~$ kubectl apply --dry-run=server -f <objet-hors-périmètre.yaml>  # toujours refusé
```

Pour un hôte : relancer `conformite-analyse` (E24) et vérifier que la règle apparaît « notselected » avec
la justification dans le rapport HTML.

## 6. Échéance et revue

- 14 jours avant `expiresAt`, le pipeline planifié de `plateforme/politiques` échoue : le demandeur
  prolonge (nouvelle MR, justification relue) ou retire l'exception.
- À l'échéance, la `PolicyException` cesse de s'appliquer : si la correction n'est pas faite, les objets
  sont de nouveau refusés. ⚠️ C'est voulu, mais prévisible : ne laisse pas une échéance tomber un vendredi
  soir sur la production.
- Revue mensuelle du registre (voir `exceptions.md`).

## Retrait

MR qui supprime le code de l'exception et déplace la ligne du registre dans « Exceptions closes » avec la
date et la raison. Vérifier que la ressource exemptée est désormais conforme **avant** la fusion
(`kyverno apply` en CI, ou rapport de fond), sinon le retrait provoque un refus.
