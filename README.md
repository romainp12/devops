# devops

Déploiement automatisé d'une infrastructure Azure avec Terraform.

Flask · Azure Blob Storage · PostgreSQL · Compute VM

---

## Architecture

- **VM** : Azure Compute (Ubuntu 22.04, Standard_D2s_v3) — France Central
- **Stockage** : Azure Blob Storage (container `fichiers`)
- **Base de données** : PostgreSQL Flexible Server
- **Backend** : Flask (Python 3)
- **IaC** : Terraform

---

## Prérequis

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [Azure CLI](https://learn.microsoft.com/fr-fr/cli/azure/install-azure-cli)
- Un compte Azure avec un abonnement actif (les free credits suffisent)

---

## Installation

### 1. Cloner le dépôt

```bash
git clone https://github.com/romainp12/devops.git
cd devops
```

### 2. Se connecter à Azure

```bash
az login
```

### 3. Configurer les variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Remplir avec ton subscription_id et un mot de passe
```

### 4. Déployer

```bash
cd terraform
terraform init
terraform apply
```

Au bout de ~10 minutes :

```
flask_url         = "http://XX.XX.XX.XX:5000"
vm_ip_publique    = "XX.XX.XX.XX"
storage_account_name = "devopsromainstore"
```

---

## Tester l'API

```bash
VM_IP=$(terraform output -raw vm_ip_publique)

# Health check
curl http://$VM_IP:5000/

# Upload un fichier
curl -X POST http://$VM_IP:5000/upload -F "file=@/tmp/test.txt"

# Lister les fichiers
curl http://$VM_IP:5000/fichiers

# Supprimer un fichier
curl -X DELETE http://$VM_IP:5000/fichiers/UUID-ICI
```

---

## Endpoints API

| Méthode | Route | Description |
|---------|-------|-------------|
| GET | `/` | Health check |
| POST | `/upload` | Upload un fichier vers Blob Storage |
| GET | `/fichiers` | Lister tous les fichiers |
| GET | `/fichiers/<id>` | Détails d'un fichier |
| DELETE | `/fichiers/<id>` | Supprimer un fichier |

---

## Détruire l'infrastructure

```bash
terraform destroy
```

---

## Structure du projet

```
devops/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── terraform.tfvars.example
├── backend/
│   ├── app.py
│   └── requirements.txt
└── README.md
```
