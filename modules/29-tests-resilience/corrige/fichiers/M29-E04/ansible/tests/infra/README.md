# tests/infra — tests d'infrastructure du socle (Testinfra)

Tests des rôles `durcissement`, `node_exporter`, `alloy` et du client de temps du rôle `base`, joués
**contre le parc réel** (pas des VMs jetables : c'est le rôle de Molecule). M29-E04.

```
uv sync --group tests
uv run pytest tests/infra --hosts='ansible://socle' -n 4                 # tout le socle
uv run pytest tests/infra --hosts='ansible://dns01' -m chrony -v          # un hôte, un rôle
uv run pytest tests/infra --hosts='ansible://socle' -m "not reseau"       # sans les contrôles depuis le contrôleur
```

- Inventaire : celui d'`ansible.cfg` (NetBox) ; exporte `NETBOX_TOKEN` (`~/.config/workbook/netbox-ansible.env`).
- Clé SSH : sur `adm01`, celle de l'agent ; en CI, `--ssh-identity-file="$ANSIBLE_PRIVATE_KEY_FILE"`.
- Un test sauté (« skipped ») a toujours une raison : rôle pas encore appliqué, règle en exception
  (registre du M26), famille de système non visée.
- Rapport JUnit : `rapports/junit/testinfra.xml`.
