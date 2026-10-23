# INC-6211 — Message d'état (interne)

> `plateforme/medisphere` — `docs/securite/incidents/INC-6211/message-etat.md` (F6-S13).
> Destinataires : Claire Morel, équipes Plateforme et MédiAgenda. Rythme : RB-360 (G3 : ouverture et
> clôture ; un point intermédiaire ici car un incident de sécurité, même mineur, se communique).

---

**Objet : [INC-6211] Incident de sécurité en recette — clos, sans impact production**

Bonjour,

**Résumé.** Ce matin à 7 h 52, notre détection (Falco) a signalé une activité anormale dans un conteneur
de l'API de MédiAgenda en **recette** : un accès interactif inattendu et une tentative de connexion vers
l'extérieur. Il ne s'agissait **pas** de la production.

**Ce qui est établi.** L'activité est restée confinée à la recette, qui ne contient **aucune donnée de
patient réelle** (données fictives). Aucun accès à la production, aucune donnée sortie. Il n'y a pas de
violation de données personnelles (analyse du DPO au registre des violations).

**Ce qui a été fait.** Le conteneur a été isolé sans être détruit (preuves préservées), les preuves
collectées, la cause corrigée (des règles de sortie trop larges retirées / un accès renouvelé), les secrets
concernés renouvelés, le service rétabli. Aucune interruption visible pour les utilisateurs.

**Suites.** Un post-mortem sans recherche de coupable est rédigé ; il a déjà produit des actions
(contrôle automatique des règles réseau, accès interactif restreint en recette comme en production).

Incident **clos**. Je reste disponible pour toute question.

L'astreinte Plateforme
