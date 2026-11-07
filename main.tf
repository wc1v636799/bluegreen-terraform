terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  # Blue always gets the remainder so the two weights sum to 100 and the
  # listener rule never ends up with a zero total.
  blue_weight = 100 - var.green_weight

  tags = merge(var.tags, {
    managed_by = "bluegreen-terraform"
    rollout    = var.name
  })
}

resource "aws_lb_target_group" "blue" {
  name                 = "${var.name}-blue"
  port                 = var.blue_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = var.deregistration_delay

  health_check {
    path                = var.health_check_path
    interval            = var.health_check_interval
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = merge(local.tags, { fleet = "blue" })
}

resource "aws_lb_target_group" "green" {
  name                 = "${var.name}-green"
  port                 = var.green_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = var.deregistration_delay

  health_check {
    path                = var.health_check_path
    interval            = var.health_check_interval
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = merge(local.tags, { fleet = "green" })
}

resource "aws_lb_target_group_attachment" "blue" {
  for_each = toset(var.blue_instance_ids)

  target_group_arn = aws_lb_target_group.blue.arn
  target_id        = each.value
  port             = var.blue_port
}

resource "aws_lb_target_group_attachment" "green" {
  for_each = toset(var.green_instance_ids)

  target_group_arn = aws_lb_target_group.green.arn
  target_id        = each.value
  port             = var.green_port
}

resource "aws_lb_listener_rule" "rollout" {
  listener_arn = var.listener_arn
  priority     = var.priority

  action {
    type = "forward"

    forward {
      # Blocks are ordered: blue first, green second. Changing green_weight
      # only rewrites the weights, it does not replace the rule.
      target_group {
        arn    = aws_lb_target_group.blue.arn
        weight = local.blue_weight
      }

      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = var.green_weight
      }

      stickiness {
        enabled  = true
        duration = 300
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  tags = local.tags
}
