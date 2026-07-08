# ==========================================
# スキーマ定義（SYSADMINで実行）
# ==========================================
resource "snowflake_schema" "training_raw" {
  database = snowflake_database.training_db.name
  name     = "RAW" # TODO:ハンドアウトを参照し、適切なスキーマ名を設定してください
  # S3から取り込んだメールの生データを保持するスキーマ。
  comment = "Raw mail data ingested from S3."
}

resource "snowflake_schema" "training_normalized" {
  database = snowflake_database.training_db.name
  name     = "NORMALIZED" # TODO:ハンドアウトを参照し、適切なスキーマ名を設定してください
  # 加工・正規化済みデータを保持するスキーマ。
  comment = "Processed data for Streamlit."
}


# ==========================================
# スキーマ定義（TODOアプリ用）
# ==========================================
resource "snowflake_schema" "training_raw_todo" {
  database = snowflake_database.training_db.name
  name     = "RAW_TODO" # TODO:ハンドアウトを参照し、適切なスキーマ名を設定してください
  # S3から取り込んだメールの生データを保持するスキーマ。
  comment = "Raw mail data ingested from S3."
}

resource "snowflake_schema" "training_normalized_todo" {
  database = snowflake_database.training_db.name
  name     = "NORMALIZED_TODO" # TODO:ハンドアウトを参照し、適切なスキーマ名を設定してください
  # 加工・正規化済みデータを保持するスキーマ。
  comment = "Processed data for Streamlit."
}
# ==========================================
# スキーマへの権限付与
# ==========================================
resource "snowflake_grant_privileges_to_account_role" "training_schema_grants" {
  for_each = toset([
    "${snowflake_database.training_db.name}.${snowflake_schema.training_raw.name}",
    "${snowflake_database.training_db.name}.${snowflake_schema.training_normalized.name}",
    # TODOアプリ用スキーマ追加
    "${snowflake_database.training_db.name}.${snowflake_schema.training_raw_todo.name}",
    "${snowflake_database.training_db.name}.${snowflake_schema.training_normalized_todo.name}"
  ])
  account_role_name = var.snowflake_role_name
  privileges = [
    "USAGE",
    "MODIFY",
    "MONITOR",
    "CREATE TABLE",
    "CREATE STAGE",
    "CREATE PIPE",
    "CREATE TASK",
    "CREATE FILE FORMAT",
    "CREATE STREAM",
    "CREATE VIEW",
    "CREATE PROCEDURE",
    "CREATE STREAMLIT"
  ]
  on_schema {
    schema_name = each.value
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_schema_training" {
  account_role_name = var.snowflake_role_name
  privileges = [
    "USAGE",
    "MODIFY",
    "MONITOR",
    "CREATE TABLE",
    "CREATE STAGE",
    "CREATE PIPE",
    "CREATE TASK",
    "CREATE FILE FORMAT",
    "CREATE STREAM",
    "CREATE VIEW",
    "CREATE PROCEDURE",
    "CREATE STREAMLIT"
  ]
  on_schema {
    future_schemas_in_database = snowflake_database.training_db.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "training_wh_usage" {
  account_role_name = var.snowflake_role_name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.snowflake_warehouse
  }
}