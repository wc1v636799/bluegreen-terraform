terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "name" {
  description = "Prefix for the alarm and any created topic."
  type        = string
}

variable "load_balancer_arn" {
  description = "ARN of the load balancer owning the watched target group."
  type        = string
}

variable "target_group_arn" {
  description = "Target group to watch. Normally the green group from the root module."
  type        = string
}

variable "max_5xx_per_min" {
  description = "Target 5xx responses per one minute period that counts as a breach."
  type        = number
  default     = 10
}

variable "evaluation_periods" {
  description = "Consecutive breaching periods before the alarm fires."
  type        = number
  default     = 2
}

variable "sns_topic_arn" {
  description = "Existing topic to notify. Empty creates a dedicated topic."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags merged onto every taggable resource."
  type        = map(string)
  default     = {}
}

locals {
  # ApplicationELB dimensions take the bare ARN suffix, not the full ARN.
  lb_dimension = replace(var.load_balancer_arn, "/^.*:loadbalancer//", "")
  tg_dimension = replace(var.target_group_arn, "/^.*:targetgroup//", "")

  create_topic = var.sns_topic_arn == ""
  topic_arn    = local.create_topic ? aws_sns_topic.alarm[0].arn : var.sns_topic_arn
}

resource "aws_sns_topic" "alarm" {
  count = local.create_topic ? 1 : 0
  name  = "${var.name}-rollout-abort"

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name        = "${var.name}-green-5xx"
  alarm_description = "Green target group for ${var.name} is serving 5xx; set green_weight = 0 and apply."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"
  statistic   = "Sum"

  dimensions = {
    LoadBalancer = local.lb_dimension
    TargetGroup  = local.tg_dimension
  }

  comparison_operator       = "GreaterThanThreshold"
  threshold                 = var.max_5xx_per_min
  period                    = 60
  evaluation_periods        = var.evaluation_periods
  treat_missing_data        = "notBreaching"
  insufficient_data_actions = []
  alarm_actions             = [local.topic_arn]

  tags = var.tags
}

output "alarm_arn" {
  description = "ARN of the rollback alarm."
  value       = aws_cloudwatch_metric_alarm.target_5xx.arn
}

output "sns_topic_arn" {
  description = "Topic receiving the alarm. Created by the module unless sns_topic_arn was set."
  value       = local.topic_arn
}
