provider "aws" {
    region = "ap-south-1"
    secret_key = var.aws_secret_key
    access_key = var.aws_access_key
  
}

variable "aws_access_key" {
    description = "AWS sign in access key"  
}

variable "aws_secret_key" {
    description = "AWS secret key for sign in to AWS account"
}
variable "key_name" {}
variable "vpc_cidr_block" {}
variable "env_prefix" {}
variable "subnet1_cidr_block" {}
variable "all_cidr" {}
variable "az1" {}
variable "az2" {}
variable "instance_type" {
	description = "Instance specs"	
}
variable "subnet2_cidr_block" {}

# [VPC (subnet)(IG)(RT)(SG(egress,ingress,association_RT)) , EC2 (AMI)(instance)]

## VPC creation

resource "aws_vpc" "myapp_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    "Name" = "${var.env_prefix}-vpc"
  }
}

## Subnet 1 creation

resource "aws_subnet" "myapp-subnet1" {
    cidr_block = var.subnet1_cidr_block
    vpc_id = aws_vpc.myapp_vpc.id
		availability_zone = var.az1
    tags = {
      "Name" = "${var.env_prefix}-subnet1"
    }
  
}

## Subnet 2 creation for HA 


resource "aws_subnet" "myapp-subnet2" {
    cidr_block = var.subnet2_cidr_block
    vpc_id = aws_vpc.myapp_vpc.id
		availability_zone = var.az2
    tags = {
      "Name" = "${var.env_prefix}-subnet2"
    }
  
}


## Internet Gateway creation

resource "aws_internet_gateway" "myapp-igw" {
    vpc_id = aws_vpc.myapp_vpc.id
    tags = {
      "Name" = "${var.env_prefix}-igw"
    }
  
}

## route table creation

resource "aws_route_table" "myapp-rt" {
    vpc_id = aws_vpc.myapp_vpc.id
    route {
        cidr_block = var.all_cidr
        gateway_id = aws_internet_gateway.myapp-igw.id
    }
    tags = {
      "Name" = "${var.env_prefix}-rt"
    }
  
}

## Route table association with subnet 1

resource "aws_route_table_association" "myapp-rt-asso-subnet1" {
    subnet_id = aws_subnet.myapp-subnet1.id
    route_table_id = aws_route_table.myapp-rt.id
  
}


resource "aws_route_table_association" "myapp-rt-asso-subnet2" {
    subnet_id = aws_subnet.myapp-subnet2.id
    route_table_id = aws_route_table.myapp-rt.id
  
}
## Security Group creation

resource "aws_security_group" "myapp-security-group" {
    vpc_id = aws_vpc.myapp_vpc.id
    description = "Allow SSH and HTTP traffic on EC2 instance"
		name = "myapp-sg-terraform"
    ingress  {
      cidr_blocks = [var.all_cidr]
      description = "SSH inbound rule for all sources"
      from_port = 22
      protocol = "TCP"      
      self = true
      to_port = 22
    } 
    ingress {
        cidr_blocks = [var.all_cidr]
				from_port = 8080
				to_port = 8080
				protocol = "TCP"
				self = true
				description = "HTTP rule on port 8080 for all sources"
    }
		egress {
			  cidr_blocks = [var.all_cidr]
				from_port = 0
				to_port = 0
				protocol = "-1"
				description = "Outbond traffic rule"
				prefix_list_ids = []
		}
		tags = {
			"Name" = "${var.env_prefix}-sg"
		}
  
}

## AWS LB creation 

resource "aws_lb" "myapp-lb" {
	security_groups = [aws_security_group.myapp-security-group.id]
	internal = false
	subnets = [aws_subnet.myapp-subnet1.id,aws_subnet.myapp-subnet2.id]
	tags = {
		"Name" = "${var.env_prefix}-lb"
		"type" = "application-${var.env_prefix}-lb"
	}	
}

## AWS LB listerner policy created 

resource "aws_lb_listener" "myapp-lb-ls" {
	load_balancer_arn = aws_lb.myapp-lb.arn
	port = "8080"
	protocol = "HTTP"
	default_action {
	  target_group_arn = aws_lb_target_group.myapp-lb-tg.arn
	  type = "forward"
	}
  
}

## AWS LB target group created 

resource "aws_lb_target_group" "myapp-lb-tg" {
	vpc_id = aws_vpc.myapp_vpc.id
	port = 8080
	protocol = "HTTP"
	Name = "myapp-lb-tg"
	target_type = "instance"
}

## AWS target group attachment with Instances 

### First instance 

resource "aws_lb_target_group_attachment" "myapp-lb-tg-1a" {
	target_group_arn  = aws_lb_target_group.myapp-lb-tg.arn
	port = 8080
	target_id = aws_instance.myapp-webserver-instance-1.id
  
}

### Second instance 

resource "aws_lb_target_group_attachment" "myapp-lb-tg-2a" {
	target_group_arn  = aws_lb_target_group.myapp-lb-tg.arn
	port = 8080
	target_id = aws_instance.myapp-webserver-instance-2.id
}

## Data fetch from AWS to get the ami info being used.

data "aws_ami" "myapp-ami" {
	most_recent = true
	owners = ["amazon"]
	filter {
		name = "name"
		values = ["amzn2-ami-hvm-*-x86_64-gp2"]
	}
	
}

## Creation of Ec2 instances {web servers with nginx container}

### First instance 

resource "aws_instance" "myapp-webserver-instance-1" {
	ami = data.aws_ami.myapp-ami.id
	instance_type = var.instance_type
	availability_zone = var.az1
	vpc_security_group_ids = [aws_security_group.myapp-security-group.id]
	subnet_id = aws_subnet.myapp-subnet1.id
	key_name = var.key_name
	associate_public_ip_address = true
	user_data = file("run-script.sh")
	tags = {
		"Name" = "${var.env_prefix}-webserver-instance-1"
		"role" = "${var.env_prefix}-webserver-1"
		"type" = "${var.env_prefix}-nginx-1"
	}	
}

### Second instance 

resource "aws_instance" "myapp-webserver-instance-2" {

	ami = data.aws_ami.myapp-ami.id
	instance_type = var.instance_type
	availability_zone = var.az2
	vpc_security_group_ids = [aws_security_group.myapp-security-group.id]
	subnet_id = aws_subnet.myapp-subnet2.id
	key_name = var.key_name
	associate_public_ip_address = true
	user_data = file("run-script.sh")

	tags = {
		"Name" = "${var.env_prefix}-webserver-instance-2"
		"role" = "${var.env_prefix}-webserver-2"
		"type" = "${var.env_prefix}-nginx-2"
	}	
}



## OUTPUT Info

### VPC ID 

output "myapp_vpc_id" {
    value = aws_vpc.myapp_vpc.id
  
}

### Subnet ID 

output "myapp-subnet1_id" {
    value = aws_subnet.myapp-subnet1.id
  
}

### AMI ID 

output "myapp-ami" {
	value = data.aws_ami.myapp-ami.id
}

/*
output "myapp-webserver-instance-info" {
	value = aws_instance.myapp-webserver-instance.id	
}
*/

### Public IP of first instance 

output "myapp-webserver-instance-1-publicIP" {
	value = aws_instance.myapp-webserver-instance-1.public_ip
}

### Public IP of second instance

output "myapp-webserver-instance-2-publicIP" {
	value = aws_instance.myapp-webserver-instance-2.public_ip
}

output "lb-dns-name" {
  value = aws_lb.myapp-lb.dns_name
}