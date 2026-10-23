# Module 29 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Ce `LIBRE` s'évalue sur le résultat (`lab/bin/check 29 25` vert) et sur les démonstrations ; ce qui suit est une façon de s'organiser, pas la seule.

### M29-E25 — Mini-projet : tests et résilience de MédiSphère v1

**Solution**

*0. Le plan de travail.* `lab/bin/check 29 25` dès le début : il rejoue les checks des exercices présents (paliers 1 et 2, puis E13, E14, E19 à E22) avec `_M29_MINI_PROJET=1` (E13 ne cherche plus les objets de la série, supprimés après l'exercice), puis la livraison. La liste des rouges est la liste des tâches.

*1. Rien de provisoire.*

```
admin@adm01:~$ for t in $(kubectl api-resources --api-group=chaos-mesh.org -o name); do kubectl get "$t" -A --no-headers 2>/dev/null; done
admin@adm01:~/src/resilience$ outils/chaos-arret.sh --supprimer                  # s'il reste quelque chose
admin@adm01:~$ kubectl -n k6 get testruns,pods ; kubectl -n wb-essais get pods
root@pve01:~# pvesh get /cluster/resources --type vm --output-format json | jq '[.[] | select(.vmid >= 2290 and .vmid <= 2299)] | length'
0
admin@adm01:~$ ls ~/.local/state/workbook/pannes-actives/ | grep '^M29-' || echo "aucune panne ouverte"
```

*2. Validation partout.* Les quatre `.gitlab-ci.yml` incluent `…/ci-templates/validation@vX.Y.Z` à la **même** version (montée par MR dans chacun, ou par Renovate s'il est en place) ; aucune surcharge `allow_failure` d'un job de validation. Démonstration : une MR de `plateforme/infra` qui embarque le plan de référence (ou une modification qui le reproduit) → job conftest rouge, pipeline rouge ; une MR de `plateforme/k8s` avec un manifeste dont un champ de CRD est mal orthographié → kubeconform rouge au premier étage. Fermer les MR ensuite.

*3. Tests nocturnes verts deux nuits de suite.* Trois pipelines planifiés :

| Projet | Planification | Ce qu'il fait |
|---|---|---|
| `plateforme/ansible` | chaque nuit (M29-E10) | Testinfra sur tout le socle |
| `plateforme/resilience` | chaque nuit, `NON_REGRESSION=1` (M29-E14) | TestRun + comparaison à la référence |
| `plateforme/tofu-modules` | chaque nuit, `NETTOYAGE=1` (M29-E21) | nettoyeur Terratest en simulation (« 0 orpheline ») |

Si la non-régression est rouge pour une raison d'outillage (quota de `k6`, image), corriger l'outillage ; si c'est la performance, RB-295 (pas de mise à jour de la référence pour « faire passer »).

*4. Chaos encadré.*

```
admin@adm01:~$ kubectl get ns -o json | jq -r '.items[] | select(.metadata.annotations["chaos-mesh.org/inject"] == "enabled") | .metadata.name'
medinotif-recette
mediagenda-recette
wb-essais
admin@adm01:~$ kubectl -n chaos-mesh get deploy chaos-controller-manager -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_FILTER_NAMESPACE")].value}{"\n"}'
true
```

Démonstration de Sophie (répétée avant, **toujours** en `--dry-run=server` : l'admission est évaluée en entier, rien n'est créé). L'expérience choisie est la plus inoffensive possible (1 ms de latence, 10 s) : si une barrière était tombée et que le `--dry-run` était oublié, l'effet sur la prod resterait négligeable — on ne fait jamais cette démonstration avec un `pod-kill`.

```
admin@adm01:~$ cat > /tmp/demo-prod.yaml <<'FIN'
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata: {name: demo-prod-refusee, namespace: chaos-experiences}
spec:
  action: delay
  mode: one
  selector: {namespaces: [mediagenda-prod]}
  delay: {latency: 1ms}
  duration: 10s
FIN
admin@adm01:~$ kubectl apply --dry-run=server -f /tmp/demo-prod.yaml
The networkchaos "demo-prod-refusee" is invalid: : ValidatingAdmissionPolicy 'medisphere-chaos-espaces' with binding
'medisphere-chaos-espaces' denied request: expérience visant un espace non autorisé : mediagenda-prod      (texte exact selon la version)
admin@adm01:~$ kubectl annotate ns mediagenda-prod chaos-mesh.org/inject=enabled --dry-run=server
… denied request: annotation chaos-mesh.org/inject=enabled interdite sur l'espace mediagenda-prod …
```

Explication à donner : **deux barrières indépendantes**. (1) La politique d'admission `medisphere-chaos-espaces` (M29-E09, liaison en `Deny`) refuse à la création toute expérience dont `selector.namespaces` sort de la liste fermée, et toute annotation `chaos-mesh.org/inject=enabled` hors de cette liste, administrateurs compris. (2) Si la première tombait (liaison repassée en `Warn`, exclusion trop large), le filtre d'espaces de Chaos Mesh (`enableFilterNamespace`, valeur dans Git) écarterait tout pod d'un espace non annoté : l'objet existerait, la condition `Selected` resterait à `False` avec un événement « no pod is selected », rien ne serait injecté. Les deux sont dans Git (valeurs de Chaos Mesh, `plateforme/k8s/admission/`), relus en MR, et vérifiés par `lab/bin/check 29 09`.

*5. Journée de jeu suivie d'effets.* Chaque issue `journee-de-jeu` est fermée avec un commentaire qui pointe la preuve : MR fusionnée (alerte, `preStop`), règle chargée dans Prometheus, test ajouté ; ou reportée par une décision écrite (commentaire daté de Claire Morel) — dans ce cas l'issue reste ouverte avec l'étiquette `reportee`, que le check accepte : on livre quand c'est **décidé**, et la décision se relit dans l'issue. L'action `/pret` : soit le correctif de M29-E23 est fusionné par l'équipe de Julien, soit sa décision écrite (avec échéance) est dans l'issue et l'issue est close par la plateforme avec lien vers le ticket `DEV-3013` qui la porte désormais.

*6. Documentation.* `docs/qualite/` : `strategie-tests.md` (M29-E12, mis à jour : ce qui a été réellement livré et où — [extrait des modifications](fichiers/M29-E25/medisphere/docs/qualite/strategie-tests.extrait-E25.md) ; le check vérifie qu'elle cite k6-operator, la non-régression, les journées de jeu et le nettoyeur), ADR-0290, RB-290 à RB-297, rapport E15, journées de jeu, post-mortem INC-5623, `sous-le-capot-chaos-mesh.md`, et la note de livraison [`livraison-resilience-v1.md`](fichiers/M29-E25/medisphere/docs/qualite/livraison-resilience-v1.md).

*7. Livraison.* Pipelines de `main` verts (`plateforme/resilience`, `plateforme/politiques`, `plateforme/ci-templates`), puis :

```
admin@adm01:~/medisphere$ git tag -a resilience-v1 -m "Tests et résilience MédiSphère v1 (M29-E25, PLAT-3025)" && git push origin resilience-v1
```

**Explications**
- Le mini-projet vérifie surtout l'**hygiène** : rien qui traîne (VMs, expériences, pannes), des boucles fermées (actions de journée de jeu), et une seule vérité (même version du composant partout).
- Le contrôle sur les annotations d'espaces est **exact** (ni plus ni moins de trois espaces) : un espace de plus annoté « pour un essai » est une dette de sécurité.

**Alternatives**
- Renovate pour garder la même version du composant `validation` partout (MR automatiques) : moins d'oublis, une MR par projet à relire.
- Livrer avec une action de journée de jeu reportée et documentée (étiquette `reportee`) : acceptable si Claire le décide et l'écrit ; poser l'étiquette sans décision écrite est une fraude au contrôle, que la revue de Nadia attrape.

**Pièges classiques**
- Supprimer les issues au lieu de les fermer avec une preuve.
- Mettre à jour la référence de performance pour verdir la nuit avant la revue.
- Oublier `--annuler` après une panne réparée : le marqueur reste, le check reste rouge.
- Laisser `cible-e24`/`client-e24` dans `wb-essais`.

**En production chez MédiSphère**
La livraison `resilience-v1` devient une revue trimestrielle : versions des outils, réussite des pipelines nocturnes sur 90 jours, journées de jeu jouées et actions closes, exceptions (chaos, droits de la CI sur Thanos) revues. Les workbooks finaux (F1-F7) partent de cet état.
