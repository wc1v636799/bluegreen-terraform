output "blue_target_group_arn" {
  description = "ARN of the blue target group. Register rollback targets here if the fleet is managed elsewhere."
  value       = aws_lb_target_group.blue.arn
}

output "green_target_group_arn" {
  description = "ARN of the green target group."
  value       = aws_lb_target_group.green.arn
}

output "listener_rule_arn" {
  description = "ARN of the weighted listener rule, for alarm and audit wiring."
  value       = aws_lb_listener_rule.rollout.arn
}

output "traffic_split" {
  description = "Effective weights after this apply. Assert on it in CI before promoting further."
  value = {
    blue  = local.blue_weight
    green = var.green_weight
  }
}
