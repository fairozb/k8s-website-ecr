output "ecr_repository_url" {
  description = "Push your Docker image here before creating the server."
  value       = aws_ecr_repository.app.repository_url
}

output "public_ip" {
  description = "Public IP of the k3s server."
  value       = aws_instance.k3s.public_ip
}

output "website_url" {
  description = "Website URL (Kubernetes NodePort). Allow a few minutes after apply."
  value       = "http://${aws_instance.k3s.public_ip}:30001"
}

output "ssh_command" {
  description = "SSH into the server (replace the key path)."
  value       = "ssh -i <path-to-key.pem> ubuntu@${aws_instance.k3s.public_ip}"
}
