# Target Provider is AWS at region ap-southeast-1 (Singapore)
provider "aws" {
  region  = "ap-southeast-1"
}

# ECR
resource "aws_ecr_repository" "lab9_image_repo" {
  name = "lab9_image_repo"
}

# Network
resource "aws_default_vpc" "default_vpc" {
}

resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "ap-southeast-1a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "ap-southeast-1b"
}

# ECS
resource "aws_ecs_cluster" "lab9_cluster" {
  name = "lab9_cluster" 
}

resource "aws_ecs_task_definition" "lab9_task" {
  family                   = "lab9-task"
  container_definitions    = <<DEFINITION
  [
    {
      "name": "lab9-container",
      "image": "${aws_ecr_repository.lab9_image_repo.repository_url}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # Stating that we are using ECS Fargate
  network_mode             = "awsvpc"    # Using awsvpc as our network mode as this is required for Fargate
  memory                   = 512         # Specifying the memory our container requires
  cpu                      = 256         # Specifying the CPU our container requires
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = "${aws_iam_role.ecsTaskExecutionRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_alb" "lab9_application_load_balancer" {
  name               = "lab9-lb" # Naming our load balancer
  load_balancer_type = "application"
  subnets = [ # Referencing the default subnets
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}"
  ]
  # Referencing the security group
  security_groups = ["${aws_security_group.lab9_load_balancer_security_group.id}"]
}

# Creating a security group for the load balancer:
resource "aws_security_group" "lab9_load_balancer_security_group" {
  ingress {
    from_port   = 80 # Allowing traffic in from port 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}

resource "aws_lb_target_group" "lab9_target_group" {
  name        = "lab9-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${aws_default_vpc.default_vpc.id}"
  health_check {
    matcher = "200,301,302"
    path = "/"
  }
}

resource "aws_lb_listener" "lab9_lb_listener" {
  load_balancer_arn = "${aws_alb.lab9_application_load_balancer.arn}"
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.lab9_target_group.arn}"
  }
}

# Creating a security group for the load balancer:
resource "aws_security_group" "lab9_service_security_group" {
  ingress {
    from_port   = 3000 # Allowing traffic in from port 80
    to_port     = 3000
    protocol    = "tcp"
    security_groups = ["${aws_security_group.lab9_load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}

resource "aws_ecs_service" "lab9_service" {
  name            = "lab9-service"
  cluster         = "${aws_ecs_cluster.lab9_cluster.id}"
  task_definition = "${aws_ecs_task_definition.lab9_task.arn}"
  launch_type     = "FARGATE"
  desired_count   = 3
  
  load_balancer {
    target_group_arn = "${aws_lb_target_group.lab9_target_group.arn}" # Referencing our target group
    container_name   = "lab9-container"
    container_port   = 3000
  }

  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}"]
    security_groups  = ["${aws_security_group.lab9_service_security_group.id}"]
    assign_public_ip = true
  }
}