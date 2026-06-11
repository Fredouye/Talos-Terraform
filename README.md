# Talos cluster — Ansible automation

Déploiement complet d'un cluster Kubernetes Talos sur vSphere, piloté par Ansible. Le playbook orchestre : la génération des images Talos via Image Factory, le provisionnement des VMs via Terraform (backend S3/MinIO), et l'installation des composants cluster (MetalLB, ArgoCD, NGINX Ingress Controller).

## Architecture

```
ansible/
├── build.yml                   # Playbook de construction
├── destroy.yml                 # Playbook de destruction
├── ansible.cfg
├── inventory/
│   └── hosts.yml               # Cible : localhost (connexion locale)
├── group_vars/
│   └── all/
│       ├── vars.yml            # Configuration non-sensible
│       └── vault.yml           # Secrets chiffrés (ansible-vault)
├── templates/
│   ├── terraform.tfvars.j2     # Variables Terraform (généré à l'exécution)
│   └── backend.hcl.j2          # Backend S3 MinIO (généré à l'exécution)
└── roles/talos_cluster/tasks/
    ├── main.yml                # Orchestrateur
    ├── fetch_secrets.yml       # Récupération des secrets depuis OpenBao
    ├── generate_schematics.yml # Génération des schematic IDs (Image Factory)
    ├── generate_tfvars.yml     # Rendu des templates Terraform
    ├── upload_ova.yml          # Upload des OVA Talos vers vCenter
    ├── terraform_plan.yml      # terraform init + plan
    ├── terraform_apply.yml     # terraform apply
    ├── terraform_destroy.yml   # terraform destroy (destroy.yml uniquement)
    ├── save_outputs.yml        # Sauvegarde des outputs dans OpenBao
    ├── deploy_metallb.yml      # MetalLB + pool IP L2
    ├── deploy_argocd.yml       # ArgoCD
    └── deploy_nginx_ingress.yml # F5 NGINX Ingress Controller
```

## Prérequis

### Binaires

| Outil | Rôle |
|---|---|
| `ansible` | Exécution des playbooks |
| `terraform` ≥ 1.15 | Provisionnement des VMs vSphere |
| `talosctl` | Optionnel — opérations post-déploiement |
| `helm3` | Déploiement des charts Helm (chemin : `~/bin/helm3`) |
| `kubectl` | Vérification manuelle post-déploiement |

### Collections Ansible

```bash
ansible-galaxy collection install \
  community.general \
  community.hashi_vault \
  community.vmware \
  kubernetes.core \
  amazon.aws
```

### Secrets dans OpenBao

Tous les secrets sont stockés dans OpenBao (compatible Vault) à `kv/talos-dev/config` :

```bash
bao kv put kv/talos-dev/config \
  vsphere_username="talos-dev@vsphere.local" \
  vsphere_password="..." \
  rancher_token="token-xxxxx:..." \
  minio_access_key="..." \
  minio_secret_key="..."
```

Le token OpenBao lui-même est stocké dans `group_vars/all/vault.yml` (chiffré ansible-vault) sous la clé `vault_bao_token`.

### Fichier vault

Le mot de passe vault est lu depuis `~/.ansible/vault_pass` (configuré dans `ansible.cfg`). Pour le créer :

```bash
echo "mon-mot-de-passe" > ~/.ansible/vault_pass
chmod 600 ~/.ansible/vault_pass
```

Pour éditer les secrets vault :

```bash
ansible-vault edit group_vars/all/vault.yml
```

## Configuration

Tous les paramètres non-sensibles se trouvent dans `group_vars/all/vars.yml` :

| Section | Variables clés |
|---|---|
| **vSphere** | `vsphere_server`, `vsphere_datacenter`, `vsphere_cluster`, `vsphere_datastore` |
| **Réseau** | `cluster_vip`, `control_plane_ips`, `worker_ips`, `gateway` |
| **Cluster** | `cluster_name`, `talos_version`, `kubernetes_version` |
| **VMs** | `cp_cpu/memory/disk_gb`, `worker_cpu/memory/disk_gb/longhorn_disk_gb` |
| **Extensions Talos** | `cp_extensions`, `worker_extensions` |
| **MetalLB** | `metallb_ip_range` (plage LoadBalancer, ex. `192.168.3.90-192.168.3.95`) |
| **Backend** | `minio_endpoint`, `minio_tf_bucket`, `minio_tf_key` |

### Versions des charts Helm

```yaml
metallb_helm_version: "0.15.3"
argocd_helm_version:  "9.4.17"
nginx_helm_version:   "2.5.1"
```

## Utilisation

### Construire le cluster

```bash
# Run complet
ansible-playbook build.yml

# Générer terraform.tfvars uniquement
ansible-playbook build.yml --tags tfvars

# Plan Terraform uniquement (sans apply)
ansible-playbook build.yml --skip-tags tf_apply,tf_outputs

# Déployer uniquement les composants Helm (infra déjà existante)
ansible-playbook build.yml --tags metallb,argocd,nginx

# Sauvegarder les outputs Terraform dans OpenBao uniquement
ansible-playbook build.yml --tags tf_outputs

# Autoriser les destructions Terraform (désactive le safety check)
ansible-playbook build.yml -e tf_allow_destroy=true
```

