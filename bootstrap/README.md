# Bootstrap — State backend

Creates the resources Terraform itself needs to manage state remotely:

- **S3 bucket** for state files (versioning + KMS encryption enabled)
- **DynamoDB table** for state locking
- **KMS key** to encrypt state at rest

## Run once per AWS account

```sh
cd bootstrap

# 1. Apply with local state
terraform init
terraform apply

# 2. Migrate state to the bucket the bootstrap just created
# (uncomment backend.tf, then re-init)
terraform init -migrate-state
```

After migration the bootstrap stack manages itself — circular but
working pattern.

## Outputs (used by other environments)

- `state_bucket_name` — referenced in `environments/*/backend.tf`
- `state_lock_table_name`
- `state_kms_key_id`
