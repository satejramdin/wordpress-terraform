terraform {
  backend "s3" {
    bucket         = "tfstatesatej"
    key            = "global/s3/terraform.tfstate"
    region         = "eu-west-1"
      }
}