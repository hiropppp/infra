####################################################
# ECS Cluster
####################################################

resource "aws_ecs_cluster" "this" {
  name               = "${local.app_name}-app-cluster"
  capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
  }
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

####################################################
# ECS IAM Role
####################################################

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs_task_execution_role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
  ]
}

####################################################
# ECS Task Container Log Groups
####################################################

resource "aws_cloudwatch_log_group" "backend_app" {
  name              = "/ecs/${local.app_name}/backend/app"
  retention_in_days = 30
}

####################################################
# ECR data source
####################################################

locals {
  ecr_backend_app_repository_name        = "webapi"
}
/*
#todo refactor
data "external" "ecr_image_frontend_newest" {
  program = [
    "aws", "ecr", "describe-images",
    "--repository-name", local.ecr_frontend_repository_name,
    "--query", "{\"tags\": to_string(sort_by(imageDetails,& imagePushedAt)[-1].imageTags)}",
  ]
}
*/

data "external" "ecr_image_backend_app_newest" {
  program = [
    "aws", "ecr", "describe-images",
    "--repository-name", local.ecr_backend_app_repository_name,
    "--query", "{\"tags\": to_string(sort_by(imageDetails,& imagePushedAt)[-1].imageTags)}",
  ]
}

locals {
  ecr_backend_app_repository_newest_tags = jsondecode(data.external.ecr_image_backend_app_newest.result.tags)
}

data "aws_ecr_repository" "backend_app" {
  name = local.ecr_backend_app_repository_name
}

####################################################
# ECS Task Definition
####################################################
locals {
  backend_task_name = "${local.app_name}-app-task-backend"
  backend_task_app_container_name = "${local.app_name}-app-container-backend"
}

resource "aws_ecs_task_definition" "backend" {
  family                   = local.backend_task_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = jsonencode([
    {
      name             = local.backend_task_app_container_name
      image            = "${data.aws_ecr_repository.backend_app.repository_url}:${local.ecr_backend_app_repository_newest_tags[0]}"
      portMappings     = [{ containerPort : 80 }]
      secrets = [
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-region : "ap-northeast-1"
          awslogs-group : aws_cloudwatch_log_group.backend_app.name
          awslogs-stream-prefix : "ecs"
        }
      }
    }
  ])
}

####################################################
# ECS Cluster Service
####################################################

resource "aws_ecs_service" "backend" {
  name                               = "${local.app_name}-backend"
  cluster                            = aws_ecs_cluster.this.id
  platform_version                   = "LATEST"
  task_definition                    = aws_ecs_task_definition.backend.arn
  desired_count                      = 2
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  propagate_tags                     = "SERVICE"
  enable_execute_command             = true
  launch_type                        = "FARGATE"
  health_check_grace_period_seconds  = 300 /* これが長くないとタイムアウトになってしまう */
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    assign_public_ip = true
    subnets          = [
      aws_subnet.public_1c.id,
    ]
    security_groups = [
      aws_security_group.app.id,
    ]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = local.backend_task_app_container_name
    container_port   = 80
  }
}

resource "aws_lb_target_group" "backend" {
  name                 = "${local.app_name}-service-tg-backend"
  vpc_id               = aws_vpc.this.id
  target_type          = "ip"
  port                 = 80
  protocol             = "HTTP"
  deregistration_delay = 60
  health_check { path = "/greeting" }
}

resource "aws_lb_listener_rule" "backend" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 2
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
  condition {
    host_header {
      values = [local.api_domain_name]
    }
  }
}

resource "aws_lb_listener_rule" "maintenance" {
  listener_arn = aws_lb_listener.https.arn
  priority = 100
  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/html"
      message_body = local.maintenance_body
      status_code = "503"
    }
  }
  condition {
    path_pattern {
      values = ["*"]
    }
  }
}

####################################################
# AutoScaling Policy
####################################################
resource "aws_appautoscaling_target" "backend" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 2
  max_capacity       = 3
}

resource "aws_appautoscaling_policy" "backend_scale_out" {
  name               = "scale_out"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.backend.service_namespace
  resource_id        = aws_appautoscaling_target.backend.resource_id
  scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

resource "aws_appautoscaling_policy" "backend_scale_in" {
  name               = "scale_in"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.backend.service_namespace
  resource_id        = aws_appautoscaling_target.backend.resource_id
  scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}
####################################################
# CloudWatchメトリクスのアラーム
####################################################
resource "aws_cloudwatch_metric_alarm" "backend_cpu_high" {
  alarm_name          = "cpu_utilization_high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "75"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.backend.name
  }

  alarm_actions = [
    aws_appautoscaling_policy.backend_scale_out.arn
  ]
}

resource "aws_cloudwatch_metric_alarm" "backend_cpu_low" {
  alarm_name          = "cpu_utilization_low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "25"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.backend.name
  }

  alarm_actions = [
    aws_appautoscaling_policy.backend_scale_in.arn
  ]
}