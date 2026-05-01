terraform {
  backend "s3" {
    bucket         = "ruuvitag-serverless-tfstate-465118852707"
    key            = "home/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "ruuvitag-serverless-tflock"
    encrypt        = true
    kms_key_id     = "alias/ruuvitag-serverless-tfstate"
  }
}
