# ============================================================
# Builds the Docker image and pushes it to ECR.
# This is the step a CI pipeline would normally do.
# Run it AFTER the ECR repo exists (see README for the order).
#
# Requires: Docker Desktop running, AWS CLI configured.
# Usage:    .\build-and-push.ps1 -Tag v1
# ============================================================
param(
  [string]$Tag = "v1",
  [string]$Region = "ap-south-1"
)

$ErrorActionPreference = "Stop"

# Get the ECR repo URL from Terraform outputs.
$RepoUrl = terraform output -raw ecr_repository_url
if (-not $RepoUrl) { throw "Could not read ecr_repository_url. Did you run 'terraform apply' for the ECR repo first?" }

$Registry = $RepoUrl.Split("/")[0]

Write-Host "Logging in to ECR: $Registry"
aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $Registry

Write-Host "Building image $RepoUrl`:$Tag"
docker build -t "$RepoUrl`:$Tag" ./app

Write-Host "Pushing image"
docker push "$RepoUrl`:$Tag"

Write-Host "Done. Image pushed: $RepoUrl`:$Tag"
