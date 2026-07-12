# Push this project to your GitHub

Checklist to get `k8s-website-ecr` onto your GitHub account
(https://github.com/fairozb) so Jenkins can build it.

## 1. Create an empty repo on GitHub
- GitHub -> New repository -> name it `k8s-website-ecr`.
- Do **not** add a README/.gitignore/license (this folder already has them).
- Keep it public, or private (Jenkins can use your token for private repos).

## 2. Confirm secrets are ignored (they already are)
The `.gitignore` here already excludes `*.tfvars`, `*.pem`, `*.tfstate`, and
`.terraform/`. Double-check nothing sensitive is staged before the first push:
```powershell
git status
```
You should NOT see `terraform.tfvars` or any `.pem` in the list.

## 3. Initialize and push
Run these from inside the `k8s-website-ecr` folder:
```powershell
git init
git branch -M main
git add .
git commit -m "Initial commit: k8s website + Jenkins pipeline"
git remote add origin https://github.com/fairozb/k8s-website-ecr.git
git push -u origin main
```
If prompted to authenticate, use a GitHub Personal Access Token as the password
(GitHub no longer accepts your account password over HTTPS).

## 4. Point the Jenkins job at it
The `jenkins-server` project already sets `repo_url` to this repo. If you named the
repo differently, update `repo_url` in `jenkins-server/terraform.tfvars` to match.

## 5. Trigger the pipeline with a test change
```powershell
# make a visible change
Add-Content app/index.html "<p>edit test</p>"
git commit -am "test: trigger pipeline"
git push
```
The GitHub webhook (auto-created by Jenkins via your token) starts the build. Watch it
in the Jenkins UI, and check your Gmail for the SUCCESS/FAILED email.

## What each push does
```
push to main
   -> GitHub webhook -> Jenkins "k8s-website-ecr" job
   -> build image -> push to ECR -> deploy to k3s -> verify -> email
```

## Handy git commands
```powershell
git log --oneline -5      # recent commits
git remote -v             # confirm the remote URL
git status                # what's staged / untracked
```

## If you accidentally staged a secret
```powershell
git rm --cached terraform.tfvars   # unstage it (keeps the local file)
git commit -m "stop tracking secrets"
```
Then confirm it's listed in `.gitignore` (it is by default here).
