# bluegreen-terraform

Terraform module that splits ALB listener traffic between two identical target
groups. Deploys are just weight changes: 0 means the green fleet is dark, 10
means a canary, 100 means blue is retired. Nothing about the fleet itself is
managed here, so the module works with ASGs, EC2 instances or anything else
that can register into a target group.

Exists because hand-edited listener weights are the usual source of half
rolled-out deploys: someone sets 50/50, closes the laptop, and the split stays
that way for a week. Here the split is in code, reviewable, and reverting it is
a one-line diff.

## Install

```hcl
module "checkout_rollout" {
  source = "github.com/wc1v636799/bluegreen-terraform"

  name                = "checkout"
  vpc_id              = data.aws_vpc.main.id
  listener_arn        = aws_lb_listener.https.arn
  priority            = 210
  green_weight        = 0
  green_instance_ids  = module.checkout_green.instance_ids
  blue_instance_ids   = module.checkout_blue.instance_ids
  health_check_path   = "/healthz"
}
```

Requires Terraform >= 1.5 and AWS provider >= 5.0. The caller owns the VPC,
the listener and the capacity on both sides.

## Usage

Promote in steps, one apply per step:

```bash
terraform apply -var 'green_weight=10'   # canary, watch for 30 minutes
./scripts/check_shift.sh "$(terraform output -raw green_target_group_arn)"
terraform apply -var 'green_weight=50'
terraform apply -var 'green_weight=100'
```

`scripts/check_shift.sh` fails when the green group has no healthy targets or
its 5xx count over five minutes exceeds the threshold (default 0.01 absolute
count per minute bucket, pass a second argument to change it). Wire it into CI
between applies and the shift stops on its own.

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | string | required | Resource prefix, max 20 chars |
| `vpc_id` | string | required | VPC of both target groups |
| `listener_arn` | string | required | Listener the weighted rule attaches to |
| `priority` | number | `100` | Rule priority, must be unique on the listener |
| `green_weight` | number | `0` | Percent of traffic to green |
| `blue_port` | number | `8080` | Blue fleet port |
| `green_port` | number | `8080` | Green fleet port |
| `health_check_path` | string | `/healthz` | Probe path, must not touch dependencies |
| `health_check_interval` | number | `10` | Probe interval in seconds |
| `healthy_threshold` | number | `3` | Passing probes before healthy |
| `deregistration_delay` | number | `30` | Drain time in seconds |
| `blue_instance_ids` | list(string) | `[]` | Blue fleet members |
| `green_instance_ids` | list(string) | `[]` | Green fleet members |
| `tags` | map(string) | `{}` | Extra tags on every resource |

## Outputs

| Name | Description |
| --- | --- |
| `blue_target_group_arn` | Blue group, for external registration |
| `green_target_group_arn` | Green group, input for `check_shift.sh` |
| `listener_rule_arn` | Weighted rule, for alarms and audits |
| `traffic_split` | Effective weights after apply |

## Failure modes

- **Green is unhealthy at weight 0.** No traffic arrives, so nothing breaks,
  but the next shift sends requests into a black hole. Run the check script
  before every promote step.
- **Both weights land on zero.** Not possible through `green_weight` alone; it
  is validated to 0-100 and blue is the computed remainder. A partial apply
  that fails after the rule update but before attachments leaves weights
  correct and targets missing.
- **Deregistration delay too short.** At 30 seconds a slow request can be
  cut mid-flight on rollback. Raise it for streaming or upload-heavy services.
- **Rule priority collision.** The apply fails loudly; adjust `priority`
  rather than sharing a rule.
- **Green cert or port mismatch.** Health checks fail and the fleet never
  gains weight, which is the safe direction.

## Rollback

Set `green_weight = 0` and apply. Blue is already at the complementary weight,
so the revert is a single attribute and takes effect within one listener
propagation (seconds). Stickiness is capped at 300 seconds, so a client pinned
to green follows the old group for at most five minutes after the change. Only
destroy the green fleet once the blue group reports healthy and the 5xx rate
is flat for an hour.

## Layout

```
main.tf       target groups, attachments, weighted listener rule
variables.tf  inputs and validation
outputs.tf    ARNs and effective split
scripts/      shift gate used in CI
```

## Releasing

Weight changes only. Any change to the listener rule shape (stickiness,
ordering, conditions) is behavioural and needs a canary in a non-production
listener first.
