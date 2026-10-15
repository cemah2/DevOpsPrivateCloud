# RB-124 — Service Quadlet en échec

| | |
|---|---|
| **Déclencheur** | un service conteneurisé géré par Quadlet ne tourne pas (alerte `ms-verif-conteneurs`, sonde applicative, signalement) |
| **Hôtes** | `ctr02` (Podman 5.4, Debian 13), `ctr03` (Podman 5.8, Rocky 10), futurs serveurs applicatifs (ADR-0120) |
| **Durée typique** | 15 à 45 min |

Se placer dans la session du compte propriétaire : `sudo machinectl shell app@` (avec `sudo -iu app`, exporter `XDG_RUNTIME_DIR=/run/user/$(id -u)`).

## 0. Le gestionnaire de l'utilisateur existe-t-il ?

```
loginctl show-user app -p Linger -p State          # en admin
systemctl status user@$(id -u app).service
```

`Linger=no` et pas de session : le gestionnaire (et tous les conteneurs) s'arrête à la déconnexion. Correctif : `sudo loginctl enable-linger app` **et** vérifier que le rôle `podman_hote` le pose.

## 1. « L'unité n'existe pas » (`Unit … could not be found`)

Le générateur a refusé le fichier, ou le fichier n'est pas au bon endroit.

```
ls ~/.config/containers/systemd/                    # (ou /etc/containers/systemd/ pour un service système)
/usr/libexec/podman/quadlet -dryrun -user           # Debian ; sur Rocky 5.6+ : podman quadlet list / print
```

Erreurs typiques : clé inconnue (`unsupported key 'X' in group 'Container'`, voir `man podman-systemd.unit`), section mal nommée, extension inconnue, référence à un `.network`/`.volume`/`.pod` absent. Corriger le fichier **dans la source** (rôle Ansible), redéposer, `systemctl --user daemon-reload`.

## 2. « Elle existe mais ne démarre pas » (`failed`, `activating` en boucle)

```
systemctl --user status <service> --no-pager
journalctl --user -u <service> -n 50 --no-pager
systemctl --user cat <service>                      # l'unité générée : ExecStart, Requires=, After=
podman ps -a --filter name=<conteneur>              # code de sortie du dernier conteneur
```

Causes typiques : dépendance (`Requires=…-network.service` introuvable), image non tirable (registre, nom court refusé par `short-name-mode = enforcing`), droits du répertoire de données (RB : M12-E36 — `podman unshare ls -ln`, `ls -Z` sur Rocky), port déjà pris, `start-limit-hit` (puis `systemctl --user reset-failed`).

## 3. « Elle tourne mais ne revient pas au démarrage »

```
systemctl --user list-dependencies --plain default.target | grep <service>
ls /run/user/$(id -u)/systemd/generator/default.target.wants/
```

Une unité générée ne s'active pas par `systemctl --user enable` (« transient or generated ») : c'est la section `[Install]` (`WantedBy=default.target`) du fichier Quadlet qui crée le lien. Preuve finale : `sudo systemctl restart user@$(id -u app).service` (ou un redémarrage de la machine), puis le service est actif sans intervention.

## Vérifier et clore

Service actif, sonde verte, survie au redémarrage du gestionnaire ; reporter toute correction dans le rôle Ansible (les fichiers Quadlet ne s'éditent jamais à la main sur l'hôte).
