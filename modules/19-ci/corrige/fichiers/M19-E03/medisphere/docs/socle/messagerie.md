# Messagerie du lab — `mon01` et Mailpit

> Ticket PLAT-2003 / SEC-2003 (M19-E03). Hôte permanent du socle v4. Rôle Ansible `mailpit`,
> playbook `playbooks/supervision.yml`, VM `socle/mon01.tf` de `plateforme/infra`.

## Ce que c'est

`mon01` (VMID 1014, 10.10.20.19, VLAN 20) porte **Mailpit 1.31.6**, un serveur SMTP **de lab** :
il **reçoit** tous les courriels qu'on lui envoie et les présente dans une interface web et une
API. Il n'en **livre aucun** : aucun relais (`MP_SMTP_RELAY_*`) ni renvoi (`MP_SMTP_FORWARD_*`)
n'est configuré, et la bordure n'ouvre aucun flux SMTP vers l'extérieur. Au M21, `mon01` porte
aussi la supervision « témoin » (Prometheus et Alertmanager hors cluster).

| Élément | Valeur |
|---|---|
| Nom de service | `smtp.par1.medisphere.internal` (CNAME vers `mon01`) : les clients n'utilisent que lui |
| SMTP | port **25**, **STARTTLS obligatoire** (une session sans STARTTLS est refusée), sans authentification |
| Interface et API | `https://mon01.par1.medisphere.internal:8025/`, authentification basique, réseau d'administration et VPN seulement |
| Certificat | ACME de step-ca (`cert-renewer@mailpit`), noms `mon01…` et `smtp…`, renouvelé aux deux tiers de sa vie, Mailpit redémarré |
| Rétention | 5000 messages et 30 jours au plus ; base SQLite `/var/lib/mailpit/mailpit.db`, **non précieuse** |
| Sauvegarde | la VM (travail PBS du socle) ; la base de Mailpit n'a pas de sauvegarde applicative |

## Adresses du lab

Domaine fictif `@medisphere.internal`, sans enregistrement MX : seuls les clients configurés pour
envoyer à `smtp.par1.medisphere.internal` l'utilisent.

| Adresse | Usage |
|---|---|
| `plateforme@medisphere.internal` | équipe Plateforme (réponse des courriels de GitLab, alertes non urgentes au M21) |
| `astreinte@medisphere.internal` | astreinte (alertes urgentes, M21) |
| `securite@medisphere.internal` | RSSI (Sophie Laurent) : alertes de sécurité |
| `<prénom.nom>@medisphere.internal` | personnes (comptes GitLab des personnages, `<MOI>`) |
| `gitlab@medisphere.internal` | expéditeur des courriels de GitLab |

## Qui envoie

| Client | Depuis | Configuration |
|---|---|---|
| GitLab | `git01` (même VLAN : filtré par le pare-feu local de `mon01`) | fragment `smtp` de `host_vars/git01/gitlab_hote.yml`, STARTTLS **vérifié** (`smtp_openssl_verify_mode = 'peer'`, racine MédiSphère) |
| Argo CD (M20), Alertmanager (M21) | pods de `k8s-par1` (adresse du nœud, règle de la bordure `K8S_CP`/`K8S_TRAV` → `mon01:25`) | à venir |
| Essais | `adm01` (MGMT) | `swaks` |

## Comptes de l'interface

| Compte | Usage | Mot de passe |
|---|---|---|
| `<MOI>` | consultation | Vault `critique` (`host_vars/mon01/vault.yml`) |
| `wb-checks` | vérifications du workbook (`lab/bin/check`, fonction `mailpit_api`) | Vault `critique` et `~/.config/workbook/mailpit-checks.env` (600) |

**Mailpit n'a pas de rôles** : tout compte authentifié a tous les droits de l'API, y compris
supprimer des messages (`DELETE /api/v1/messages`). Le compte `wb-checks` n'est donc « en
lecture » que par l'usage qu'on en fait. Compensations : mot de passe propre (pas celui de
`<MOI>`), fichier 600 sur `adm01` seulement, interface joignable depuis MGMT et le VPN seulement,
données de lab sans valeur (aucune donnée de santé réelle ne transite par le lab). Un vrai
service de messagerie de production n'aurait pas cette faiblesse.

## Ce que Mailpit ne fait pas

- livrer un courriel à l'extérieur (c'est voulu) ;
- garder les messages longtemps (5000 / 30 jours) : ce n'est pas un journal d'audit ;
- authentifier les expéditeurs : n'importe quel client autorisé par le pare-feu peut envoyer
  « de la part de » n'importe qui. Le contrôle est **réseau** (pare-feu local et bordure).

## Tester

```
admin@adm01:~$ swaks --server smtp.par1.medisphere.internal:25 --tls \
                 --tls-ca-path /usr/local/share/ca-certificates/medisphere-root-ca.crt \
                 --from plateforme@medisphere.internal --to astreinte@medisphere.internal \
                 --header "Subject: test messagerie"
root@git01:~# gitlab-rails runner "Notify.test_email('plateforme@medisphere.internal', 'Test GitLab', 'Corps').deliver_now"
admin@adm01:~$ . ~/.config/workbook/mailpit-checks.env && \
  curl -sf -K <(printf 'user = "%s:%s"\n' "$MAILPIT_USER" "$MAILPIT_PASSWORD") \
  'https://mon01.par1.medisphere.internal:8025/api/v1/search?query=subject:test' | jq '.messages_count'
```

Panne fréquente : GitLab ne remet rien et `production.log` montre `SSL_connect … certificate verify
failed` : la racine n'est pas dans `/etc/gitlab/trusted-certs/` ou le certificat de Mailpit ne
porte pas `smtp.par1.medisphere.internal`. Les envois de GitLab passent par Sidekiq : un envoi
raté est réessayé (file `mailers`).
