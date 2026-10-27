# Zone stacks

Create one Terraform root and HCP Terraform workspace per zone. Each zone stack
owns resources scoped to that zone; account-scoped resources stay in
`stacks/account/`.

Name workspaces `cf-<account_id>-zone-<zone-name-with-dashes>` in Local
execution mode, keep the backend configuration in a local ignored `backend.hcl`,
and add the new root to the CI workflow matrix.
