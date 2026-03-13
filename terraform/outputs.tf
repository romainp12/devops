output "vm_ip_publique" {
  description = "IP publique de la VM"
  value       = azurerm_public_ip.main.ip_address
}

output "flask_url" {
  description = "URL de l'API Flask"
  value       = "http://${azurerm_public_ip.main.ip_address}:5000"
}

output "storage_account_name" {
  description = "Nom du storage account"
  value       = azurerm_storage_account.main.name
}

output "container_name" {
  description = "Nom du container Blob"
  value       = azurerm_storage_container.main.name
}
