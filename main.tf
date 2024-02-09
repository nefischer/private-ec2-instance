provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/24"
  enable_dns_support = true
  enable_dns_hostnames = true
}

# Create 3 private subnets
resource "aws_subnet" "my_private_subnet" {
  count                   = 3
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.my_vpc.cidr_block, 2, count.index)
  map_public_ip_on_launch = false
  availability_zone       = element(["us-east-1a", "us-east-1b", "us-east-1c"], count.index)
}

# Security Group for EC2 instance
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [aws_security_group.endpoint_service_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for VPC Endpoint Service
resource "aws_security_group" "endpoint_service_sg" {
  vpc_id = aws_vpc.my_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instance
resource "aws_instance" "my_instance" {
  ami           = "ami-123456" # Replace with a valid AMI for your region
  instance_type = "t2.micro"
  subnet_id     = element(aws_subnet.my_private_subnet.*.id, 0)
  security_groups = [aws_security_group.ec2_sg.name]

  tags = {
    Name = "MyInstance"
  }
}

# Network Load Balancer
resource "aws_lb" "my_nlb" {
  name               = "my-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.my_private_subnet.*.id
  enable_cross_zone_load_balancing = true
  vpc_id             = aws_vpc.my_vpc.id
}

# NLB Target Group
resource "aws_lb_target_group" "my_target_group" {
  name     = "my-target-group"
  port     = 22
  protocol = "TCP"
  vpc_id   = aws_vpc.my_vpc.id

  target_type = "instance"
}

# NLB Listener
resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.my_nlb.arn
  protocol          = "TCP"
  port              = 22

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}

# Register EC2 instance with the NLB target group
resource "aws_lb_target_group_attachment" "my_tg_attachment" {
  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id        = aws_instance.my_instance.id
  port             = 22
}

# VPC Endpoint Service connected to the NLB
resource "aws_vpc_endpoint_service" "my_endpoint_service" {
  acceptance_required       = false # or true, depending on whether you want to manually accept connection requests
  network_load_balancer_arns = [aws_lb.my_nlb.arn]

  # Tags
  tags = {
    Name = "MyVpcEndpointService"
  }
}
