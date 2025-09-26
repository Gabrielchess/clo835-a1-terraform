# CLO835 IaC (Terraform)

Creates:
- ECR repos: `clo835-webapp`, `clo835-mysql`
- EC2 (Amazon Linux 2023) with SGs
- ALB + target groups + path rules (/blue, /pink, /lime)

## Usage
```bash
terraform init
terraform apply -auto-approve
terraform output
