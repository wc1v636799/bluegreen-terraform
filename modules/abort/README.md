# abort - 5xx alarm for a rollout target group

Optional companion to the root module. It watches the green target group and
fires an SNS notification when target 5xx responses cross the threshold, so the
promote job (or whoever is on call) can return `green_weight` to 0 instead of
finding out from a dashboard an hour later.

The alarm does not change weights by itself. It notifies; the caller decides.
Automation that reacts to the topic must make the rollback apply idempotent,
because SNS delivers at least once.

## Usage

```hcl
module "checkout_abort" {
  source = "github.com/wc1v636799/bluegreen-terraform//modules/abort"

  name              = "checkout"
  load_balancer_arn = aws_lb.public.arn
  target_group_arn  = module.checkout_rollout.green_target_group_arn
  max_5xx_per_min   = 10
}
```

Point `sns_topic_arn` at an existing topic to reuse paging rules; leave it
empty and the module creates its own topic and returns the ARN.

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | string | required | Alarm name prefix |
| `load_balancer_arn` | string | required | ALB that owns the target group |
| `target_group_arn` | string | required | Group being watched, usually green |
| `max_5xx_per_min` | number | `10` | Breach threshold per one minute period |
| `evaluation_periods` | number | `2` | Consecutive breaching periods |
| `sns_topic_arn` | string | `""` | Existing topic, empty creates one |
| `tags` | map(string) | `{}` | Extra tags |

## Outputs

| Name | Description |
| --- | --- |
| `alarm_arn` | Created alarm, for dashboards |
| `sns_topic_arn` | Topic that receives the notification |

## Rollback behaviour

A breach means the green fleet is serving errors. Correct response is
`green_weight = 0` and apply; the alarm clears after `evaluation_periods` clean
periods. Delete the alarm only after the green fleet is retired, otherwise the
next rollout starts unwatched. Threshold of 10 per minute is roughly one 5xx
every six seconds, chosen so a single flaky health probe does not page.
