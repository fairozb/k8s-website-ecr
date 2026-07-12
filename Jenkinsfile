// ============================================================
// Jenkins CI/CD pipeline for the k8s-website-ecr project.
//
// Trigger : automatically on every push to GitHub (webhook).
// Flow    : checkout -> terraform (infra) -> build image -> push to ECR
//           -> deploy to k3s -> verify. Emails the result to Gmail.
//
// AWS auth: uses the Jenkins EC2 instance's IAM role (no stored keys).
// Only two things are configured in Jenkins (done automatically by the
// jenkins-server bootstrap via JCasC):
//   - ec2-ssh-key : SSH private key for the k3s EC2 instance
//   - SMTP + NOTIFY_EMAIL for Gmail notifications
// Required agent tools (pre-installed by the bootstrap): terraform,
// docker, awscli, kubectl, ssh, curl.
// ============================================================

pipeline {
  agent any

  parameters {
    booleanParam(name: 'APPLY_INFRA', defaultValue: true,
                 description: 'Run terraform apply for infrastructure (ECR, IAM, EC2).')
    string(name: 'IMAGE_TAG', defaultValue: '',
           description: 'Image tag to deploy. Leave blank to use the build number.')
  }

  environment {
    AWS_REGION   = 'ap-south-1'
    PROJECT      = 'k8s-website-ecr'
    TF_DIR       = '.'
    IMAGE_TAG    = "${params.IMAGE_TAG ?: 'build-' + env.BUILD_NUMBER}"
    NOTIFY_EMAIL = 'your-email@gmail.com'
  }

  triggers {
    githubPush()
    pollSCM('H/5 * * * *')
  }

  options {
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        echo "Building tag: ${env.IMAGE_TAG}"
      }
    }

    stage('Terraform Init & Validate') {
      steps {
        dir(env.TF_DIR) {
          sh '''
            terraform init -input=false
            terraform fmt -check -recursive
            terraform validate
          '''
        }
      }
    }

    stage('Terraform Plan') {
      when { expression { return params.APPLY_INFRA } }
      steps {
        dir(env.TF_DIR) {
          // Compute this Jenkins server's public IP so the app server's
          // security group allows Jenkins to SSH in for the deploy stage.
          sh '''
            MYIP=$(curl -s http://checkip.amazonaws.com || curl -s https://api.ipify.org)
            terraform plan -input=false -out=tfplan \
              -var="image_tag=${IMAGE_TAG}" \
              -var="key_name=terraform-docker-key" \
              -var="allowed_ssh_cidr=${MYIP}/32"
          '''
        }
      }
    }

    stage('Approve Infra Changes') {
      when { expression { return params.APPLY_INFRA } }
      steps {
        input message: 'Apply the Terraform plan to AWS?', ok: 'Apply'
      }
    }

    stage('Terraform Apply (Infra)') {
      when { expression { return params.APPLY_INFRA } }
      steps {
        dir(env.TF_DIR) {
          sh 'terraform apply -input=false tfplan'
        }
      }
    }

    stage('Build Docker Image') {
      steps {
        dir(env.TF_DIR) {
          script {
            env.ECR_URL = sh(script: 'terraform output -raw ecr_repository_url', returnStdout: true).trim()
          }
          sh 'docker build -t "$ECR_URL:$IMAGE_TAG" ./app'
        }
      }
    }

    stage('Push to ECR') {
      steps {
        sh '''
          REGISTRY=$(echo "$ECR_URL" | cut -d'/' -f1)
          aws ecr get-login-password --region "$AWS_REGION" \
            | docker login --username AWS --password-stdin "$REGISTRY"
          docker push "$ECR_URL:$IMAGE_TAG"
        '''
      }
    }

    stage('Deploy to Kubernetes (k3s)') {
      steps {
        withCredentials([
          sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')
        ]) {
          dir(env.TF_DIR) {
            script {
              env.EC2_IP = sh(script: 'terraform output -raw public_ip', returnStdout: true).trim()
            }
            sh '''
              ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" "$SSH_USER@$EC2_IP" bash -s <<EOF
                set -euxo pipefail
                export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
                # Wait until the new server has finished installing Docker + k3s.
                for i in \\$(seq 1 40); do
                  if command -v docker >/dev/null && sudo k3s kubectl get nodes >/dev/null 2>&1; then break; fi
                  echo "waiting for docker + k3s to be ready (\\$i)..."; sleep 15
                done
                REGISTRY=\\$(echo "$ECR_URL" | cut -d'/' -f1)
                aws ecr get-login-password --region "$AWS_REGION" | sudo docker login --username AWS --password-stdin "\\$REGISTRY"
                sudo docker pull "$ECR_URL:$IMAGE_TAG"
                sudo docker save "$ECR_URL:$IMAGE_TAG" -o /tmp/img.tar
                sudo k3s ctr images import /tmp/img.tar
                sudo k3s kubectl set image deployment/website website="$ECR_URL:$IMAGE_TAG" || \\
                  sudo k3s kubectl create deployment website --image="$ECR_URL:$IMAGE_TAG"
                sudo k3s kubectl rollout status deployment/website --timeout=180s
EOF
            '''
          }
        }
      }
    }

    stage('Verify') {
      steps {
        dir(env.TF_DIR) {
          script {
            def url = sh(script: 'terraform output -raw website_url', returnStdout: true).trim()
            echo "Checking ${url}"
            sh """
              for i in \$(seq 1 20); do
                if curl -fsS --max-time 5 "${url}" >/dev/null; then
                  echo "SUCCESS: site is live at ${url}"
                  exit 0
                fi
                echo "attempt \$i - not ready, waiting 15s"
                sleep 15
              done
              echo "Site did not become ready in time"
              exit 1
            """
          }
        }
      }
    }
  }

  post {
    success {
      emailext(
        to: "${env.NOTIFY_EMAIL}",
        subject: "BUILD SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
        body: """<p>Build <b>SUCCEEDED</b>.</p>
                 <ul>
                   <li>Job: ${env.JOB_NAME} #${env.BUILD_NUMBER}</li>
                   <li>Deployed image tag: ${env.IMAGE_TAG}</li>
                   <li>Logs: <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></li>
                 </ul>""",
        mimeType: 'text/html'
      )
    }
    failure {
      emailext(
        to: "${env.NOTIFY_EMAIL}",
        subject: "BUILD FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
        body: """<p>Build <b>FAILED</b>.</p>
                 <ul>
                   <li>Job: ${env.JOB_NAME} #${env.BUILD_NUMBER}</li>
                   <li>Check the console log: <a href="${env.BUILD_URL}console">${env.BUILD_URL}console</a></li>
                 </ul>""",
        mimeType: 'text/html'
      )
    }
    always {
      sh 'rm -f tfplan || true'
    }
  }
}
