# IAM Role for pulling images
resource "aws_iam_role" "pull_image" {
  name               = "pull-ecr-image"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Assume role trust relationship
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role       = aws_iam_role.pull_image.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
