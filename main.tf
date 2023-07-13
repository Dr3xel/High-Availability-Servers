terraform {
  required_providers {
    aws = {
    source  = "hashicorp/aws"
    version = "~> 3.27"
    }
  }

    required_version = ">= 0.14.9"
}

provider "aws" {
    region = "eu-central-1"
}

data "aws_ami" "ubuntu" {
    most_recent = true
 
    filter {
      name = "name"
      values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
    }
 
    filter {
      name = "virtualization-type"
      values = ["hvm"]
    }
 
    owners = ["099720109477"] 
}

variable "public_subnet_cidrs" {
    type        = list(string)
    description = "Public Subnet CIDR values"
    default     = ["171.31.1.0/24", "171.31.2.0/24", "171.31.3.0/24"]
}

variable "azs" {
    type        = list(string)
    description = "Availability Zones"
    default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

resource "aws_vpc" "main" {
    cidr_block = "171.31.0.0/16"
    
    tags = {
      Name = "main"
    }
}

resource "aws_subnet" "public_subnets" {
    count             = length(var.public_subnet_cidrs)
    vpc_id            = aws_vpc.main.id
    cidr_block        = element(var.public_subnet_cidrs, count.index)
    availability_zone = element(var.azs, count.index)

    tags = {
        Name = "Public Subnet ${count.index + 1}"
        }
}

resource "aws_internet_gateway" "gw" {
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "project-ig"
    }
}

resource "aws_route_table" "main_rt" {
    vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
    }

    tags = {
        Name = "main-route"
    }
}

resource "aws_route_table_association" "public_subnet_asso" {
    count = length(var.public_subnet_cidrs)
    subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
    route_table_id = aws_route_table.main_rt.id
}


resource "aws_security_group" "project-sg" {
    name = "project-sg"
    vpc_id = aws_vpc.main.id
    description = "security group for project"
 
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
      to_port = 65535
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_launch_template" "launch_temp" {
    name = "tasktemp"
    image_id = data.aws_ami.ubuntu.id
    instance_type = "t2.micro"
    key_name = "YourKey"
    user_data = filebase64("nginx.sh")
    network_interfaces {
      associate_public_ip_address = true
      security_groups = [aws_security_group.project-sg.id]
      delete_on_termination = true 
    }
    lifecycle {
      create_before_destroy = true
    }
}


resource "aws_elb" "project-elb" {
    name = "ELB"
    security_groups = [aws_security_group.project-sg.id]
    subnets = aws_subnet.public_subnets[*].id
    
 
    listener {
      instance_port = 80
      instance_protocol = "http"
      lb_port = 80
      lb_protocol = "http"
    }
 
    health_check {
      healthy_threshold = 2
      unhealthy_threshold = 2
      timeout = 3
      target = "HTTP:80/"
      interval = 30
    }
   
    cross_zone_load_balancing = true
    idle_timeout = 400
    connection_draining = true
    connection_draining_timeout = 400
 
    tags = {
      Name = "project-elb"
    }
}

output "elb_dns" {
    value = aws_elb.project-elb.dns_name
}

resource "aws_autoscaling_group" "scaling-group" {
    vpc_zone_identifier = aws_subnet.public_subnets[*].id
    desired_capacity = 1
    max_size = 2
    min_size = 1
    load_balancers = [aws_elb.project-elb.id]
    launch_template {
    id      = aws_launch_template.launch_temp.id
    version = "$Default"
   }
 
    lifecycle {
      create_before_destroy = true
   }
}