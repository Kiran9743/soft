provider "aws" {
  access_key:"AKIAYS2NUPRPSTIERI4Y+p+G4BXzamiu"
  secret_key:"9NJ9uGwjxZ+3ZB0MRmh9JLPUSD5"
  region = "us-east-1"
}



variable "bucket_name" {
  default = "my-static-site-bucket-123456"  # Change to a globally unique name
}



resource "aws_s3_bucket" "static_site" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.static_site.bucket

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}



resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "S3-OAC"
  description                       = "OAC for S3 static site"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}


resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id   = "s3Origin"

    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3Origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}



data "aws_iam_policy_document" "s3_policy" {
  statement {
    sid     = "AllowCloudFrontServicePrincipal"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.static_site.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.static_site.id
  policy = data.aws_iam_policy_document.s3_policy.json
}



resource "aws_iam_user" "cicd_user" {
  name = "cicd-deploy-user"
}

resource "aws_iam_access_key" "cicd_access_key" {
  user = aws_iam_user.cicd_user.name
}

resource "aws_iam_policy" "s3_deploy_policy" {
  name = "S3StaticSiteDeployPolicy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        Effect   = "Allow",
        Resource = [
          aws_s3_bucket.static_site.arn,
          "${aws_s3_bucket.static_site.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "cicd_attach" {
  user       = aws_iam_user.cicd_user.name
  policy_arn = aws_iam_policy.s3_deploy_policy.arn
}



output "s3_bucket_name" {
  value = aws_s3_bucket.static_site.bucket
}

output "cloudfront_url" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "cicd_access_key_id" {
  value     = aws_iam_access_key.cicd_access_key.id
  sensitive = true
}

output "cicd_secret_access_key" {
  value     = aws_iam_access_key.cicd_access_key.secret
  sensitive = true
}
