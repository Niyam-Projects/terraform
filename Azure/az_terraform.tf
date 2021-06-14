# add azure provider
provider "azurerm" {
  features {}
}


# create resource group
resource "azurerm_resource_group" "demo" {
  name     = "az-demo-rg"
  location = "East US 2"

  tags = {
    environment = "Demo"
  }
}

# security group for internet access - for the public instance
resource "azurerm_network_security_group" "web_dmz" {
  name                = "web_dmz"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  security_rule {
    name                       = "ingress 80"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    destination_address_prefix = "*"
    source_address_prefix      = "*"
  }
  security_rule {
    name                       = "ingress ssh"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    destination_address_prefix = "*"
    source_address_prefix      = "*"
  }
  security_rule {
    name                       = "egress all"
    priority                   = 102
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    destination_address_prefix = "*"
    source_address_prefix = "*"
  }
  tags = {
    environment = "Demo"
  }
}

# security group for private instance access - for the private instance
# access from public subnet
resource "azurerm_network_security_group" "internal_access_sg" {
  name                = "internal_access_sg"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  security_rule {
    name                       = "ingress ping"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    destination_address_prefix = "*"
    source_address_prefix      = "10.0.1.0/24"
  }
  security_rule {
    name                       = "ingress 80"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    destination_address_prefix = "*"
    source_address_prefix      = "10.0.1.0/24"
  }
  security_rule {
    name                       = "ingress 443"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    destination_address_prefix = "*"
    source_address_prefix      = "10.0.1.0/24"
  }
  security_rule {
    name                       = "ingress 3306"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    destination_address_prefix = "*"
    source_address_prefix      = "10.0.1.0/24"
  }
  security_rule {
    name                       = "egress all"
    priority                   = 104
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    destination_address_prefix = "*"
    source_address_prefix = "*"
  }
  tags = {
    environment = "Demo"
  }
}
# Create virutal network
resource "azurerm_virtual_network" "demo" {
  name                = "az-demo-vn"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  address_space       = ["10.0.0.0/16"]
  dns_servers         = ["10.0.0.4", "10.0.0.5"]

  tags = {
    environment = "Demo"
  }
}

resource "azurerm_subnet" "public_subnet" {
  name                 = "public_subnet"
  resource_group_name  =  azurerm_resource_group.demo.name
  address_prefixes       = ["10.0.1.0/24"]
  virtual_network_name = azurerm_virtual_network.demo.name
}
resource "azurerm_subnet" "private_subnet" {
  name                 = "private_subnet"
  resource_group_name  = azurerm_resource_group.demo.name
  address_prefixes       = ["10.0.4.0/24"]
  virtual_network_name = azurerm_virtual_network.demo.name
}

resource "azurerm_subnet_network_security_group_association" "public_subnet_assoc" {
  subnet_id                 = azurerm_subnet.public_subnet.id
  network_security_group_id = azurerm_network_security_group.web_dmz.id
}
resource "azurerm_subnet_network_security_group_association" "private_subnet_assoc" {
  subnet_id                 = azurerm_subnet.private_subnet.id
  network_security_group_id = azurerm_network_security_group.internal_access_sg.id
}

resource "azurerm_public_ip" "demo" {
  name                         = "public-ip"
  resource_group_name          = azurerm_resource_group.demo.name
  location                     = azurerm_resource_group.demo.location
  allocation_method            = "Dynamic"

  tags = {
      environment = "Demo"
  }
}  

resource "azurerm_network_interface" "web_facing_instance_nic" {
  name                = "web_facing_instance"
  resource_group_name          = azurerm_resource_group.demo.name
  location                     = azurerm_resource_group.demo.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.demo.id
  }
}

resource "azurerm_linux_virtual_machine" "web_facing_instance" {
  name                = "web-facing-instance"
  resource_group_name          = azurerm_resource_group.demo.name
  location                     = azurerm_resource_group.demo.location
  size                = "Standard_A1_v2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.web_facing_instance_nic.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}


resource "azurerm_network_interface" "internal_instance_nic" {
  name                = "internal_instance_nic"
  resource_group_name          = azurerm_resource_group.demo.name
  location                     = azurerm_resource_group.demo.location
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "internal_instance" {
  name                = "internal-instance"
  resource_group_name          = azurerm_resource_group.demo.name
  location                     = azurerm_resource_group.demo.location
  size                = "Standard_A1_v2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.internal_instance_nic.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}