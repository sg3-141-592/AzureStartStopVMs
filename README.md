This script starts and stops VMs based on cron schedules specified tags on the VMs.
This script runs as an Azure Automation runbook.

For example:

`automation_start: * 8 * * 1-5`
and
`automation_stop: * 18 * * 1-5`

Current Functionality

- Start and stop VMs based on tags

Future Roadmap

- Start and stop VMs based on a sequence tag in the resource group. For example `sequence_start: 2`, `sequence_stop: 2`
- Resize PaaS SQL DTUs on a tagged schedule
- Self-service start-up of groups of resources for developers.