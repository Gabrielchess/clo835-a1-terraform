output "ec2_public_ip" {
  value = aws_instance.app_host.public_ip
}

output "ecr_webapp_url" {
  value = aws_ecr_repository.webapp.repository_url
}

output "ecr_mysql_url" {
  value = aws_ecr_repository.mysql.repository_url
}

output "instance_public_ip" {
  value = aws_instance.app_host.public_ip
}

output "alb_dns_name" {
  value = aws_lb.app_alb.dns_name
}
