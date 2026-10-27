# GCP: Petstore origin

Origin for the Petstore API Shield demo (`demo/petstore-api-shield/`). Creates a
Container-Optimized OS VM with no public IP running two containers on a private
Docker network:

- `swaggerapi/petstore3` (Swagger Petstore v3, port 8080, never exposed)
- `cloudflared`, connecting the remotely managed tunnel from `stacks/account/`

Cloud NAT provides egress. The only ingress rule allows SSH from IAP. The tunnel
token is read from the account stack's remote state, stored in Secret Manager,
and fetched by the VM's service account at boot.

Copy `backend.hcl.example` to `backend.hcl` and `terraform.tfvars.example` to
`terraform.tfvars` (both gitignored), then:

```sh
gcloud auth application-default login
terraform init -backend-config=backend.hcl
terraform apply
```

Debug the VM with the `ssh_command` output, then
`sudo journalctl -u petstore -u cloudflared`. See `GETTING_STARTED.md` at the
repository root.
