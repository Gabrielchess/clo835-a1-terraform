terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ---------- Key pair (uses your Cloud9 public key) ----------
resource "aws_key_pair" "clo835" {
  key_name   = "clo835-key"                  # Name that will appear in EC2 console
  public_key = file("~/.ssh/id_ed25519.pub") # Your existing public key on Cloud9
}

# ---------- Networking ----------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ---------- ECR ----------
resource "aws_ecr_repository" "webapp" {
  name = "clo835-webapp"
}

resource "aws_ecr_repository" "mysql" {
  name = "clo835-mysql"
}

# ---------- Security Group (SSH + 8081/8082/8083) ----------
resource "aws_security_group" "ec2_sg" {
  name        = "clo835-ec2-sg"
  description = "Allow SSH and web ports"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = [8081, 8082, 8083]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- Use EXISTING IAM Role + Instance Profile ----------
# (From your screenshot: Role = LabRole, Instance profile = LabInstanceProfile)
data "aws_iam_role" "lab" {
  name = var.existing_iam_role_name
}

data "aws_iam_instance_profile" "lab_profile" {
  name = var.existing_instance_profile_name
}

# ---------- AMI ----------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["137112412989"] # Amazon

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-x86_64"]
  }
}

# ---------- EC2 ----------
resource "aws_instance" "app_host" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnets.default_public.ids[0]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.clo835.key_name
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  iam_instance_profile        = data.aws_iam_instance_profile.lab_profile.name

  # Root EBS volume (20 GB)
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = <<-BASH
    #!/bin/bash
    set -eux
    dnf update -y
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user
  BASH

  tags = { Name = "clo835-ec2" }
}


# --- ALB Security Group: allow HTTP from internet ---
resource "aws_security_group" "alb_sg" {
  name        = "clo835-alb-sg"
  description = "ALB inbound 80 from internet; egress anywhere"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# or add this extra rule set to limit traffic to those ports from the ALB only.
resource "aws_security_group_rule" "app_from_alb_808x" {
  for_each = toset(["8081","8082","8083"])
  type              = "ingress"
  security_group_id = aws_security_group.ec2_sg.id
  from_port         = tonumber(each.key)
  to_port           = tonumber(each.key)
  protocol          = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
}

# --- Application Load Balancer ---
resource "aws_lb" "app_alb" {
  name               = "clo835-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default_public.ids
}

# --- Three Target Groups (instance target, ports 8081/8082/8083) ---
resource "aws_lb_target_group" "blue" {
  name        = "tg-blue-8081"
  port        = 8081
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.default.id
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }
}

resource "aws_lb_target_group" "pink" {
  name        = "tg-pink-8082"
  port        = 8082
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }
}

resource "aws_lb_target_group" "lime" {
  name        = "tg-lime-8083"
  port        = 8083
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }
}

# --- Register your single EC2 instance in each TG ---
resource "aws_lb_target_group_attachment" "blue_ec2" {
  target_group_arn = aws_lb_target_group.blue.arn
  target_id        = aws_instance.app_host.id
  port             = 8081
}

resource "aws_lb_target_group_attachment" "pink_ec2" {
  target_group_arn = aws_lb_target_group.pink.arn
  target_id        = aws_instance.app_host.id
  port             = 8082
}

resource "aws_lb_target_group_attachment" "lime_ec2" {
  target_group_arn = aws_lb_target_group.lime.arn
  target_id        = aws_instance.app_host.id
  port             = 8083
}

# --- HTTP Listener on :80 with path-based rules ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  # default action: send to blue (can be anything)
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

resource "aws_lb_listener_rule" "route_blue" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  condition {
    path_pattern {
      values = ["/blue*", "/"]  # keep "/" here if you want blue for root
    }
  }
}

resource "aws_lb_listener_rule" "route_pink" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pink.arn
  }

  condition {
    path_pattern {
      values = ["/pink*"]
    }
  }
}

resource "aws_lb_listener_rule" "route_lime" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lime.arn
  }

  condition {
    path_pattern {
      values = ["/lime*"]
    }
  }
}
