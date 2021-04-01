# Target Provider is AWS at region ap-southeast-1 (Singapore)
provider "aws" {
  region  = "ap-southeast-1"
}

# ECR
resource "aws_ecr_repository" "lab9_image_repo" {
  name = "lab9_image_repo"
}
