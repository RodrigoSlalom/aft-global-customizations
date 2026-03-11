resource "aws_ssm_parameter" "param" {
  name  = "/test/global/parameter"
  value = "works!"
  type  = "String"
}