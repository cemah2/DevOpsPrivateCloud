# Module 27 — Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M27-E25 — Mini-projet : les données et la messagerie de MédiSphère v1

**Solution**

Une démarche possible, en sept lots, chacun clos par sa preuve (le contrôle global les reprend dans le même ordre : `lab/bin/check 27 25`).

1. **Inventaire de ce qui doit être vrai** : reprendre chaque contrainte du ticket et noter où est la preuve (tableau en tête de `docs/donnees/README.md`). C'est aussi la liste de contrôle de la fenêtre CHG-2825.
2. **Production** (fenêtre annoncée, sauvegarde CNPG `Completed` d'abord : `kubectl cnpg backup mediagenda-db -n mediagenda-prod`, puis `kubectl -n mediagenda-prod get backups` ) :
   - MédiAgenda de prod passe par `mediagenda-db-pooler-rw` (M27-E02, à refaire si ce n'est pas fait) ; preuve : `cnpg_pgbouncer_pools_cl_active{namespace="mediagenda-prod"}` > 0 et plus aucune connexion de l'API directement sur le primaire (`pg_stat_activity` : les connexions de l'API viennent des pods du *pooler*) ;
   - `MEDIAGENDA_AMQP_URL` en prod (M27-E08), MédiNotif de prod à deux réplicas ;
   - démonstration ([exemple](fichiers/M27-E25/medisphere/docs/donnees/demonstration.md)) : praticien fictif réservé à la plateforme, destinataire factice, création puis annulation, chaque étape horodatée avec sa preuve.
3. **Identités et sécurité** : relire les `Permission` de la topologie (MédiAgenda : `configure ^$`, `read ^$`, `write ^notifications$` ; MédiNotif : `configure ^$`, `write ^$`, `read ^notifications$`) ; aucune image Bitnami (`kubectl get pods -A -o jsonpath='{..image}' | tr ' ' '\n' | grep -i bitnami` vide) ; compte par défaut de RabbitMQ décrit comme bris de glace dans le README ; le compte `sauvegarde-definitions` (`administrator`, sans permission de vhost) noté comme écart justifié.
4. **Exploitation** : M27-E14 et E15 verts (`lab/bin/check 27 14`, `27 15`) ; aucune alerte de ces familles active (`ALERTS{alertstate="firing"}` dans Thanos Query) ; export des définitions de la nuit présent dans `s3://messagerie-definitions/` ; réplica de secours à jour ; alertes ajoutées en M27-E23 chargées.
5. **Essais retirés** : `kafka-essai` (espace, Application, PVC), VMs Patroni (Proxmox, NetBox, DNS) et leur flux de bordure (MR de `plateforme/ansible`), bancs et grappes de `wb-essais`, témoin `wb-pannes/trafic-recette` (s'il ne sert plus au M28), aucune panne marquée active (`ls ~/.local/state/workbook/pannes-actives/`).
6. **Documentation** : [`docs/donnees/README.md`](fichiers/M27-E25/medisphere/docs/donnees/README.md) (schéma, composants et versions, où vit chaque définition et qui l'applique, identités, flux, index des runbooks, passation au M28) ; ADR-0270 ; comparatifs ; dimensionnement ; décision RabbitMQ 4.4 ; RB-270 à RB-279 ; démonstration.
7. **Livraison** : MR fusionnées, pipelines verts, puis :
   ```
   admin@adm01:~/src/medisphere$ git tag -a donnees-v1 -m "Données et messagerie v1 (M27-E25, PLAT-2825)" && git push origin donnees-v1
   admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check 27 25
   ```

**Explications**

Le mini-projet ne demande presque rien de neuf : il demande que tout ce qui a été fait **tienne ensemble** et soit **vérifiable par quelqu'un d'autre**. Les deux pièges du module s'y retrouvent : ce qui a été fait à la main (bases de recette et de secours appliquées depuis `plateforme/k8s`, gestes de pannes) doit être soit dans Git, soit écrit comme exception ; et la fiabilité des notifications reste **au moins une fois avec un trou connu** (publication après validation, sans *outbox*) : le dire dans le README plutôt que le taire.

**Alternatives**

- Faire la démonstration en production par la sonde synthétique du M29 plutôt qu'à la main : meilleure à terme, mais elle n'existe pas encore.
- Livrer l'*outbox* dans ce mini-projet : possible si Julien est d'accord, mais c'est une évolution de l'application (MR dans `mediagenda/api`, tests, migration `expand`), à ne pas mélanger avec la livraison de la plateforme.

**Pièges classiques**
- Poser l'étiquette avant que le contrôle global soit vert.
- Une démonstration en production avec un vrai patient ou un vrai numéro de téléphone.
- Oublier le flux de bordure de l'essai Patroni (il reste ouvert vers des adresses qui seront réattribuées).
- Mettre MédiNotif de prod à zéro « pour tester KEDA plus tard ».

**En production chez MédiSphère**

Revue de livraison avec Claire (README lu par quelqu'un d'extérieur au module), puis passage au M28 : KEDA lira la profondeur de `notifications` avec un compte `monitoring` dédié, et les seuils viendront de `dimensionnement.md`.
</content>
</invoke>
<invoke name="Bash">
<parameter name="command">curl -sS --max-time 20 https://api.github.com/repos/nats-io/nats-server/releases?per_page=5 2>/dev/null | python3 -c "import json,sys
try:
  print([(r['tag_name'], r['published_at'][:10]) for r in json.load(sys.stdin)])
except Exception as e: print('err',e)"; curl -sSL --max-time 20 https://raw.githubusercontent.com/nats-io/nats-server/main/LICENSE | head -3