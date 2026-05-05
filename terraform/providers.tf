terraform {
  required_version = ">= 1.5"

  backend "s3" {
    # Backend configuration is injected at init time by Ansible via the
    # community.general.terraform backend_config parameter.
    # No values are hardcoded here — see terraform_plan.yml.
  }

  required_providers {
    vsphere = {
      source  = "vmware/vsphere"
      version = "~> 2.8"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.7"
    }
    rancher2 = {
      # Provider major version must match Rancher minor version.
      # Rancher 2.13 → rancher2 ~> 13.0
      source  = "rancher/rancher2"
      version = "~> 13.0"
    }
    vault = {
      # Compatible with OpenBao — same API, same provider.
      # Credentials are never stored in tfvars or Ansible vault.
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# ─── OpenBao (via Vault provider) ─────────────────────────────────────────────
# VAULT_ADDR and VAULT_TOKEN must be set in the environment before running
# Terraform. The Ansible playbook sets these from vault_bao_token in vault.yml.

provider "vault" {
  # address and token are read from VAULT_ADDR / VAULT_TOKEN env vars.
}

# ─── Secrets from OpenBao ─────────────────────────────────────────────────────
# All secrets are stored at a single KV path — same path used by Ansible
# fetch_secrets.yml — keeping both in sync.
# Store with:
#   bao kv put kv/talos-dev/config \
#     vsphere_username="talos-dev@vsphere.local" \
#     vsphere_password="..." \
#     rancher_token="token-xxxxx:..." \
#     minio_access_key="..." \
#     minio_secret_key="..."

data "vault_kv_secret_v2" "config" {
  mount = "kv"
  name  = "talos-dev/config"
}

# ─── Providers ────────────────────────────────────────────────────────────────

provider "vsphere" {
  user                 = data.vault_kv_secret_v2.config.data["vsphere_username"]
  password             = data.vault_kv_secret_v2.config.data["vsphere_password"]
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

provider "talos" {}

provider "rancher2" {
  api_url   = var.rancher_url
  token_key = data.vault_kv_secret_v2.config.data["rancher_token"]
  insecure  = true
}
