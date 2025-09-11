# Quando o código rodar ao final irá mostrar o ip publico para acesso a nossa máquina
output "public_ip_address" {
  value = azurerm_public_ip.public_ip.ip_address
}