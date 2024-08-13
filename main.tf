# Define the provider
provider "aws" {
  region = "eu-west-1"
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Create public subnets
resource "aws_subnet" "public" {
  count = 2
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.${count.index}.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
}
resource "aws_db_subnet_group" "main" {
  name       = "main-db-subnet-group"
  subnet_ids = aws_subnet.public[*].id

  tags = {
    Name = "Main DB Subnet Group"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# Create a route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

# Associate route table with public subnets
resource "aws_route_table_association" "a" {
  count = 2
  subnet_id = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

# Create security groups
resource "aws_security_group" "web" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port = 443
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

# Create RDS instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage = 20
  engine = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"
  db_name = "wordpressdb01"
  username = "admin"
  password = "password"
  vpc_security_group_ids = [aws_security_group.web.id]
  multi_az = true
  db_subnet_group_name = aws_db_subnet_group.main.name
}

# Create EC2 instances test
resource "aws_instance" "wordpress" {
  count = 2
  ami = "ami-0a2202cf4c36161a1" # Amazon Linux 2
  instance_type = "t3.micro"
  subnet_id = element(aws_subnet.public.*.id, count.index)
  security_groups = [aws_security_group.web.name]

  user_data = <<-EOF
                #!/bin/bash
                yum install -y httpd php php-mysqlnd
                systemctl start httpd
                systemctl enable httpd
                cd /var/www/html
                wget https://wordpress.org/latest.tar.gz
                tar -xzf latest.tar.gz
                mv wordpress/* .
                chown -R apache:apache /var/www/html/
                EOF

  tags = {
    Name = "WordPress-${count.index}"
  }
}

# Create an Application Load Balancer
resource "aws_lb" "wordpress_lb" {
  name = "wordpress-lb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.web.id]
  subnets = aws_subnet.public.*.id
}

# Create Target Group
resource "aws_lb_target_group" "wordpress_tg" {
  name = "wordpress-tg"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.main.id
  target_type = "instance"
}

# Attach instances to Target Group
resource "aws_lb_target_group_attachment" "a" {
  count = 2
  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id = element(aws_instance.wordpress.*.id, count.index)
  port = 80
}

# Create Listener
resource "aws_lb_listener" "wordpress" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port = "80"
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

# Route 53 setup
resource "aws_route53_zone" "primary" {
  name = "satetest.com"
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.primary.zone_id
  name = "www"
  type = "A"
  alias {
    name = aws_lb.wordpress_lb.dns_name
    zone_id = aws_lb.wordpress_lb.zone_id
    evaluate_target_health = true
  }
}
