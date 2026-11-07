variable "name" {
  description = "Prefix for every resource created by this module. Keep it short, the target group names are capped at 32 characters."
  type        = string

  validation {
    condition     = length(var.name) <= 20
    error_message = "name must be 20 characters or fewer so derived target group names stay under the 32 character limit."
  }
}

variable "vpc_id" {
  description = "VPC that owns both target groups."
  type        = string
}

variable "listener_arn" {
  description = "ARN of the HTTPS listener the weighted rule is attached to. The listener keeps its own default action."
  type        = string
}

variable "priority" {
  description = "Listener rule priority. Must not collide with other rules on the same listener."
  type        = number
  default     = 100
}

variable "blue_port" {
  description = "Traffic port of the blue (current) fleet."
  type        = number
  default     = 8080
}

variable "green_port" {
  description = "Traffic port of the green (candidate) fleet. Usually equal to blue_port, different only during migrations."
  type        = number
  default     = 8080
}

variable "green_weight" {
  description = "Percentage of traffic sent to green. 0 is a full rollback, 100 is a completed cutover."
  type        = number
  default     = 0

  validation {
    condition     = var.green_weight >= 0 && var.green_weight <= 100
    error_message = "green_weight must be between 0 and 100."
  }
}

variable "health_check_path" {
  description = "Path the load balancer probes on both fleets. Must return 200 without touching dependencies."
  type        = string
  default     = "/healthz"
}

variable "health_check_interval" {
  description = "Seconds between health probes."
  type        = number
  default     = 10
}

variable "healthy_threshold" {
  description = "Consecutive successful probes before a target is considered healthy."
  type        = number
  default     = 3
}

variable "deregistration_delay" {
  description = "Seconds to keep draining a target after it leaves the rotation. Long enough for in-flight requests, short enough to roll back quickly."
  type        = number
  default     = 30
}

variable "blue_instance_ids" {
  description = "Instances serving the blue fleet. Empty list is valid, for example after the blue fleet was retired."
  type        = list(string)
  default     = []
}

variable "green_instance_ids" {
  description = "Instances serving the green fleet."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags merged onto every taggable resource."
  type        = map(string)
  default     = {}
}
