# Sous le capot : exécution d'un module et module maison `systemd_dropin`

> Analyse de référence (M04-E44), rédigée avec ansible-core 2.21 sur `adm01`, cible `dns01` (Debian 13, Python 3.13). Les chemins temporaires, horodatages et tailles varient d'une exécution à l'autre.

## 1. Cycle d'exécution d'une tâche

```
adm01 (contrôleur)                                                     dns01 (cible)
─────────────────                                                      ─────────────
1. analyse du playbook, variables résolues pour l'hôte,
   modèles Jinja2 rendus → arguments de la tâche
2. action plugin (normal, template, copy…) :
   - construit le paquet AnsiballZ :
     wrapper Python + zip(module + module_utils importés) en base64
     + arguments JSON (ANSIBLE_MODULE_ARGS + _ansible_*)
3. connexion (ssh, multiplexée par ControlPersist)
   sans pipelining :                       ── mkdir ~/.ansible/tmp/ansible-tmp-… ──►  dossier 700
                                           ── PUT AnsiballZ_ping.py (sftp/scp) ──►   fichier
                                           ── chmod u+rwx ──►
                                           ── [sudo …] python3 AnsiballZ_ping.py ──► 4. le wrapper écrit le zip
                                                                                       dans un dossier de
                                                                                       tempfile (/tmp/ansible_
                                                                                       ping_payload_…), lance
                                                                                       le module, supprime le zip
                                           ◄── JSON sur la sortie standard ──        5. exit_json / fail_json
                                           ── rm -rf ~/.ansible/tmp/ansible-tmp-… ──► (sauf KEEP_REMOTE_FILES)
   avec pipelining :                       ── [sudo …] python3 (le wrapper sur l'entrée standard) ──►
                                           ◄── JSON ──
6. résultat analysé (changed, failed, diff…), callbacks, handlers notifiés
```

## 2. Observations

**Sans pipelining** (`-e ansible_pipelining=false -vvv`, extrait) :

```
<10.10.20.10> EXEC /bin/sh -c 'echo ~admin && sleep 0'
<10.10.20.10> EXEC /bin/sh -c '( umask 77 && mkdir -p "` echo /home/admin/.ansible/tmp `"&& mkdir "` echo /home/admin/.ansible/tmp/ansible-tmp-1791384427.94-13700-39731292529244 `" && echo ansible-tmp-…="…" ) && sleep 0'
<10.10.20.10> PUT /home/admin/.ansible/tmp/ansible-local-13692n4ez9mjn/tmp4m8tfgle TO /home/admin/.ansible/tmp/ansible-tmp-…/AnsiballZ_ping.py
<10.10.20.10> EXEC /bin/sh -c 'chmod u+rwx /home/admin/.ansible/tmp/ansible-tmp-…/ /home/admin/.ansible/tmp/ansible-tmp-…/AnsiballZ_ping.py && sleep 0'
<10.10.20.10> EXEC /bin/sh -c '/usr/bin/python3 /home/admin/.ansible/tmp/ansible-tmp-…/AnsiballZ_ping.py && sleep 0'
```

La ligne `rm -f -r …` de nettoyage est absente : `ANSIBLE_KEEP_REMOTE_FILES=1` la supprime, c'est tout son rôle. Le fichier `AnsiballZ_ping.py` fait environ 160 Ko pour un module de quelques lignes : l'essentiel est `module_utils`.

Fin du fichier (abrégée) :

```python
if __name__ == "__main__":
    _ansiballz_main(
ansible_module='ansible.builtin.ping',
module_fqn='ansible.modules.ping',
profile='legacy',
date_time=datetime.datetime(2026, 10, 7, 14, 47, 8, …),
rlimit_nofile=0,
params='{"ANSIBLE_MODULE_ARGS": {"data": "octobre", "_ansible_check_mode": false, "_ansible_no_log": false, "_ansible_diff": false, "_ansible_verbosity": 3, "_ansible_version": "2.21.5", …}}',
extensions={},
zip_data='UEsDBBQAAAAIAON1R10…',
)
```

