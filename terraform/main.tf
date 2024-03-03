#####################################################
### Data resources
#####################################################
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}
data "aws_rds_engine_version" "postgresql" {
  engine  = "aurora-postgresql"
  version = "14.5"
}


#####################################################
### Local variables
#####################################################
locals {
  account_id = data.aws_caller_identity.current.account_id
  name   = "warp-app"
  dbname = "warpdb"

  vpc_cidr                     = "10.0.0.0/16"
  azs                          = slice(data.aws_availability_zones.available.names, 0, 3)
  preferred_maintenance_window = "sun:05:00-sun:06:00"

  container_name = "nginx"
  container_port = 80

  db_user = module.aurora_postgresql_v2.cluster_master_username
  db_password = module.aurora_postgresql_v2.cluster_master_password
  db_endpoint = module.aurora_postgresql_v2.cluster_endpoint
  db_name = module.aurora_postgresql_v2.cluster_database_name

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}


#####################################################
### RDS Postgres DB (Serverless)
#####################################################
module "aurora_postgresql_v2" {
  source = "./modules/rds"

  name              = "${local.name}-postgresqlv2"
  engine            = data.aws_rds_engine_version.postgresql.engine
  engine_mode       = "provisioned"
  engine_version    = data.aws_rds_engine_version.postgresql.version
  storage_encrypted = true
  master_username   = "root"
  master_password   = random_password.master.result
  manage_master_user_password = false
  database_name     = local.dbname

  vpc_id               = module.vpc.vpc_id
  db_subnet_group_name = module.vpc.database_subnet_group_name
  security_group_rules = {
    vpc_ingress = {
      cidr_blocks = module.vpc.private_subnets_cidr_blocks
    }
  }

  monitoring_interval = 60

  apply_immediately   = true
  skip_final_snapshot = true

  serverlessv2_scaling_configuration = {
    min_capacity = 0.5
    max_capacity = 2
  }

  instance_class = "db.serverless"
  instances = {
    one = {}
  }

  tags = local.tags
}


#####################################################
### DB password
#####################################################
resource "random_password" "master" {
  length  = 20
  special = false
}


#####################################################
### VPC
#####################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs              = local.azs
  public_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 3)]
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 6)]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = local.tags
}


#####################################################
### ECS Cluster
#####################################################
module "ecs_cluster" {
  source = "./modules/cluster"

  cluster_name = local.name

  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 50
        base   = 20
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 50
      }
    }
  }

  tags = local.tags
}


#####################################################
### ECS Service
#####################################################
module "ecs_service" {
  source = "./modules/service"

  name        = local.name
  cluster_arn = module.ecs_cluster.arn

  cpu    = 1024
  memory = 4096

  enable_execute_command = true

  # Container definitions
  container_definitions = {
    nginx = {
      cpu       = 512
      memory    = 1024
      essential = true
      image     = "${var.nginx_image_name}:${var.nginx_image_tag}"
      port_mappings = [
        {
          name          = local.container_name
          containerPort = local.container_port
          hostPort      = local.container_port
          protocol      = "tcp"
        }
      ]

      readonly_root_filesystem = false

      linux_parameters = {
        capabilities = {
          drop = [
            "NET_RAW"
          ]
        }
      }
      memory_reservation = 100
    }

    warp-app = {
      cpu       = 512
      memory    = 1024
      essential = true
      image     = "${var.app_image_name}:${var.app_image_tag}"
      environment = [{
          name = "WARP_DATABASE"
          value = "postgresql://${local.db_user}:${local.db_password}@${local.db_endpoint}:5432/${local.db_name}"
        },
        {
          name = "WARP_SECRET_KEY"
          value = random_password.api_key.result
        },
        {
          name = "WARP_DATABASE_INIT_SCRIPT"
          value = "[\"sql/schema.sql\",\"sql/sample_data.sql\"]"
        },
        {
          name = "WARP_LANGUAGE_FILE"
          value = "i18n/en.js"
        },
      ]

      readonly_root_filesystem = false

      linux_parameters = {
        capabilities = {
          drop = [
            "NET_RAW"
          ]
        }
      }
      memory_reservation = 100
    }
  }

  service_connect_configuration = {
    namespace = aws_service_discovery_http_namespace.this.arn
    service = {
      client_alias = {
        port     = local.container_port
        dns_name = local.container_name
      }
      port_name      = local.container_name
      discovery_name = local.container_name
    }
  }

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["ex_ecs"].arn
      container_name   = local.container_name
      container_port   = local.container_port
    }
  }

  subnet_ids = module.vpc.private_subnets
  security_group_rules = {
    alb_ingress_3000 = {
      type                     = "ingress"
      from_port                = local.container_port
      to_port                  = local.container_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb.security_group_id
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  service_tags = {
    "ServiceTag" = "Tag on service level"
  }

  tags = local.tags
}


#####################################################
### API Key
#####################################################
resource "random_password" "api_key" {
  length  = 20
  special = false
}


#####################################################
### Service Discovery
#####################################################
resource "aws_service_discovery_http_namespace" "this" {
  name        = local.name
  description = "CloudMap namespace for ${local.name}"
  tags        = local.tags
}


#####################################################
### Application Load Balancer
#####################################################
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name = local.name

  load_balancer_type = "application"

  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  enable_deletion_protection = false

  # Security Group
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  listeners = {
    ex_http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "ex_ecs"
      }
    }
  }

  target_groups = {
    ex_ecs = {
      backend_protocol                  = "HTTP"
      backend_port                      = local.container_port
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 5
        interval            = 30
        matcher             = "302"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      create_attachment = false
    }
  }

  tags = local.tags
}
