# Ansible – Claude Code Conventions

## Core rule
Always prefer native Ansible modules over `shell`, `command`, `raw`, or `script`.

## shell/command modules: forbidden except as a last resort
- Never use `ansible.builtin.shell` or `ansible.builtin.command` if a native module exists
- If no native module covers the need, explain in a comment why `shell`/`command` is used

## Mandatory substitutions

| Avoid | Use instead |
|---|---|
| `shell: apt-get install -y nginx` | `ansible.builtin.apt` |
| `shell: systemctl restart nginx` | `ansible.builtin.systemd` |
| `command: mkdir -p /etc/app` | `ansible.builtin.file: state=directory` |
| `shell: cp src dest` | `ansible.builtin.copy` |
| `shell: sed -i ...` | `ansible.builtin.lineinfile` or `replace` |
| `shell: useradd ...` | `ansible.builtin.user` |
| `command: openssl ...` | `community.crypto.*` |

## General style
- Always use the FQCN (Fully Qualified Collection Name): `ansible.builtin.apt` not just `apt`
- Declare `become: false` at the play level, and use `become: true` only on individual tasks that require root
- Use `notify` + handlers for service restarts
- Prefer `ansible.builtin.template` over `ansible.builtin.copy` whenever variables are involved

## Idempotency
Every task must be idempotent. If not guaranteed natively, use `changed_when` and `failed_when` explicitly.
