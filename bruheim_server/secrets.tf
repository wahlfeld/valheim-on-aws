data "aws_ssm_parameter" "bruheim_server_password" {
	name = var.bruheim_server_password
	with_decryption = false
}