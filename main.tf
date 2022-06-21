resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name}-vmnet"
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.address_space
  location            = azurerm_resource_group.this.location
}

resource "azurerm_subnet" "this" {
  for_each             = var.address_prefixes
  name                 = "${var.name}-${each.key}-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = each.value


  dynamic "delegation" {
    for_each = each.key == "app" ? [1] : []
    content {
      name = "delegation"

      service_delegation {
        name    = "Microsoft.ContainerInstance/containerGroups"
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }

  enforce_private_link_endpoint_network_policies = true

}

resource "azurerm_container_group" "this" {

  count               = 2
  name                = "${var.name}-container-${count.index}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  ip_address_type     = "Private"
  os_type             = "Linux"
  network_profile_id  = azurerm_network_profile.this.id

  container {
    name   = "hello-world"
    image  = var.docker_image
    cpu    = "0.5"
    memory = "1.5"

    ports {
      port     = 3000
      protocol = "TCP"
    }

    secure_environment_variables = {
      "user"     = "${var.user}@${var.name}-postgresql"
      "host"     = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
      "database" = "${var.name}-db"
      "password" = var.password
    }

  }
}

resource "azurerm_network_profile" "this" {

  name                = "${var.name}-container-network-interface"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  container_network_interface {
    name = "${var.name}-container-network-interface"

    ip_configuration {
      name      = "${var.name}-container-ip-config"
      subnet_id = azurerm_subnet.this["app"].id
    }
  }

}

resource "azurerm_public_ip" "this" {
  name                = "${var.name}-public-ip"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "network" {
  name                = "${var.name}-appgateway"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "${var.name}-gateway-ip-config"
    subnet_id = azurerm_subnet.this["web"].id
  }

  frontend_port {
    name = "${var.name}-gateway-frontend-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "${var.name}-gateway-frontend-ip-config"
    public_ip_address_id = azurerm_public_ip.this.id
  }

  backend_address_pool {
    name         = "${var.name}-gateway-backend-address-pool"
    ip_addresses = azurerm_container_group.this[*].ip_address
  }

  backend_http_settings {
    name                  = "${var.name}-gateway-backend-http-settings"
    cookie_based_affinity = "Disabled"
    path                  = "/"
    port                  = 3000
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "${var.name}-gateway-http-listener"
    frontend_ip_configuration_name = "${var.name}-gateway-frontend-ip-config"
    frontend_port_name             = "${var.name}-gateway-frontend-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "${var.name}-gateway-request-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "${var.name}-gateway-http-listener"
    backend_address_pool_name  = "${var.name}-gateway-backend-address-pool"
    backend_http_settings_name = "${var.name}-gateway-backend-http-settings"
    priority                   = 10
  }
}

resource "azurerm_postgresql_server" "this" {
  name                = "${var.name}-postgresql"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  administrator_login           = var.user
  administrator_login_password  = var.password
  auto_grow_enabled             = true
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  sku_name                      = "GP_Gen5_2"
  ssl_enforcement_enabled       = true
  storage_mb                    = 51200
  version                       = "11"
  public_network_access_enabled = false

  threat_detection_policy {
    disabled_alerts      = []
    email_account_admins = false
    email_addresses      = []
    enabled              = true
    retention_days       = 0
  }
}

resource "azurerm_postgresql_server" "replica" {
  name                = "${var.name}-postgresql-replica"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  create_mode                   = "Replica"
  creation_source_server_id     = azurerm_postgresql_server.this.id
  administrator_login           = var.user
  administrator_login_password  = var.password
  auto_grow_enabled             = true
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  sku_name                      = "GP_Gen5_2"
  ssl_enforcement_enabled       = true
  storage_mb                    = 51200
  version                       = "11"
  public_network_access_enabled = false

  threat_detection_policy {
    disabled_alerts      = []
    email_account_admins = false
    email_addresses      = []
    enabled              = true
    retention_days       = 0
  }
}

resource "azurerm_private_endpoint" "this" {
  name                = "${var.name}-postgres-endpoint"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.this["db"].id

  private_service_connection {
    name                           = "postgresql-connection"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_postgresql_server.this.id
    subresource_names              = ["postgresqlServer"]
  }
}

resource "azurerm_postgresql_database" "this" {
  name                = "${var.name}-db"
  resource_group_name = azurerm_resource_group.this.name
  server_name         = azurerm_postgresql_server.this.name
  charset             = "UTF8"
  collation           = "English_United States.1252"
}

resource "azurerm_network_security_group" "web" {
  name                = "${var.name}-web-security-group"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "Allow-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = var.address_prefixes["web"][0]
  }

  security_rule {
    name                       = "Allow-inbound-lb"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.this["web"].id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_network_security_group" "app" {
  name                = "${var.name}-app-security-group"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "Allow-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = var.address_prefixes["web"][0]
    destination_address_prefix = var.address_prefixes["app"][0]
  }

  security_rule {
    name                       = "Allow-outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.address_prefixes["app"][0]
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.this["app"].id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_network_security_group" "db" {
  name                = "${var.name}-db-security-group"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "Allow-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.address_prefixes["app"][0]
    destination_address_prefix = var.address_prefixes["db"][0]
  }
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.this["db"].id
  network_security_group_id = azurerm_network_security_group.db.id
}

provider "azurerm" {
  features {}
}

