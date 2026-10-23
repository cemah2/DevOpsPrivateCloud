# Module 27 — Mini-projet

### M27-E25 — Mini-projet : les données et la messagerie de MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-2825** — *De : Claire Morel, en copie Nadia Roussel, Julien Petit et Sophie Laurent*
> On clôt le chantier « données et messagerie » avant de passer à l'autoscaling et au portail. Je veux pouvoir dire au comité : tout est dans Git, la production passe par le *pooler*, les notifications partent en production de bout en bout, l'astreinte a ses alertes et ses runbooks, le plan de reprise a été joué, et les essais (Kafka, Patroni) sont partis. Livre-moi l'étiquette **`donnees-v1`** sur `plateforme/medisphere` quand c'est vrai, pas avant.

**Objectifs pédagogiques**
- Intégrer les briques du module dans l'infrastructure MédiSphère comme un service livré : reproductible, supervisé, documenté, réversible.
- Faire la preuve de bout en bout, en production, sans rien casser.
- Préparer les modules suivants : KEDA (M28) dimensionnera MédiNotif sur la profondeur de la file `notifications`, et les journées de jeu du M29 viseront la recette.

**Prérequis** : tout le module (`lab/bin/check 27 02` à `27 24` verts, ou leurs écarts expliqués).
**Durée indicative** : 4 à 6 h.

**Contraintes**
- **Tout est dans Git** et appliqué par Argo CD ou par le code d'infrastructure ; aucune ressource de données ou de messagerie créée à la main ne subsiste (les seules exceptions sont celles déjà écrites : bases de recette et de secours appliquées depuis `plateforme/k8s`, à documenter comme telles).
- **Production** : MédiAgenda de production se connecte à sa base **par le *pooler*** ; MédiAgenda de production **publie** les demandes de notification et MédiNotif de production les **consomme** ; aucune file de production ne grossit et son rebut est vide ou expliqué. Toute intervention en production passe par une fenêtre annoncée (`CHG-2825`) et commence par une sauvegarde CNPG vérifiée.
- **Sécurité** : chaque application a ses propres identités (base, AMQP, Valkey) dans OpenBao, lues par ESO, avec le moindre privilège (MédiAgenda ne fait que publier, MédiNotif ne fait que consommer) ; TLS partout dans le cluster ; le compte par défaut de RabbitMQ est un bris de glace documenté, inutilisé au quotidien ; aucune image ni aucun chart Bitnami.
- **Exploitation** : supervision collectée et alertes chargées pour PostgreSQL, le *pooler*, RabbitMQ, Valkey et le réplica de secours, **aucune alerte de ces familles active** au moment de la livraison ; tableau `m27-donnees` à jour ; export nocturne des définitions RabbitMQ réussi ; réplica de secours à jour.
- **Essais retirés** : rien ne reste de Kafka (`kafka-essai`), de Patroni (VMs 2271-2273) ni des bancs et grappes jetables de `wb-essais` ; aucune panne du module n'est encore active.
- **Documentation** dans `docs/donnees/` de `plateforme/medisphere` : un `README.md` d'architecture (schéma, composants et versions, flux, identités, où vit chaque définition, qui fait quoi), l'ADR-0270, les comparatifs (messagerie, Patroni/CNPG), le dimensionnement, la décision RabbitMQ 4.4, les runbooks RB-270 à RB-279 indexés depuis le README, et une **démonstration** datée (`demonstration.md`) : un rendez-vous de production de test créé puis annulé, sa notification suivie de la publication à l'envoi (horodatages, identifiants), avec ce que tu as fait pour que ce rendez-vous de test ne gêne personne.
- Les nouveaux flux réseau sont dans `group_vars/role_routeur/pare_feu.yml` et les matrices de flux ; ceux de l'essai Patroni en sont retirés.

**Livrables**
1. Les MR fusionnées dans `plateforme/donnees`, `plateforme/k8s`, `plateforme/gitops`, `plateforme/observabilite`, `mediagenda/deploiement`, `medinotif/deploiement` et `plateforme/infra`.
2. La documentation de `docs/donnees/` et l'étiquette **`donnees-v1`** sur `plateforme/medisphere`.
3. Une note de passation (une page, dans `docs/donnees/README.md` ou à part) pour le module suivant : la métrique de file que KEDA lira, l'utilisateur et la permission qu'il lui faudra (lecture de la file, étiquette `monitoring`), et ce qu'il ne faut pas faire (mettre MédiNotif de production à zéro).

**Critères de réussite**
- [ ] Le contrôle global passe : `lab/bin/check 27 25`.
- [ ] La démonstration de bout en bout en production est datée et vérifiable (identifiants, horodatages, journaux).
- [ ] Un relecteur qui ne connaît pas le module comprend, depuis `docs/donnees/README.md`, comment tout tient et où intervenir.

**Vérification** : `lab/bin/check 27 25` (contrôle global, 3 à 6 minutes).

<details><summary>Indice 1</summary>

Commence par la liste de ce qui doit être vrai, pas par ce qu'il reste à faire : chaque contrainte ci-dessus est une phrase que quelqu'un peut vérifier. Pour chacune, écris où se trouve la preuve (une commande, un tableau, un fichier dans Git), puis fais en sorte que la preuve existe.
</details>

<details><summary>Indice 2</summary>

Pour la démonstration en production, pense à ce que le rendez-vous de test laisse derrière lui : une ligne en base, un message, un journal de MédiNotif. Un praticien fictif réservé à la plateforme, un destinataire factice qui n'envoie rien de réel, et une annulation juste après font l'affaire ; écris-le.
</details>

**Pour aller plus loin** : prépare l'*outbox* de l'ADR-0270 sous forme de proposition chiffrée (table, relais, tests, effort) à présenter à Julien : c'est la prochaine marche de fiabilité des notifications.
</content>
</invoke>
