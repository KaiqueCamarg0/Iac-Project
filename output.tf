output "resource_group_name" {
  description = "Nome do Resource Group"
  value       = azurerm_resource_group.rg.name
}

output "loadbalancer_public_ip" {
  description = "IP Público para acessar o Load Balancer"
  value       = azurerm_public_ip.lb_pip.ip_address
}