# Jenkins CI/CD Setup

This guide configures Jenkins so that **pushing a change to GitHub automatically runs
the pipeline**, and **the build result is emailed to your Gmail**.

Your GitHub account: https://github.com/fairozb
The pipeline is defined in the `Jenkinsfile` at the repo root.

---

## The pipeline stages

| Stage | What it does |
|-------|--------------|
| Checkout | Pulls the latest code (triggered by your git push) |
| Terraform Init & Validate | `init`, `fmt -check`, `validate` |
| Terraform Plan | Previews infra changes |
| Approve Infra Changes | Manual gate before touching AWS |
| Terraform Apply (Infra) | Creates/updates ECR, IAM, EC2 |
| Build Docker Image | Builds the site image, tagged with the build number |
| Push to ECR | Pushes the image to your private registry |
| Deploy to Kubernetes (k3s) | SSHes to the server, imports the image, rolls the deployment |
| Verify | Polls the website URL until it returns HTTP 200 |
| post (email) | Emails SUCCESS/FAILURE to your Gmail |

> Tip: for pure app changes you can uncheck `APPLY_INFRA` so it skips the Terraform
> apply stages and just builds + deploys.

---

## Prerequisites

1. **A GitHub repo with this code.** Create one under your account and push:
   ```bash
   git init
   git remote add origin https://github.com/fairozb/k8s-website-ecr.git
   git add .
   git commit -m "initial"
   git push -u origin main
   ```
2. **Jenkins reachable from the internet** (so GitHub's webhook can reach it).
   If Jenkins runs on your laptop, expose it with a tunnel like `ngrok http 8080`
   and use the public URL below.
3. **Jenkins plugins installed:** Git, GitHub, Pipeline, Email Extension (`emailext`),
   Credentials Binding, AWS Credentials, SSH Agent.
4. **Agent tools on the Jenkins node:** terraform, docker, awscli, kubectl, ssh, curl.

---

## 1. Add credentials in Jenkins

Manage Jenkins -> Credentials -> (global) -> Add Credentials:

- **`aws-creds`** — kind "AWS Credentials" (or Username/Password with the access key
  as username and secret as password). Used by the Terraform, ECR, and deploy stages.
- **`ec2-ssh-key`** — kind "SSH Username with private key". Username `ubuntu`, and paste
  the contents of your `.pem` key. Used by the Deploy stage to reach the server.

These IDs must match the `credentialsId` values in the `Jenkinsfile`.

---

## 2. Create the pipeline job

1. New Item -> **Pipeline** -> name it `k8s-website-ecr`.
2. Under **Pipeline**, choose **Pipeline script from SCM**.
3. SCM: Git. Repository URL: `https://github.com/fairozb/k8s-website-ecr.git`.
   Add credentials if the repo is private.
4. Branch: `*/main`. Script Path: `Jenkinsfile`.
5. Under **Build Triggers**, tick **GitHub hook trigger for GITScm polling**.
6. Save.

---

## 3. Auto-trigger on git push (GitHub webhook)

This is what makes a push start the build automatically.

1. In GitHub: your repo -> **Settings -> Webhooks -> Add webhook**.
2. **Payload URL:** `http://<your-jenkins-url>/github-webhook/`
   (note the trailing slash; if using ngrok, use the https ngrok URL).
3. **Content type:** `application/json`.
4. **Events:** "Just the push event".
5. Add webhook. GitHub sends a test ping — a green check means it reached Jenkins.

Now every `git push` to `main` triggers the pipeline. The `triggers { githubPush() }`
block in the Jenkinsfile handles it, and `pollSCM('H/5 * * * *')` is a 5-minute fallback
if the webhook ever fails.

### Quick test
```bash
# edit the website
echo "<p>updated $(date)</p>" >> app/index.html
git commit -am "test: trigger pipeline"
git push
```
Watch the job start on its own in Jenkins.

---

## 4. Gmail build notifications

Gmail requires an **App Password** (not your normal password), and your account must
have 2-Step Verification enabled.

### Create a Gmail App Password
1. Google Account -> Security -> enable **2-Step Verification**.
2. Security -> **App passwords** -> generate one for "Mail". Copy the 16-character code.

### Configure Jenkins SMTP
Manage Jenkins -> System -> **Extended E-mail Notification**:
- SMTP server: `smtp.gmail.com`
- Advanced -> Use SSL: check, **SMTP Port: 465** (or STARTTLS on 587)
- Credentials: add Username/Password = your Gmail address + the **App Password**
- Default user email suffix: leave blank

Also set **Jenkins Location -> System Admin e-mail address** to your Gmail.

### Point the pipeline at your inbox
In the `Jenkinsfile`, change:
```groovy
NOTIFY_EMAIL = 'your-email@gmail.com'
```
to your actual Gmail address. The `post { success { ... } failure { ... } }` block
sends an HTML email with the result and a link to the logs after every build.

### Send a test email
Manage Jenkins -> System -> Extended E-mail Notification -> "Test configuration by
sending test e-mail". If it lands in your inbox, notifications are working.

---

## Troubleshooting

- **Webhook shows a red X in GitHub:** Jenkins isn't reachable from the internet.
  Use ngrok or host Jenkins on a public server, and re-check the Payload URL.
- **Build triggers but email never arrives:** wrong App Password, or port blocked.
  Try port 587 with STARTTLS. Check the test email first.
- **Deploy stage fails on SSH:** confirm `ec2-ssh-key` username is `ubuntu` and the
  security group allows SSH from the Jenkins machine's IP.
- **`terraform output` empty in Build stage:** the ECR repo must exist first — keep
  `APPLY_INFRA` checked on the initial run.