`zip_data` est une archive zip encodée en base64 : `ansible/modules/ping.py`, `ansible/module_utils/basic.py`, `common/…`, `parsing/convert_bool.py`, `distro/…`, etc. `profile` désigne le profil de sérialisation des échanges contrôleur ↔ module, introduit avec le *data tagging* (2.19).

**Explode / execute** :

```
admin@dns01:~$ python3 ~/.ansible/tmp/ansible-tmp-…/AnsiballZ_ping.py explode
Module expanded into:
/home/admin/.ansible/tmp/ansible-tmp-…/debug_dir
admin@dns01:~$ find ~/.ansible/tmp/ansible-tmp-…/debug_dir -name '*.py' | head
admin@dns01:~$ sed -i 's/"data": "octobre"/"data": "crash"/' ~/.ansible/tmp/ansible-tmp-…/debug_dir/args
admin@dns01:~$ python3 ~/.ansible/tmp/ansible-tmp-…/AnsiballZ_ping.py execute
```

Avec `data=crash`, le module `ping` lève volontairement une exception : on obtient la trace Python complète **sur la cible**, sans l'enrobage du contrôleur. On peut ajouter des `print()` dans `debug_dir/ansible/modules/ping.py` et relancer `execute`. Nettoyage : `rm -rf ~/.ansible/tmp/ansible-tmp-…`.

**Avec pipelining** : plus de `mkdir`, `PUT`, `chmod`, `rm` ; une seule exécution `python3 && sleep 0` dont l'entrée standard porte le wrapper. Le wrapper écrit **quand même** le zip dans un dossier de `tempfile.mkdtemp()` (`/tmp/ansible_ping_payload_…`), qu'il supprime en sortie : le pipelining supprime les allers-retours SSH et le fichier `AnsiballZ_*.py`, pas l'extraction.

## Réponses aux questions

