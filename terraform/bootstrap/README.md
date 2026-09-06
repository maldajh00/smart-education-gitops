# Terraform state bootstrap

One-time setup that creates the GCS bucket every other Terraform root
(`environments/prod`, and any future environment) uses as its remote
state backend. Its own state is local (`terraform.tfstate`, gitignored)
— it cannot use the GCS backend it is itself responsible for creating.

Run once per project:

```bash
cd terraform/bootstrap
terraform init
terraform plan
terraform apply
```

After this, the bucket `smart-education-assignment-tfstate` exists with
versioning enabled (so a bad apply's prior state is recoverable) and
public access blocked. `environments/prod/backend.tf` points at it.

Nobody should need to run this again unless the bucket's own settings
change (retention, location, versioning policy) — day-to-day
infrastructure work happens in `environments/prod`, not here.
