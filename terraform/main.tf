# ==========================================
# 1. プラグイン（Provider）の設定
# ==========================================
terraform {
  cloud {
    organization = "snowflake-training"
    workspaces {
      tags = ["training"]
    }
  }

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 1.0.0"
    }
  }
}

# ==========================================
# 2. Snowflakeへの接続設定
# ==========================================
provider "snowflake" {
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  role              = var.snowflake_role
  warehouse         = var.snowflake_warehouse
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = var.snowflake_private_key

  preview_features_enabled = [
    "snowflake_storage_integration_resource",
    "snowflake_file_format_resource",
    "snowflake_table_resource",
    "snowflake_stage_resource",
    "snowflake_pipe_resource"
  ]
}


