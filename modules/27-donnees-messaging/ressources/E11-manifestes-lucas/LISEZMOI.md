# MR de Lucas — « rappel la veille » (DEV-2811)

Branche `lucas/rappels-veille` de `plateforme/k8s`, dossier `espaces/mediagenda-recette/rappels/`.
Message de commit : « ajout base + messagerie pour les rappels (testé sur minikube) ».

| Fichier | Contenu selon Lucas |
|---|---|
| `60-rappels-db.yaml` | une petite base PostgreSQL dédiée aux rappels, sauvegardée |
| `61-rappels-pooler.yaml` | un pooler devant cette base |
| `62-rabbitmq-rappels.yaml` | une messagerie à part « pour ne pas toucher à la vôtre », et son mot de passe |
| `63-topologie-rappels.yaml` | la file des rappels et le compte de l'application |

**Ne les applique pas** : relis-les (M27-E11). Seuls des essais à blanc (`--dry-run=server`) dans `wb-essais` sont permis.
