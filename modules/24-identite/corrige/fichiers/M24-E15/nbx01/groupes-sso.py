# nbx01 — groupes NetBox du SSO (M24-E15, SEC-2515). À lancer UNE fois dans le shell de NetBox :
#   admin@nbx01:~$ sudo -u netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py nbshell < groupes-sso.py
# Idempotent : crée (ou complète) les groupes sso-lecture et sso-ecriture et leurs permissions d'objets.
# sso-lecture : « view » sur tous les types d'objets ; sso-ecriture : toutes les actions.
# Les personnes reçoivent sso-lecture à chaque connexion (REMOTE_AUTH_DEFAULT_GROUPS) ; sso-ecriture
# est donné à la main (Admin → Users) aux membres de plateforme-admins, et revu par la revue d'accès.
from core.models import ObjectType
from users.models import Group, ObjectPermission

types = ObjectType.objects.public()
for nom, actions in (("sso-lecture", ["view"]), ("sso-ecriture", ["view", "add", "change", "delete"])):
    groupe, _ = Group.objects.get_or_create(name=nom, defaults={"description": f"SSO MédiSphère (M24-E15) : {', '.join(actions)}"})
    permission, _ = ObjectPermission.objects.get_or_create(name=f"{nom} : tout", defaults={"actions": actions, "enabled": True})
    permission.actions = actions
    permission.enabled = True
    permission.save()
    permission.object_types.set(types)
    permission.groups.add(groupe)
    print(f"{nom} : {len(actions)} action(s) sur {types.count()} types d'objets")
