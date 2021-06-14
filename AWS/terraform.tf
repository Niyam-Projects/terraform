terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}
# put variables in terraform.tfvars

variable "access_key" {
    description = "provide access key"

}

variable "secret_key" {
    description = "provide secret_key"
}

# To destroy: terraform destroy --auto-approve
# Configure the AWS Provider
provider "aws" {
  region = "us-east-2"
  access_key = var.access_key
  secret_key = var.secret_key
}


# Custom VPC
resource "aws_vpc" "internal_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "terraform-assets"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "custom_gw" {
  vpc_id = aws_vpc.internal_vpc.id
}

# public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.internal_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "terraform-assets"
  }
}

# private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.internal_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name = "terraform-assets"
  }
}

resource "aws_eip" "assign_eip" {
  vpc      = true
  depends_on  = [aws_internet_gateway.custom_gw]
}

# nat gateway allows private instance to download update
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.assign_eip.id
  subnet_id     = aws_subnet.public_subnet.id
  depends_on = [aws_internet_gateway.custom_gw]

  tags = {
    Name = "terraform-gw-NAT"
  }
}

# private route table using nat_gateway
resource "aws_route_table" "custom_private_routeTB" {
  vpc_id = aws_vpc.internal_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = {
    Name = "terraform-routeTable-private"
  }
}

# route table associate with the vpc
resource "aws_route_table" "custom_public_routeTB" {
  vpc_id = aws_vpc.internal_vpc.id  

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.custom_gw.id
  } 
  tags = {
    Name = "terraform-routeTable-public"
  }
}

resource "aws_route_table_association" "routeTB_public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.custom_public_routeTB.id
}


resource "aws_route_table_association" "routeTB_private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.custom_private_routeTB.id
}

# security group for internet access - for the public instance
resource "aws_security_group" "web_dmz" {
  name = "web_dmz"
  description = "Web Security Group"
  vpc_id      = aws_vpc.internal_vpc.id
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }    
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# security group for private instance access - for the private instance
# access from public subnet
resource "aws_security_group" "internal_access_sg" {
  name = "internal_access_sg"
  description = "For Private Subnet Security Group"
   vpc_id      = aws_vpc.internal_vpc.id
   ingress {
    from_port = 0
    to_port = 0
    protocol = "icmp"
    cidr_blocks = ["10.0.1.0/24"]
  }
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }
   ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }
   ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }
   egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



# public instance
resource "aws_instance" "web_facing_instance" {
  ami           = "ami-0d8d212151031f51c"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [ aws_security_group.web_dmz.id]
   key_name   = "jenkins-keypair"
  tags = {
    Name = "terraform-web-facing-instance"
  }
}

# private instance
resource "aws_instance" "private_ec2_instance" {
  ami           = "ami-0d8d212151031f51c"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.private_subnet.id
  vpc_security_group_ids = [ aws_security_group.internal_access_sg.id]
   key_name   = "jenkins-keypair"
  tags = {
    Name = "terraform-internal-ec2-instance"
  }
}