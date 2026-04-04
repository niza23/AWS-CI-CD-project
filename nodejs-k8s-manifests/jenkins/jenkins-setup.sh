#!/bin/bash
# ============================================================
# Jenkins Setup Script for AWS EC2 (Ubuntu 22.04)
# Run as: sudo bash jenkins-setup.sh
# ============================================================
set -euo pipefail

echo "==> [1/7] System update"
apt-get update -y && apt-get upgrade -y

echo "==> [2/7] Install Java 17 (Jenkins requirement)"
apt-get install -y openjdk-17-jdk curl gnupg2 software-properties-common unzip

echo "==> [3/7] Install Jenkins"
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | \
  tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" | \
  tee /etc/apt/sources.list.d/jenkins.list > /dev/null
apt-get update -y
apt-get install -y jenkins
systemctl enable jenkins && systemctl start jenkins

echo "==> [4/7] Install Docker"
apt-get install -y docker.io
usermod -aG docker jenkins
usermod -aG docker ubuntu
systemctl enable docker && systemctl start docker

echo "==> [5/7] Install AWS CLI v2"
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

echo "==> [6/7] Install kubectl"
KUBECTL_VERSION=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
curl -fsSLO "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl /usr/local/bin/kubectl

echo "==> [7/7] Install Trivy (image vulnerability scanner)"
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key | \
  gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | \
  tee /etc/apt/sources.list.d/trivy.list
apt-get update -y && apt-get install -y trivy

echo ""
echo "======================================================"
echo " Jenkins is running on http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo " Initial admin password:"
cat /var/lib/jenkins/secrets/initialAdminPassword
echo "======================================================"
echo ""
echo "NEXT STEPS:"
echo "  1. Open Jenkins in browser and install suggested plugins"
echo "  2. Install additional plugins: AWS Steps, Docker Pipeline, SonarQube Scanner"
echo "  3. Add credentials: aws-credentials, github-token, ECR_REGISTRY"
echo "  4. Configure SonarQube server in Manage Jenkins > Configure System"
echo "  5. Create a Pipeline job pointing to your nodejs-app Jenkinsfile"
