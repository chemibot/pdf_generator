provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "pdf_bucket" {
  bucket = var.bucket_name

  website {
    index_document = "index.html"
  }

  force_destroy = true
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "pdf-demo-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.pdf_bucket.bucket_regional_domain_name
    origin_id   = "s3-origin"

    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-origin"

    viewer_protocol_policy = "allow-all"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

resource "aws_ecr_repository" "pdf_api_repo" {
  name = "pdf-api"
}

resource "aws_ecs_cluster" "pdf_cluster" {
  name = "pdf-cluster"
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_s3_access" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_s3" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}


resource "aws_ecs_task_definition" "pdf_task" {
  family                   = "pdf-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn = aws_iam_role.ecs_task_role.arn
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "pdf-api"
      image     = "337909777634.dkr.ecr.eu-west-1.amazonaws.com/pdf-api:latest"
      essential = true
      portMappings = [{
        containerPort = 5000
        hostPort      = 5000
      }],
      environment = [
        { name = "S3_BUCKET", value = var.bucket_name },
        { name = "CLOUDFRONT_DOMAIN", value = aws_cloudfront_distribution.cdn.domain_name },
        { name = "AWS_REGION", value = var.region }
      ]
    }
  ])
}

resource "aws_ecs_service" "pdf_service" {
  name            = "pdf-service"
  cluster         = aws_ecs_cluster.pdf_cluster.id
  task_definition = aws_ecs_task_definition.pdf_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = ["subnet-07163a7a0f031b0de"]  
    security_groups = ["sg-04d889213d80ba899"]     
    assign_public_ip = true
  }
}