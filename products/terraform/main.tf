resource "aws_dynamodb_table" "product_table" {
  name             = "product_table"
  hash_key         = "productId"
  billing_mode     = "PAY_PER_REQUEST"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "productId"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  global_secondary_index {
    name               = "category"
    hash_key           = "category"
    range_key          = "productId"
    projection_type    = "ALL"
  }
}