1. **Pourquoi un zip base64 de module + `module_utils`.** La cible n'a pas Ansible installé : tout le code dont le module a besoin doit voyager avec lui, en un seul transfert, sans dépendre de la version d'Ansible présente (ou non) sur la cible. Le zip est importable directement (`zipimport`/chemin dans `sys.path`) ; le base64 le rend transportable dans un fichier texte Python (et sur l'entrée standard avec le pipelining). Les `module_utils` embarqués sont trouvés par **analyse statique des imports** du module (et récursivement des `module_utils` importés) sur le contrôleur, d'où l'obligation d'importer `module_utils` par des instructions `import` ordinaires (pas d'import dynamique).
2. **Arguments `_ansible_*`.** Ce sont des paramètres internes ajoutés par le contrôleur à ceux de la tâche : mode vérification (`_ansible_check_mode`), mode différence (`_ansible_diff`), masquage des journaux (`_ansible_no_log`), verbosité, version, dossier temporaire distant, etc. Ils sont lus par `AnsibleModule` (`module.check_mode`, `module._diff`, `no_log`…) avant la validation de l'`argument_spec` : le module n'a pas à les déclarer.
3. **Où le paquet est écrit et exécuté.** Sans pipelining : `AnsiballZ_<module>.py` est déposé dans `~/.ansible/tmp/ansible-tmp-…/` de l'utilisateur de **connexion** (`remote_tmp`), exécuté (par `sudo` si `become`), et le zip est extrait par le wrapper dans un dossier de `tempfile` (souvent `/tmp`). Avec pipelining : rien n'est déposé, le wrapper arrive sur l'entrée standard de Python ; seul le zip temporaire est écrit. Avec `become_user` **non privilégié** et sans pipelining : le fichier appartient à l'utilisateur de connexion, l'utilisateur cible ne peut pas le lire ; Ansible tente alors des ACL POSIX (`setfacl`), puis un changement de propriétaire, puis échoue (« Failed to set permissions on the temporary files Ansible needs to create when becoming an unprivileged user ») sauf à autoriser des fichiers temporaires lisibles par tous (option `world_readable_temp` du plugin shell, déconseillée). Le pipelining évite le problème.
4. **Rien sur la sortie standard hors du JSON.** Le contrôleur lit la sortie standard du module et en extrait le JSON : des lignes parasites **avant** le JSON sont écartées, du texte **après** donne l'avertissement « Module invocation had junk after the JSON data », et une sortie sans JSON exploitable fait échouer la tâche (`MODULE FAILURE`, sortie brute affichée). Un `print()` de débogage rend donc le résultat fragile, voire faux ; on utilise `module.debug()`, `module.warn()`, ou `explode`/`execute` sur la cible.
5. **Module sans `supports_check_mode`.** Le module est bien envoyé et lancé, mais `AnsibleModule` constate dès son initialisation que `_ansible_check_mode` est vrai et que le module ne le prend pas en charge : il sort aussitôt avec `skipped` (« remote module (…) does not support check mode »), sans rien faire. Un rôle qui en dépend (une tâche qui enregistre un résultat utilisé plus loin) peut alors échouer en `--check` sur une variable indéfinie, ou annoncer « rien à changer » à tort : le `--check` de la CI devient aveugle sur cette tâche.
6. **`atomic_move`.** Le module écrit le nouveau contenu dans un fichier temporaire du **même** système de fichiers puis le renomme sur la cible (`rename(2)`, atomique) en conservant les attributs (droits, propriétaire, contexte SELinux). Un lecteur voit soit l'ancien fichier, soit le nouveau, jamais un fichier tronqué. Écrire directement, c'est risquer qu'un `daemon-reload`, un rechargement de `sshd` ou un redémarrage de la machine lise un fichier à moitié écrit (ou vide si le disque est plein) : unité qui ne démarre plus, service sans configuration.
7. **Module, template, rôle ou filtre ?** *Pour un module* : une opération qu'on veut **décrire par son intention** et ses paramètres validés (`settings` est un dictionnaire typé, pas un texte libre) ; une logique d'idempotence ou de comparaison qui serait illisible en Jinja2 ; un besoin de tests unitaires et de `--diff` précis ; une réutilisation dans plusieurs rôles. *Contre* : un `template` + `systemd_service: daemon_reload` en handler fait la même chose en 10 lignes connues de tous ; un module est du code Python à maintenir, tester et faire évoluer avec ansible-core. Pour `systemd_dropin`, le module se justifie à l'échelle (plusieurs rôles, plusieurs unités, revue simplifiée), pas pour un seul fichier. Un **filtre** transforme des données sur le contrôleur et ne touche jamais la cible ; un **rôle** assemble des tâches.
8. **Action plugin.** Code exécuté **sur le contrôleur** avant (ou à la place de) l'exécution du module. `template` en a besoin pour rendre le modèle Jinja2 sur le contrôleur (variables, filtres, fichiers locaux), puis transférer le résultat et appeler le module `copy` sur la cible. Un module seul ne voit ni les variables ni les fichiers du contrôleur. Par défaut, une tâche passe par l'action plugin `normal`, qui se contente d'exécuter le module.
9. **Interpréteur Python.** `interpreter_python` (défaut `auto`) : à la première tâche, Ansible cherche une liste d'interpréteurs connus sur la cible (`python3.14`, `python3.13`, …, `/usr/bin/python3`, `python3`) et retient le premier trouvé ; il affiche un avertissement quand le résultat pourrait changer si un autre Python était installé, d'où l'intérêt de fixer `ansible_python_interpreter: /usr/bin/python3` pour le socle. Sans Python sur la cible, les modules Python échouent ; restent `ansible.builtin.raw` (commande brute par SSH, sert à installer Python), `ansible.builtin.script` (transfère et exécute un script), les modules binaires et, sur Windows, les modules PowerShell.
10. **`ansible-test sanity`.** Ensemble de contrôles statiques d'une collection : validation de `DOCUMENTATION`/`EXAMPLES`/`RETURN` et cohérence avec l'`argument_spec` (`validate-modules`), compilation sur les versions de Python prises en charge (`compile`), règles `pylint` et `pep8`, `shebang`, fins de ligne, restrictions d'import dans les modules (pas d'import de code du contrôleur, seulement `module_utils`), etc. (liste exacte : `ansible-test sanity --list-tests`). Il attrape avant la revue les écarts entre la documentation et le code, qui font mentir `ansible-doc`.
