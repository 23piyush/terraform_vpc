resource "aws_vpc" "myvpc" {
  cidr_block = var.cidr
}

resource "aws_subnet" "sub1" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.0.0/24" // within 10.0.0.0/16, what we defined in aws_vpc
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "sub2" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.1.0/24" // within 10.0.0.0/16, what we defined in aws_vpc
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id
}

resource "aws_route_table" "RT" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta1" {
  subnet_id      = aws_subnet.sub1.id
  route_table_id = aws_route_table.RT.id
}

resource "aws_route_table_association" "rta2" {
  subnet_id      = aws_subnet.sub2.id
  route_table_id = aws_route_table.RT.id
}

resource "aws_security_group" "websg" {
  name   = "web"
  vpc_id = aws_vpc.myvpc.id

  // Configure inbound and out-bound rules now

  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // [aws_vpc.main.cidr_block] , 0.0.0./0 means all can access
  }

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // [aws_vpc.main.cidr_block] , 0.0.0./0 means all can access
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "web-sg"
  }
}

resource "aws_s3_bucket" "example" {
  bucket = "mypiyush2023bucket1" // must be globally unique
}

resource "aws_instance" "webserver1" {
  ami                    = "ami-053b0d53c279acc90" // Open your aws account, create ec2, select "ubuntu" in ami and copy the ami id appeared
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.websg.id]
  subnet_id              = aws_subnet.sub1.id
  user_data              = base64encode(file("userdata.sh")) // Whenever we launch this ec2 instance, this script will run and install the software mentioned
}

resource "aws_instance" "webserver2" {
  ami                    = "ami-053b0d53c279acc90" // Open your aws account, create ec2, select "ubuntu" in ami and copy the ami id appeared
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.websg.id]
  subnet_id              = aws_subnet.sub2.id
  user_data              = base64encode(file("userdata1.sh")) // Whenever we launch this ec2 instance, this script will run and install the software mentioned
}

// create application load balancer
resource "aws_lb" "myalb" {
  name               = "myalb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.websg.id] // In practice, it's good to have different security groups, a seperate for accessing load 
  // balancer through ec2 instance
  subnets = [aws_subnet.sub1.id, aws_subnet.sub2.id]

  tags = {
    Name = "web"
  }
}

resource "aws_lb_target_group" "tg" {
  name     = "myTG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.myvpc.id
  health_check {
    path = "/"
    port = "traffic-port"
  }
}

resource "aws_lb_target_group_attachment" "lbtgattach1" {
  target_id        = aws_instance.webserver1.id
  target_group_arn = aws_lb_target_group.tg.arn
  port             = 80
}

resource "aws_lb_target_group_attachment" "lbtgattach2" {
  target_id        = aws_instance.webserver2.id
  target_group_arn = aws_lb_target_group.tg.arn
  port             = 80
}

resource "aws_lb_listener" "listener" { // to define that this particular target group should listen to this load-balancer
  load_balancer_arn = aws_lb.myalb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.tg.arn
    type             = "forward"
  }
}

output "loadbalancerdns" {
  value = aws_lb.myalb.dns_name
}