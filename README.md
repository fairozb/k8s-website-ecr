# Kubernetes Website on EC2 — image from ECR (production-like)

Same result as `k8s-website-terraform`, but the Docker image is stored in a private
registry (**Amazon ECR**) instead of being built on the server. This mirrors how real
teams work: build the image once, push it to a registry, and let servers pull it.

## Why this is closer to production

| | `k8s-website-terraform` | this (`k8s-website-ecr`) |
|---|---|---|
| Where the image is built | on the EC2 server, every boot | once, locally (or in CI), pushed to ECR |
| Image source | local `docker build` | private ECR registry |
| Auth to registry | n/a | EC2 **IAM role** (no stored keys) |
| Versioning | none | tagged images (`v1`, `v2`, ...) |
| Repeatable across servers | no (rebuilds each time) | yes (same image everywhere) |

## The flow (important: order matters)

Because the server pulls the image at boot, the image must exist in ECR **before**
the EC2 instance starts. So we apply in two stages:

```
1. Create the ECR repo         →  terraform apply -target=aws_ecr_repository.app
2. Build + push the image      →  .\build-and-push.ps1 -Tag v1
3. Create everything else       →  terraform apply
4. Verify the site is live      →  .\verify.ps1
```

> In a real setup, step 2 is done by a CI pipeline on every commit, and step 3 just
> updates the running image tag.

## Prerequisites

- AWS credentials configured (`aws configure`)
- Terraform installed
- **Docker Desktop running** (needed locally to build/push the image)
- An existing EC2 key pair; your public IP

## Step by step

```powershell
# 0. settings
cp terraform.tfvars.example terraform.tfvars
#    edit key_name and allowed_ssh_cidr

terraform init

# 1. create ONLY the ECR repository first
terraform apply -target=aws_ecr_repository.app

# 2. build the image and push it to ECR
.\build-and-push.ps1 -Tag v1

# 3. create the server (it pulls image v1 from ECR on boot)
terraform apply

# 4. check it's live (polls until ready)
.\verify.ps1
```

Then open the URL from `terraform output website_url`.

## Deploying a new version later

```powershell
.\build-and-push.ps1 -Tag v2
terraform apply -var="image_tag=v2"   # replaces the instance with the new image
```

## How the pieces fit

- **`aws_ecr_repository`** — the private registry that holds your image.
- **IAM role + instance profile** — lets the EC2 instance pull from ECR without any
  stored credentials (it authenticates as itself).
- **`user-data.sh.tftpl`** — on boot: installs k3s, logs in to ECR with the IAM role,
  pulls the image, imports it into k3s (containerd), and applies the manifests.
- **`build-and-push.ps1`** — the "CI step": builds and pushes the image.
- **`verify.ps1`** — polls the website URL until it returns HTTP 200.

## Files

```
k8s-website-ecr/
├── main.tf                 # provider, ECR, IAM role, firewall, EC2
├── variables.tf
├── outputs.tf
├── user-data.sh.tftpl      # boot script (pulls from ECR, deploys)
├── build-and-push.ps1      # build + push image to ECR
├── verify.ps1              # check the site is live
├── terraform.tfvars.example
└── app/                    # website + Dockerfile
    ├── index.html
    └── Dockerfile
```

## Tear down (stops charges)

```powershell
terraform destroy
```

`force_delete = true` on the ECR repo lets destroy remove it even if it still holds
images.

## Notes / simplifications

- Single-node k3s; NodePort exposes the app directly (no load balancer).
- The image is imported into k3s with `imagePullPolicy: Never`. A fuller setup would
  configure k3s to pull directly from ECR via a registry credentials helper.
- For a true CI/CD version, see the `terraform-docker-corporate` project (ALB + ASG + CI).
