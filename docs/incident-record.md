# Workbook evidence and lifecycle record

Use real observations from your own run. The original issue references establish
failure patterns, not results from this deployment.

| Stage | Record |
| --- | --- |
| Incident | Workbook, cluster, first observed failure, affected control/data path, commander and authorized operator |
| Remediation | Targeted fix, alternative rejected, expected effect, rollback/stop condition, actual result |
| RCA | Proven mechanism, competing hypotheses, missing evidence, identity/network boundaries, access or ownership delays |
| Early warning | Signal that detects this mechanism, notification owner, missing-data behavior, test result |
| Fix in progress | Problem/change IDs, accountable engineering owner, product sponsor, access/vendor dependency, next milestone |
| Verification | Desired configuration AND observed recovery, current generation, preserved state/data, remaining uncertainty |
| Alert retirement | Temporary watch, replacement coverage/prevention test, receiving operator acknowledgment, retained steady-state monitoring |

If the normal operator is unreachable, use the published delegate and keep actions
within existing authority. If InfoSec denies broad access, request the minimum
diagnostic capability or an authorized operator. If product ownership changes,
transfer open corrective work and risk explicitly. A due date is a review/escalation
trigger, not permission for the last protection to expire silently.

The workbooks include CLI verification, not a deployed monitoring stack. Any
Prometheus/Alertmanager integration, metric exporters, production notification
routes, or automated alert retirement must be designed and authorized separately.
