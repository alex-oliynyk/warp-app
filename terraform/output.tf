output "db-host" {
  value = module.aurora_postgresql_v2.cluster_endpoint
}

output "db-username" {
  value     = module.aurora_postgresql_v2.cluster_master_username
  sensitive = true
}

output "db-password" {
  value     = module.aurora_postgresql_v2.cluster_master_password
  sensitive = true
}

output "db-name" {
  value = module.aurora_postgresql_v2.cluster_database_name
}

output "alb-dns-name" {
  value = module.alb.dns_name
}
