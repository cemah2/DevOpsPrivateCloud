### M25-E35 — Panne : le coffre est scellé après un redémarrage  `BF` `★★`

> **Ticket INC-5235** — *De : Nadia Roussel*
> Cette nuit, Lucas a fait la maintenance des nœuds du coffre : mises à jour, un redémarrage par nœud, « deux ou trois réglages ». Depuis, le coffre répond mal : mon contrôle du matin (`sys/health` sur `vault01`, `vault02`, `vault03` et sur `openbao.par1.medisphere.internal:8200`) rate une requête sur trois, et une alerte parle d'un nœud scellé. Lucas redémarre le nœud actif cet après-midi pour le noyau : est-ce que tout va tomber ? *(Le détail s'affiche à l'injection ; selon le cas, le contrôle est encore vert et Lucas signale seulement un « réglage d'essai » oublié sur un des nœuds.)*

**Objectifs pédagogiques**
- Mener un diagnostic méthodique sur une grappe : observer depuis les clients, mesurer depuis le nœud, comparer avec Git, sans rien toucher avant d'avoir une cause.
- Distinguer quatre états qui se ressemblent vus de loin : nœud **scellé**, processus **arrêté**, nœud **injoignable** (écoute, filtrage) et nœud **refusé** (TLS), et savoir lequel une alerte désigne vraiment.
- Lire la configuration **effective** d'un service (`systemctl cat`, `systemctl show`, `/proc/<PID>/limits`, `ss`, certificat présenté) et pas seulement les fichiers qu'on croit en place.
- Évaluer le risque d'une bascule vers un nœud malade et corriger à la racine, par le rôle Ansible, un nœud en attente à la fois.

**Prérequis** : M25-E24 (grappe, VIP, `chk_openbao_actif`), M25-E25 (seal `transit`), M25-E27 (supervision, `OpenBaoScelle`), M25-E28 (gabarit final du rôle `openbao`, surcharge `medisphere.conf`), M04-E29 (job `derive`) ; `lab/bin/check 25 28` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Contexte technique**
- Grappe de trois nœuds (`vault01-03`) : **un** actif (`sys/health` = 200), deux en attente (429). La VIP `openbao.par1.medisphere.internal` (10.10.20.200) ne suit que l'actif. Le script `chk_openbao_actif` de keepalived interroge **le nœud local**, sous son nom, par la boucle locale (`--resolve <nœud>:8200:127.0.0.1`).
- Raft et le transfert de requêtes passent par le port de grappe **8201** (`cluster_address`). Les clients, la supervision et keepalived passent par l'API **8200** (`address` de l'écouteur).
- Référence : `/etc/openbao/openbao.hcl` (gabarit `openbao.hcl.j2`), `/etc/systemd/system/openbao.service.d/medisphere.conf` (`LimitNOFILE=65536`, durcissement), certificat ACME `/etc/openbao/tls/{cert,key}.pem` émis pour le nœud **et** le nom du service, relu par SIGHUP (`systemctl reload openbao`). Tout vient de `plateforme/ansible` (`playbooks/coffre.yml`).
- Prometheus (`job="openbao"`) interroge chaque nœud **par son nom** ; `OpenBaoScelle` (M25-E27) sonne sur `vault_core_unsealed == 0` **ou** `up == 0`.
- La panne touche **un seul nœud en attente**, ni les données ni le seal. Elle ne passe pas par OpenBao : c'est le système du nœud qui a changé.

> ⚠️ **Attention** : tant que tu n'as pas de cause, **pas** de `bao operator step-down`, **pas** de redémarrage du nœud actif : un nœud malade peut prendre la main, et alors c'est tout le coffre qui tombe. Ne lance jamais `bao operator unseal` ni de procédure de clés de récupération sur un nœud que tu n'as pas **vu** scellé depuis le nœud lui-même. Ne touche ni à `kms01`, ni à `/var/lib/openbao`. Ne copie jamais une clé privée d'un nœud à l'autre pour « réparer vite ».

**Injection** : `lab/bin/break 25 35` (3 variantes).

