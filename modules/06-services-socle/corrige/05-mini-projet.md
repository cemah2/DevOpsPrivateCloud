# Module 06 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M06-E46 — Mini-projet : socle MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, les points de contrôle de chaque étape, une démonstration de référence de la chaîne « ajouter un hôte », et la **grille de revue** avec laquelle Claire, Karim, Sophie, Nadia et Julien évaluent la livraison. Les fichiers de référence sont ceux des exercices du module (`corrige/fichiers/M06-EXX/`) ; rien de nouveau n'est à écrire qui ne soit déjà dans un exercice, à l'exception de `docs/socle/services.md` et de la mise à jour des documents existants.

**Solution**

*Plan de travail recommandé* (dans cet ordre : chaque étape s'appuie sur la précédente)

1. **État des lieux** (1 h) : `lab/bin/check 06 46`, puis les contrôles détaillés rouges. Dresser la liste de ce qui reste provisoire : `dpkg -l dnsmasq` sur `dns01`, `grep -rl 'CA provisoire' /etc/ssl/certs` et `ls /usr/local/share/ca-certificates/` sur chaque hôte, certificats en service et leur émetteur :
   ```
   admin@adm01:~$ for s in git01:443 nbx01:443 s3-01:8333 ca01:443; do h=${s%:*}; printf '%-12s ' "$s"; \
       openssl s_client -connect "$s" -servername "$h.par1.medisphere.internal" </dev/null 2>/dev/null \
       | openssl x509 -noout -issuer -enddate -nameopt utf8,sep_comma_plus | tr '\n' ' '; echo; done
   ```
2. **Fermer le provisoire** (2 à 3 h) : bascule des derniers certificats sur ACME ; période de recouvrement (une semaine en production, une journée en lab) pendant laquelle les deux racines sont installées ; puis retrait de la racine provisoire par le rôle `ca_lab` (variable de liste des racines à **absenter**, `state: absent` + `update-ca-certificates --fresh`), redémarrage des services Go/Java qui lisent le magasin au démarrage (GitLab Runner) ; archivage chiffré de `~/pki-provisoire` (ou destruction : le choix et sa justification vont dans la politique de certification). Retrait de dnsmasq de `dns01` : `site.yml` n'applique plus le rôle `dnsmasq`, une tâche du rôle `powerdns_recursor` (ou un playbook ponctuel commité) désinstalle le paquet (`state: absent`, `purge: true`) **après** vérification que rien n'écoute plus sur 53 hors du récurseur. Le relais de `gw01`, lui, utilise dnsmasq et reste.
3. **Aligner le code** (2 à 4 h) : `site.yml --check --diff` sur tout le socle à `changed=0` ; `tofu plan` de l'état `socle` à « No changes » ; synchronisation Proxmox → NetBox en `--dry-run` sans écart ; comparaison des deux inventaires (groupes `socle`, `role_*`) en CI.
4. **Exploitation** (2 à 3 h) : sauvegardes applicatives planifiées vers PBS (`par1/ca01`, `par1/nbx01`, `par1/dns01`, `par1/dns02`), test de restauration chronométré sur une VM 2060-2068 (par exemple la base de NetBox : restauration de `pg_dump` sur une VM `nbx-restau`, NetBox démarre et `/api/status/` répond ; mesurer chaque étape) ; sondes `ms-verif-services` planifiées et branchées sur `ms-alerte@`.
5. **Démonstration** (2 h, à répéter) : voir ci-dessous.
6. **Documentation et livraison** (3 à 4 h) : `services.md`, RB-060 relu, inventaire exporté, matrice des flux, registre des secrets ; MR, pipelines verts, étiquette `socle-v1`.

*Démonstration de référence — ajouter un hôte au socle (RB-060)*

| Étape | Action (code ou NetBox seulement) | Preuve |
|---|---|---|
| 1 | NetBox : créer la VM `demo01` (cluster `pve01`, site PAR1, étiquettes `env-m06`, rôle) ; l'adresse est allouée par OpenTofu dans le préfixe (`netbox_available_ip_address`) | objet NetBox avec IP primaire |
| 2 | MR sur `plateforme/infra` : une instance du module `vm-debian` (VMID 2060, VNet `vinfra` ou `vsandbox`) ; `plan` dans la MR ; fusion ; `apply` protégé | VM 2060 démarrée, enregistrement `netbox_ip_address` |
| 3 | DNS : enregistrements A et PTR créés à côté de la VM (provider `mmianl/powerdns`, M06-E14) ou par la génération depuis NetBox (E15) | `dig demo01.par1.medisphere.internal` et inverse, validés (`ad`) |
| 4 | Ansible : la VM apparaît dans l'inventaire NetBox (étiquettes) ; le pipeline applique `base`, `ssh_durci`, `ssh_ca_hote` | `ssh demo01` sans question sur l'empreinte (certificat d'hôte reconnu par `@cert-authority`) |
| 5 | Certificat TLS : le rôle du service demande un certificat ACME et installe le renouvellement | `openssl s_client` : émetteur « MédiSphère Intermediate CA », 30 jours au plus |
| 6 | Retrait : suppression de l'instance dans le code (`tofu apply`) ; NetBox passe l'objet à `decommissioning` puis le supprime ; le DNS suit ; le certificat expire (30 jours) ou est révoqué (révocation passive : renouvellement refusé) — choix justifié | plus de VM, plus de nom, plus d'objet actif |

Un chronométrage typique en lab : 15 à 25 minutes de bout en bout, dont l'essentiel en attente de pipeline. Chaque intervention manuelle pendant la répétition est un ticket sur RB-060 ou sur le code.

*Contenu attendu de `docs/socle/services.md`*

Modèle : [`fichiers/M06-E46/services.md`](fichiers/M06-E46/services.md).

- Carte des services et de leurs dépendances (texte ou Mermaid) : réseau → DNS (récurseurs, autoritaires) → temps (NTS) → PKI (step-ca, ACME, CA SSH) → NetBox → consommateurs (OpenTofu, Ansible, CI, sauvegardes).
- Pour chaque service : hôtes, ports, données et leur sauvegarde, secrets (emplacement), supervision, procédure de redémarrage et de restauration, **ce qui se passe quand il tombe** (qui est touché, combien de temps on tient : cache DNS, certificats encore valides, baux en cours).
- Points uniques de défaillance restants (par exemple : `ca01` seul — les certificats en cours restent valides, mais plus aucune émission ni renouvellement ; `nbx01` seul ; `gw01` seul) et ce que le bloc B ou les modules 24-25 traiteront.

**Explications**

Ce mini-projet vérifie surtout l'**intégration** : chaque service pris seul a été construit dans un exercice ; leur valeur vient de la chaîne qui les relie. Le contrôle global revérifie aussi les acquis des modules 01 à 05, parce que le module 06 les a modifiés en profondeur (certificats de GitLab et de `s3-01`, inventaire, DNS des pipelines) : une régression silencieuse de la forge ou de l'état OpenTofu est le risque principal d'un module qui touche aux fondations.

**Alternatives**
- Garder dnsmasq comme cache local sur chaque hôte (devant les deux résolveurs) : accélère et lisse les pannes, mais ajoute un étage à diagnostiquer ; `systemd-resolved` joue ce rôle sur certaines distributions.
- NetBox comme source **unique** (OpenTofu lit NetBox pour créer les VMs) plutôt que NetBox alimenté par OpenTofu : plus pur, mais demande des contrôles stricts dans NetBox (droits, validations) ; c'est le débat de l'ADR-0060.

**Pièges classiques**
- Retirer la racine provisoire avant d'avoir basculé **tous** les certificats (oubli fréquent : `s3-01`, ou un client Python qui lit son propre magasin).
- Désinstaller dnsmasq de `dns01` avec `apt purge` sans vérifier qu'aucun service n'y était encore attaché (`ss -lunp`), ou le retirer de `gw01` par erreur (le relais DHCP en dépend).
- Une démonstration qui marche « à la main » mais pas par le pipeline.
- Un registre des secrets qui liste des valeurs, ou des secrets oubliés (clé d'API PowerDNS, mot de passe du provisioner JWK, clés TSIG `axfr-par1` et `ddns-kea`).

**En production chez MédiSphère**
La recette ajoute un exercice de reprise : arrêt de `dns01` pendant 30 minutes (les clients basculent sur `dns02`, Kea passe en *partner-down*), arrêt de `ca01` pendant une journée (aucune émission, rien ne casse tant que les certificats ont plus de 10 jours) ; les résultats complètent `services.md`.

**Grille de revue (auto-évaluation si tu travailles seul)**

| Relecteur | Critère | Attendu |
|---|---|---|
| Claire | Contrôle global | `lab/bin/check 06 46` entièrement vert, sans contrôle ignoré |
| Claire | Provisoire retiré | dnsmasq absent de `dns01`, CA provisoire absente de tous les magasins, aucun certificat en service émis par elle |
| Claire | Points uniques de défaillance | listés dans `services.md` avec leur impact et l'échéance de traitement |
| Karim | Code | `site.yml --check` à `changed=0`, `tofu plan` « No changes », rôles testés par Molecule, MR relues |
| Karim | Source de vérité | ADR-0060 appliqué (qui fait foi pour quoi), inventaires comparés en CI, synchronisation sans écart |
| Sophie | PKI | racine hors ligne (clé absente de `ca01`), politique de certification relue, durées (30 jours TLS, 16 h SSH), révocation décrite |
| Sophie | Secrets et flux | registre complet (emplacements, portée, propriétaire, échéance), matrice des flux en code et dans la documentation, aucun secret dans les dépôts |
| Sophie | Accès de secours | compte `secours` et clé de bris de glace documentés, usage tracé |
| Nadia | Restauration | test chronométré d'un service socle avec RTO et RPO, procédure jouable par un tiers |
| Nadia | Supervision | sondes planifiées, alertes reçues (dont expiration < 10 jours), runbooks du palier 4 |
| Julien | Démonstration | hôte ajouté puis retiré avec RB-060 seul, sans intervention manuelle |
| Tous | Présentation | 10 minutes : avant/après, risques, ce que le bloc B consommera |

Une livraison est acceptée quand tous les critères sont remplis ; un critère manquant est noté comme action (responsable, échéance) dans le compte rendu de recette, jamais passé sous silence.
