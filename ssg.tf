data "aws_ami" "amzn2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-*-hvm-2.0*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"] # Canonical
}

resource "aws_security_group" "tf-asg-sg" {
  name        = "tf-asg-sg"
  description = "Allow web-asg inbound traffic"
  vpc_id      = aws_vpc.vpc-10-0-0-0.id
  
  ingress {
    description      = "tf-asg-sg from VPC"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "tf-asg-sg"
  }
}

resource "aws_security_group" "tf-asg-alb-sg" {
  name        = "tf-asg-alb-sg"
  description = "Allow ALB inbound traffic" 
  vpc_id      = aws_vpc.vpc-10-0-0-0.id

  ingress {
    description      = "tf-asg-alb-sg from VPC"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tf-asg-alb-sg"
  }
}

resource "aws_lb" "tf-asg-alb" {
  name               = "tf-asg-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.tf-asg-alb-sg.id]
  subnets            = [aws_subnet.sub-pub1-10-0-1-0.id, aws_subnet.sub-pub2-10-0-2-0.id]

  enable_deletion_protection = false

  tags = { 
    Name = "tf-asg-alb"
  }
}

resource "aws_lb_target_group" "tf-asg-alb-tg" {
  name     = "tf-asg-alb-tg"
  port     = 80
  protocol = "HTTP"
  # target_type = "ip"
  vpc_id   = aws_vpc.vpc-10-0-0-0.id
  
  health_check {
  	enabled				= true
  	healthy_threshold	= 3
  	interval			= 5
  	matcher				= "200"
  	path				= "/"
  	port				= "traffic-port"
  	protocol			= "HTTP"
  	timeout				= 2
  	unhealthy_threshold	= 2
  }
}

resource "aws_lb_listener" "tf-asg-alb-ln" {
  load_balancer_arn = aws_lb.tf-asg-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tf-asg-alb-tg.arn
  }
}

resource "aws_launch_configuration" "as_conf" {
  name_prefix   = "terraform-lc-example-"
  image_id      = data.aws_ami.amzn2.id
  instance_type = "t2.micro"
  #iam_instance_profile = I don't know.
  security_groups = [aws_security_group.tf-asg-sg.id]
  key_name = "tf-key-pair-cloud9"
  user_data = file("./userdata.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "tf-asg" {
  name                      = "terraform-asg-example"
  max_size                  = 4
  min_size                  = 2
  health_check_grace_period = 5
  health_check_type         = "EC2"
  desired_capacity          = 2
  force_delete              = true
  launch_configuration      = aws_launch_configuration.as_conf.name
  vpc_zone_identifier       = [aws_subnet.sub-pri1-10-0-3-0.id, aws_subnet.sub-pri2-10-0-4-0.id]

  tag {
    key                 = "Name"
    value               = "tf-asg"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.tf-asg.id
  alb_target_group_arn   = aws_lb_target_group.tf-asg-alb-tg.arn
}
