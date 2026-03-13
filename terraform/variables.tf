variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "location" {
  description = "Azure Region"
  type        = string
  default     = "francecentral"
}

variable "project_name" {
  description = "Nom du projet"
  type        = string
  default     = "devops-romain"
}

variable "vm_size" {
  description = "Taille de la VM"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "admin_username" {
  description = "Username admin VM"
  type        = string
  default     = "adminuser"
}

variable "admin_password" {
  description = "Password admin VM"
  type        = string
  sensitive   = true
}
