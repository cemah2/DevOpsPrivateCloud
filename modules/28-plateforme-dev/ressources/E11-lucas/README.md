# Mot de Lucas

Salut ! J'ai voulu finir l'autoscaling avant les congés de Karim, en partant des exemples les plus vus en ligne (j'ai juste adapté les noms) :

- `hpa-vpa-mediagenda.yaml` : HPA **et** VPA sur MédiAgenda en production, comme ça on a les deux (le nombre de pods ET les bonnes ressources, automatiquement). J'ai mis un minimum à 1 pour économiser la nuit, et 20 au maximum pour être tranquille.
- `scaledobject-medinotif-prod.yaml` : MédiNotif de prod passe à zéro quand la file est vide (on économise encore) ; j'ai mis AMQP, c'est le protocole de RabbitMQ, et le compte du worker, il a déjà les droits sur la file. J'interroge toutes les secondes pour être réactif.
- `triggerauthentication-medinotif-prod.yaml` : le Secret est dans le même fichier, c'est plus simple pour Argo CD (pas besoin d'aller dans OpenBao).
- `tenant-partenaire.yaml` : le locataire du prestataire de téléconsultation qui arrive. Pour qu'il ne nous embête pas avec des tickets, je lui ai donné tous les droits sur ses espaces ; je l'ai mis à mon nom en attendant qu'on sache qui c'est chez eux.

Je n'ai rien appliqué. Tu me dis ?
Lucas