### Détruire le cluster

```bash
ansible-playbook destroy.yml -e tf_confirm_destroy=yes
```

Le playbook affiche le plan de destruction et demande une confirmation manuelle avant d'exécuter. Post-destruction, les outputs OpenBao et le state MinIO sont automatiquement supprimés.

## Ce que fait le playbook `build.yml`

1. **Prérequis** — Vérifie la présence de `terraform` et `talosctl`
2. **Secrets** — Récupère les credentials depuis OpenBao (`kv/talos-dev/config`)
3. **Schematics** — Génère les IDs de schematic Talos via [Image Factory](https://factory.talos.dev) en fonction des extensions configurées (CP et workers ont des sets différents)
4. **OVA** — Vérifie si les templates vSphere existent ; les télécharge et les importe depuis Image Factory si besoin
5. **Terraform tfvars** — Rend `terraform.tfvars` et `backend.hcl` depuis les templates Jinja2
6. **Terraform init** — Initialise le backend S3 MinIO avec `terraform init -reconfigure -backend-config=backend.hcl`
7. **Terraform plan** — Génère le plan et bloque si des destructions sont détectées (safety check)
8. **Terraform apply** — Provisionne les VMs vSphere, bootstrap Talos, importe le cluster dans Rancher
9. **Outputs** — Sauvegarde `talosconfig`, `kubeconfig` et les IPs dans OpenBao ; écrit les fichiers locaux (`~/.talos/config`, `~/.kube/talos-dev.yaml`)
10. **MetalLB** — Déploie MetalLB via Helm, configure le pool IP L2 (`metallb_ip_range`) et la L2Advertisement
11. **ArgoCD** — Déploie ArgoCD via Helm, affiche le mot de passe admin initial
12. **NGINX Ingress** — Déploie le F5 NGINX Ingress Controller via Helm, attend l'attribution d'une IP LoadBalancer par MetalLB

## Cluster déployé

| Composant | Version | Namespace |
|---|---|---|
| Talos | `v1.12.2` | — |
| Kubernetes | `v1.34.1` | — |
| MetalLB | `0.15.3` | `metallb-system` |
| ArgoCD | `9.4.17` (app `v3.3.6`) | `argocd` |
| NGINX Ingress | `2.5.1` (app `5.4.1`) | `nginx-ingress` |

**Topologie :**
- 3 control planes : `192.168.3.41–43` — VIP : `192.168.3.40`
- 3 workers : `192.168.3.44–46`
- Pool LoadBalancer MetalLB : `192.168.3.90–95`

## Adresses MAC des VMs

Les adresses MAC sont générées **de façon déterministe** à partir du nom du cluster, ce qui garantit des adresses uniques et stables sans assignation manuelle.

### Algorithme

1. Calcul du hash MD5 du `cluster_name` → 32 caractères hexadécimaux
2. **Byte 4** : les 2 premiers caractères du hash, convertis en entier, modulo 64 (pour rester dans la plage VMware `00`–`3F`)
3. **Byte 5** : les 2 caractères suivants du hash, convertis en entier
4. **Byte 6** : index séquentiel — `0, 1, 2` pour les control planes, puis `3, 4, 5` pour les workers
5. Préfixe fixe VMware : `00:50:56` (plage manuelle : `00:50:56:00:00:00` – `00:50:56:3F:FF:FF`)

Format final : `00:50:56:<byte4>:<byte5>:<index>`

### Exemple avec `cluster_name = "talos-dev"`

```
md5("talos-dev") = 73884459921d4b14a5ac97a2791d3f09

byte4 = 0x73 (115) % 64 = 51 → 0x33
byte5 = 0x88 (136)            → 0x88
```

| VM | Index | Adresse MAC |
|---|---|---|
| control-plane-0 | 0 | `00:50:56:33:88:00` |
| control-plane-1 | 1 | `00:50:56:33:88:01` |
| control-plane-2 | 2 | `00:50:56:33:88:02` |
| worker-0 | 3 | `00:50:56:33:88:03` |
| worker-1 | 4 | `00:50:56:33:88:04` |
| worker-2 | 5 | `00:50:56:33:88:05` |

Changer `cluster_name` produit un jeu de MACs entièrement différent, évitant les collisions entre clusters sur le même réseau vSphere.

## Compatibilité Terraform 1.15+

Depuis Terraform 1.15, `terraform validate` valide le bloc `backend` même lorsqu'il est vide. Le bloc `backend "s3" {}` dans `providers.tf` est intentionnellement vide (la configuration est injectée au `init` via `backend.hcl`). Pour contourner ce changement, le playbook exécute `terraform init` explicitement avant de lancer plan et apply — sans passer par le module `community.general.terraform` qui appelait `validate` en premier.
