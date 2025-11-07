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
  
  security_rule {
  name                        = "Allow-Grafana-3000"
  priority                    = 1005
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range            = "*"
  destination_port_range       = "3000"
  source_address_prefix        = "*"
  destination_address_prefix   = "0.0.0.0/0"
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
  instances           = 1   # 2 VMs de base
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

  custom_data = base64encode(<<EOF
#cloud-config
package_update: true
package_upgrade: true
packages:
  - wget
  - curl
  - zabbix-agent
  - apache2

runcmd:
  - |
    #!/bin/bash
    echo "=== Configurando Zabbix Agent ==="
    systemctl enable zabbix-agent
    systemctl start zabbix-agent

    # Remove linhas existentes de configuração
    sed -i 's/^Server=/## Server=/g' /etc/zabbix/zabbix_agentd.conf
  

    # Adiciona as novas configurações
    echo "Server=10.0.1.10" >> /etc/zabbix/zabbix_agentd.conf
   

    # Reinicia o serviço para aplicar
    systemctl restart zabbix-agent

    echo "=== Zabbix Agent configurado e iniciado ==="

    # Configura Apache
    apt-get update -y
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
      default = 1
      minimum = 1
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
# ================================
# IP Público para o Zabbix Server
# ================================
resource "azurerm_public_ip" "vm_single_public_ip" {
  name                = "pip-vm-single"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ================================
# Interface de Rede da VM Zabbix
# ================================
resource "azurerm_network_interface" "vm_single_nic" {
  name                = "nic-vm-single"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.10"

    # 🔹 Associação do IP público
    public_ip_address_id = azurerm_public_ip.vm_single_public_ip.id
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
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "186.233.26.122"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP-Zabbix"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }

  security_rule {
  name                       = "Allow-Grafana"
  priority                   = 1003
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "3000"
  source_address_prefix      = "0.0.0.0/0"
  destination_address_prefix = "*"
  }

}

resource "azurerm_network_interface_security_group_association" "vm_single_assoc" {
  network_interface_id      = azurerm_network_interface.vm_single_nic.id
  network_security_group_id = azurerm_network_security_group.vm_single_nsg.id
}

resource "azurerm_linux_virtual_machine" "vm_single" {
  name                            = "vm-single"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = "Standard_B1s"
  admin_username                  = "adminuser"
  admin_password                  = "Y0ush@lln0tp@ss"
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.vm_single_nic.id,
  ]

  source_image_reference {
    publisher = "debian"
    offer     = "debian-12"
    sku       = "12"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # ==========================
  # Cloud-init (Instalação automática do Zabbix)
  # ==========================
  custom_data = base64encode(<<EOF
#cloud-config
package_update: true
package_upgrade: true
packages:
  - wget
  - curl
  - sudo
  - net-tools
  - ethtool
  - locales
  - postgresql
  - apache2

#cloud-config
runcmd:
  - |
    #!/bin/bash
    set -e

    echo "=== Ajustando localidade ==="
    sed -i 's/^# *pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen
    update-locale LANG=pt_BR.UTF-8

    echo "=== Instalando repositório do Zabbix ==="
    cd /tmp
    wget https://repo.zabbix.com/zabbix/7.4/release/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.4+debian12_all.deb
    dpkg -i zabbix-release_latest_7.4+debian12_all.deb
    apt-get update

    echo "=== Instalando Zabbix e dependências ==="
    apt-get install -y postgresql zabbix-server-pgsql zabbix-frontend-php php8.2-pgsql \
                       zabbix-apache-conf zabbix-sql-scripts zabbix-agent

    echo "=== Habilitando e iniciando PostgreSQL ==="
    systemctl enable postgresql
    systemctl start postgresql

    echo "=== Aguardando PostgreSQL inicializar ==="
    sleep 10
    until sudo -u postgres psql -c "select 1;" >/dev/null 2>&1; do
      echo "Aguardando PostgreSQL ficar pronto..."
      sleep 5
    done

    echo "=== Criando usuário e banco Zabbix ==="
    sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='zabbix'" | grep -q 1 || \
      sudo -u postgres psql -c "CREATE USER zabbix WITH PASSWORD 'senai101';"

    if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw zabbix; then
      sudo -u postgres psql -c "CREATE DATABASE zabbix OWNER zabbix;"
      echo "=== Importando schema do banco ==="
      zcat /usr/share/zabbix/sql-scripts/postgresql/server.sql.gz | sudo -u postgres psql zabbix
    fi

    echo "=== Ajustando permissões do banco ==="
    sudo -u postgres psql -d zabbix -c "GRANT ALL PRIVILEGES ON DATABASE zabbix TO zabbix;"
    sudo -u postgres psql -d zabbix -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO zabbix;"
    sudo -u postgres psql -d zabbix -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO zabbix;"
    sudo -u postgres psql -d zabbix -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO zabbix;"
    sudo -u postgres psql -d zabbix -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO zabbix;"
    sudo -u postgres psql -c "ALTER DATABASE zabbix OWNER TO zabbix;"

    echo "=== Configurando Zabbix ==="
    sed -i 's/^# DBPassword=.*/DBPassword=senai101/' /etc/zabbix/zabbix_server.conf
    chown -R zabbix:zabbix /etc/zabbix

    echo "=== Habilitando e iniciando serviços ==="
    systemctl enable zabbix-server zabbix-agent apache2
    systemctl restart zabbix-server zabbix-agent apache2

    echo "=============================================================="
    echo "  Zabbix 7.4 instalado com sucesso no Debian 12!"
    echo "  Acesse via navegador: http://<SEU_IP>/zabbix"
    echo "  Login padrão: Admin / Senha: zabbix"
    echo "=============================================================="
    
    sudo apt-get install -y apt-transport-https software-properties-common wget

    sudo mkdir -p /etc/apt/keyrings/
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null

    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list

    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com beta main" | sudo tee -a /etc/apt/sources.list.d/grafana.list

    # Updates the list of available packages
    sudo apt-get update

    # Installs the latest OSS release:
    sudo apt-get install grafana -y
    systemctl enable grafana-server
    systemctl start grafana-server


    #logar (localhost:3000)
EOF
  )
}

##########################################
# Cosmos DB Serverless (RU)
##########################################
resource "azurerm_cosmosdb_account" "cosmosdb" {
  name                = "cosmos-evosec-serverless"
  location            = "East US" # ⚠️ precisa estar em uma região que suporte serverless
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "MongoDB"

  capabilities {
    name = "EnableMongo"
  }

  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  enable_automatic_failover = false
  enable_free_tier          = true

  geo_location {
    location          = "East US"
    failover_priority = 0
  }

  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
    storage_redundancy  = "Local"
  }

  is_virtual_network_filter_enabled = false
  public_network_access_enabled     = true
  enable_multiple_write_locations   = false
  analytical_storage_enabled        = false
}

##########################################
# Banco de dados MongoDB
##########################################
resource "azurerm_cosmosdb_mongo_database" "db" {
  name                = "loja"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmosdb.name
}

##########################################
# Collection - Produtos
##########################################
resource "azurerm_cosmosdb_mongo_collection" "produtos" {
  name                = "produtos"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmosdb.name
  database_name       = azurerm_cosmosdb_mongo_database.db.name

  shard_key = "_id"

  index {
    keys = ["_id"]
  }
}
