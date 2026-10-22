# Sous le capot : eBPF, LSM et chaîne d'admission

> Compte rendu de M26-E44. Remplace chaque « … » par ce que tu as relevé sur le lab (en lecture seule).
> Aucun secret. Publie par MR dans `docs/securite/durcissement/analyses/`.

## Les programmes eBPF

- Commande : `sudo bpftool prog show` sur le nœud … (relève un `id` réel : …).
- Par type (`kprobe`, `tracepoint`, `lsm`, `sched_cls`/`tc`, `cgroup_*`) : …
- Qui charge quoi : Cilium (…), Falco (…), Tetragon (…). Programmes épinglés dans `/sys/fs/bpf` : …
- Ce que le vérificateur eBPF garantit : …

## Les LSM

- `cat /sys/kernel/security/lsm` : … (LSM majeur : AppArmor sur Debian / SELinux sur Rocky ; BPF-LSM ?).
- Hook `security_bprm_check` (à `execve`) et lien avec « binaire exécuté depuis /tmp » : …
- Rapport avec seccomp (`seccompDefault`) : …

## La chaîne d'admission

- Ordre relevé : authentification → autorisation → mutation → validation → persistance.
- Où une charge non conforme est arrêtée (PSA ? Kyverno ? VAP native ?) : … (message observé : …).
- Pourquoi la mutation vient avant la validation : …

## L'auditID de bout en bout

- `auditID` relevé : … ; étapes `RequestReceived` → `ResponseComplete` ; verdict (`responseStatus`) : …

## Réponses aux questions

1. … 2. … 3. … 4. … 5. … 6. … 7. … 8. …