**Travail demandé**
1. **Observe depuis les clients.** Relève, pour chaque nœud et pour la VIP, le code HTTP **et** le message d'erreur de `curl` (pas seulement « ça marche / ça ne marche pas »). Quelle alerte a sonné, sur quelle série ? Formule tes hypothèses (scellé, arrêté, injoignable, refusé, limité en ressources, sorti de Raft) et dis lesquelles ces premiers relevés écartent.
2. **Mesure depuis le nœud.** Sur le nœud suspect : état du service et journal depuis la maintenance, `seal-status` **par la boucle locale**, adresses d'écoute, certificat présenté, limites effectives du processus. Vu de la grappe : `bao operator raft list-peers` et l'état d'autopilot. Le nœud est-il scellé ?
3. **Compare avec Git.** `playbooks/coffre.yml --limit <NŒUD> --check --diff` : qu'est-ce qu'Ansible voit, et qu'est-ce qu'il **ne voit pas** ? Complète la comparaison par la configuration effective (`systemctl cat`, comparaison avec un nœud sain). Énonce la cause en une phrase.
4. **Réponds à Nadia** : la requête sur trois, d'où vient-elle ? Et si l'actif redémarre cet après-midi avant ta réparation, que se passe-t-il, selon la cause trouvée ? Justifie à partir de `chk_openbao_actif`.
5. **Corrige à la racine**, sur le seul nœud touché (en attente), par le rôle Ansible ; si le rôle ne sait pas corriger cet écart, corrige à la main **et** corrige le rôle. Vérifie depuis les clients.
6. **Préviens** : fais en sorte que le job `derive` voie ce type d'écart, que l'alerte dise ce qu'elle a vraiment constaté, et propose la règle de revue qui aurait arrêté cette modification. Tiens ton journal de diagnostic.

**Critères de réussite**
- [ ] Les trois nœuds répondent **par leur nom**, TLS vérifié : un actif, deux en attente, tous descellés ; la VIP répond.
- [ ] Sur chaque nœud : l'API écoute sur le réseau, aucune surcharge systemd hors `medisphere.conf`, limite de descripteurs du processus ≥ 65536, certificat présenté émis pour le nœud et pour `openbao.par1.medisphere.internal`.
- [ ] Le rôle `openbao` retire les surcharges systemd non déclarées ; une alerte « nœud injoignable » distincte de `OpenBaoScelle` est chargée dans Prometheus.
- [ ] Ton journal de diagnostic (un fichier dont le nom contient `INC-5235`, dans `docs/securite/secrets/journal/` de `plateforme/medisphere`) cite les relevés, la cause et la réponse à la question de Nadia.

**Vérification** : `lab/bin/check 25 35`

<details><summary>Indice 1</summary>

`curl -w '%{http_code} %{errormsg}\n'` dit **pourquoi** une requête échoue : `Connection refused` (rien n'écoute à cette adresse), délai dépassé (filtrage, processus figé), erreur de certificat (`SSL: no alternative certificate subject name matches`), ou un vrai code HTTP (503 : scellé). Un nœud scellé **répond** : il dit lui-même qu'il est scellé.
</details>

<details><summary>Indice 2</summary>

Depuis le nœud, interroge-le comme le fait keepalived : `curl --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt --resolve <NŒUD>.par1.medisphere.internal:8200:127.0.0.1 https://<NŒUD>.par1.medisphere.internal:8200/v1/sys/seal-status`. S'il répond là et pas depuis `adm01`, le problème est entre les deux : écoute, filtrage ou certificat.
</details>

<details><summary>Indice 3</summary>

`systemctl cat openbao` affiche l'unité **et toutes ses surcharges**, dans l'ordre où systemd les applique : la dernière valeur d'un réglage l'emporte. Compare `systemctl show -p LimitNOFILE openbao` et la ligne `Max open files` de `/proc/<PID>/limits` sur le nœud suspect et sur un nœud sain. Ansible ne signale que les fichiers qu'il gère.
</details>

**Pour aller plus loin** (facultatif) : sur un `bao server -dev` jetable de ton poste, lancé par `systemd-run --user -p LimitNOFILE=<N>`, cherche la plus petite limite qui laisse démarrer le serveur, puis ouvre des connexions en parallèle et note le message du journal. Documentation : [écouteur TCP](https://openbao.org/docs/configuration/listener/tcp/), [`sys/health`](https://openbao.org/api-docs/system/health/), [rechargement par SIGHUP](https://openbao.org/docs/commands/server/), [`systemd.unit` : surcharges](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html).
