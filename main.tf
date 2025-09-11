# Dizemos quem vai ser o nosso provedor da infraestrutura e a versão que vai ser utilizada
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }

  required_version = ">= 1.1.0"
}

# Configuramos para o terraform se conectar a nossa conta do Azure e nossa assinatura

provider "azurerm" {
  features {}

    subscription_id = "35789804-a13e-4872-99d8-e9e308059479"
    client_id = "0e246783-1d11-40a6-a98b-02beb69d690a"
    client_secret = "nxk8Q~lQU4eScvggu6VNBMbZvmjcsnfDFmqC4bh9"
    tenant_id = "b1051c4b-3b94-41ab-9441-e73a72342fdd"


}

#Aqui criamos o Grupo de Recursos que vai gerenciar toda a infraestrutura

resource "azurerm_resource_group" "rg" {
  name     = "myTFResourceGroup"
  location = "eastus"
}

#Cria uma rede virtual (VNet) com a faixa de IP 192.168.150.0/24:

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-TF"
  address_space       = ["192.168.150.0/24"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

#Criamos uma sub-rede (subnet) dentro da VNet:

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-TF"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.168.150.0/24"]
}

#Cria um endereço IP público dinâmico para podermos acessa-la de fora:

resource "azurerm_public_ip" "public_ip" {
  name                = "ip-publico-TF"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  allocation_method   = "Static"
  sku                 = "Standard" 

}

# Aqui esta o grupo de segurança de internet para acessos a VM

resource "azurerm_network_security_group" "nsg_ssh" {
  name                = "nsg-ssh"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Cria a interface de rede (NIC) da VM: Conecta a VM à Subnet. Gera um IP privado automaticamente. Associa o IP público que criamos antes.

resource "azurerm_network_interface" "nic" {
  name                = "nic-TF"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }

}

#Associa o grupo de segurança á interface NIC

resource "azurerm_network_interface_security_group_association" "nsg_association" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg_ssh.id
}


# Cria a máquina virtual com a configuração: "Standard_B1s" e conecta ela com toda a rede que criamos antes e ao grupo de recursos 

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-TF"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  admin_password      = "achoumesmoqueeuiacolocarasenhaaqui" 

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "osdisk-vm-exemplo"
  }

  source_image_reference {
  publisher = "Debian"
  offer     = "debian-12"
  sku       = "12"
  version   = "latest"
}


  disable_password_authentication = false
}

