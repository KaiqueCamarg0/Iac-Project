# Quando o código rodar ao final irá mostrar o ip publico para acesso a nossa máquina

output "loadbalancer_public_ip" {
  description = "IP Público para acessar o Load Balancer"
  value       = azurerm_public_ip.lb_pip.ip_address
}

output "zabbix_public_ip" {
  description = "Endereço público do Zabbix Server"
  value       = azurerm_public_ip.vm_single_public_ip.ip_address
}