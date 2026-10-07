# Grille d'auto-évaluation — ADR-0050 (M05-E30)

Note ton ADR **avant** de lire l'exemple. 2 points par ligne : 0 absent, 1 partiel, 2 complet et justifié.

| # | Critère | Points |
|---|---|---|
| 1 | Le titre énonce la décision (et pas seulement le sujet) | /2 |
| 2 | Le contexte se comprend sans connaître le lab : ce qui est arrivé à MinIO (dates), ce dont l'état a besoin, ce qui viendra (MédiDoc, Velero) | /2 |
| 3 | Les facteurs sont explicites et **hiérarchisés** : les critères éliminatoires (écritures conditionnelles, versionnage) sont séparés des critères pondérés | /2 |
| 4 | Au moins cinq options réelles, dont Garage, Ceph RGW et le fork de MinIO ; l'option « sans S3 » (état géré par GitLab) est envisagée | /2 |
| 5 | Chaque cellule du tableau dit **comment** elle a été vérifiée (test, documentation datée, non vérifié) | /2 |
| 6 | Au moins deux candidats autres que SeaweedFS ont été **testés** (script E12 sur une VM jetable), ou l'impossibilité est argumentée précisément | /2 |
| 7 | La décision s'appuie sur les critères vérifiés, pas sur la popularité ou un comparatif en ligne | /2 |
| 8 | La gouvernance est analysée (qui peut changer la licence, combien de mainteneurs, CLA) : la leçon MinIO est tirée | /2 |
| 9 | Les conditions de révision sont **observables** (dates, délais, événements), avec une revue de routine datée | /2 |
| 10 | La stratégie de sortie dit ce qui est portable et ce qui ne l'est pas, avec une procédure et une durée | /2 |
| 11 | La stratégie de sortie est (au moins en partie) **testée** ou un test est planifié avec une date ou un module | /2 |
| 12 | Les conséquences négatives (point unique de défaillance, dépendance aux mainteneurs, fonctions S3 non couvertes) sont nommées avec leur traitement | /2 |

**Total : /24.** En dessous de 16, reprends les lignes à 0 avant de comparer à l'exemple.

## Décisions également valables

L'exemple garde SeaweedFS. D'autres décisions sont acceptables si elles respectent les critères
éliminatoires **vérifiés** et assument leurs conséquences :

- **Fork communautaire de MinIO** : acceptable seulement si l'ADR traite la gouvernance (une
  petite équipe tierce, des correctifs de sécurité rétroportés ou non), la licence AGPL et la
  question « que fait-on si ce fork s'arrête à son tour ».
- **Ceph RGW dès maintenant** : défendable pour un socle qui aura de toute façon Ceph, mais le
  coût (plusieurs Go de RAM, trois nœuds pour la redondance, compétences) doit être chiffré, et la
  décision doit dire quoi faire d'ici au module 08.
- **État OpenTofu géré par GitLab + SeaweedFS pour le reste** : acceptable si l'ADR traite le
  couplage forge-état (forge en panne = plus de plan ni d'apply, y compris pour réparer la forge
  si elle était un jour gérée par OpenTofu) et la sauvegarde des états dans celle de GitLab.

Une décision qui retient Garage pour l'état n'est **pas** valable : sans versionnage ni écritures
conditionnelles vérifiées, le verrou et le retour arrière de l'état disparaissent.
