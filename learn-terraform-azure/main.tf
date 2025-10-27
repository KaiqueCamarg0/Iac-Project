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

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-TF"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "subnet-TF"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Public IP para o Load Balancer
resource "azurerm_public_ip" "lb_pip" {
  name                = "lb-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Load Balancer
resource "azurerm_lb" "lb" {
  name                = "lb-TF"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb_pip.id
  }
}

# Backend pool
resource "azurerm_lb_backend_address_pool" "bepool" {
  loadbalancer_id = azurerm_lb.lb.id
  name            = "BackEndAddressPool"
}
# Network Security Group para liberar HTTP
resource "azurerm_network_security_group" "nsg" {
  name                = "vmss-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associa o NSG à Subnet
resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Probing HTTP (Apache2)
resource "azurerm_lb_probe" "http" {
  loadbalancer_id     = azurerm_lb.lb.id
  name                = "http-probe"
  protocol            = "Tcp"
  port                = 80
}

# Regras do Load Balancer
resource "azurerm_lb_rule" "http" {
  loadbalancer_id                = azurerm_lb.lb.id
  name                           = "http-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.bepool.id]
  probe_id                       = azurerm_lb_probe.http.id
}

# VM Scale Set
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "vmss-demo"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard_B1s"
  instances           = 2   # 2 VMs de base
  admin_username      = "azureuser"

  admin_password      = "Y0ush@lln0tp@ss" # em produção use KeyVault ou SSH key
  disable_password_authentication = false

  source_image_reference {
  publisher = "Debian"
  offer     = "debian-12"
  sku       = "12"
  version   = "latest"
}


  network_interface {
    name    = "vmss-nic"
    primary = true

    ip_configuration {
      name                                   = "internal"
      subnet_id                              = azurerm_subnet.subnet.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bepool.id]
      primary                                = true
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  upgrade_mode = "Automatic"

  # Instala Apache2 via cloud-init
  custom_data = base64encode(<<EOF
#!/bin/bash
apt-get update
apt-get install -y apache2
systemctl enable apache2
systemctl start apache2
echo "<h1>VMSS Apache - $(hostname)</h1>" > /var/www/html/index.html
EOF
  )
}

# Autoscale
resource "azurerm_monitor_autoscale_setting" "autoscale" {
  name                = "autoscale-vmss"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss.id

  profile {
    name = "defaultProfile"

    capacity {
      default = 2
      minimum = 2
      maximum = 5
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 80
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}

# ==============================
# Máquina Virtual Única (igual ao VMSS)
# ==============================

resource "azurerm_network_interface" "vm_single_nic" {
  name                = "nic-vm-single"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Regras de segurança: SSH permitido apenas do IP 186.233.26.122
resource "azurerm_network_security_group" "vm_single_nsg" {
  name                = "nsg-vm-single"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH-From-Specific-IP"
    priority                   = 1001
    direction                   = "Inbound"
    access                      = "Allow"
    protocol                    = "Tcp"
    source_port_range           = "*"
    destination_port_range      = "22"
    source_address_prefix       = "186.233.26.122"
    destination_address_prefix  = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "vm_single_assoc" {
  network_interface_id      = azurerm_network_interface.vm_single_nic.id
  network_security_group_id = azurerm_network_security_group.vm_single_nsg.id
}

resource "azurerm_linux_virtual_machine" "vm_single" {
  name                = "vm-single"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = "Standard_B1s"
  admin_username      = "adminuser"                # 👈 altere o nome de usuário se quiser
  admin_password      = "Y0ush@lln0tp@ss"           # 👈 substitua por uma senha forte e segura
  disable_password_authentication = false          # necessário para login com senha

  network_interface_ids = [
    azurerm_network_interface.vm_single_nic.id,
  ]

  source_image_reference {
    publisher = azurerm_linux_virtual_machine_scale_set.vmss.source_image_reference[0].publisher
    offer     = azurerm_linux_virtual_machine_scale_set.vmss.source_image_reference[0].offer
    sku       = azurerm_linux_virtual_machine_scale_set.vmss.source_image_reference[0].sku
    version   = azurerm_linux_virtual_machine_scale_set.vmss.source_image_reference[0].version
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
}

