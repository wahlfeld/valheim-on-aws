# valheim-on-aws

## todo

- write usage section
- don't include empty keys in admin list
- fix shellcheck and terraform validate pre commit checks?
- improve terratest e.g. ssm
- add lifecycle rule to s3 bucket

## Install dependencies
`make install`

## Usage
todo

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admins"></a> [admins](#input\_admins) | List of Valheim server admins (use their SteamID) | `map(any)` | `{}` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | The AWS region to create the Valheim server | `string` | n/a | yes |
| <a name="input_domain"></a> [domain](#input\_domain) | Domain name used to create a static monitoring URL | `string` | `""` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | AWS EC2 instance type to run the server on (t3a.medium is the minimum size) | `string` | `"t3a.medium"` | no |
| <a name="input_keybase_username"></a> [keybase\_username](#input\_keybase\_username) | The Keybase username to encrypt AWS user passwords with | `string` | n/a | yes |
| <a name="input_purpose"></a> [purpose](#input\_purpose) | The purpose of the deployment | `string` | `"prod"` | no |
| <a name="input_server_name"></a> [server\_name](#input\_server\_name) | The server name | `string` | n/a | yes |
| <a name="input_server_password"></a> [server\_password](#input\_server\_password) | The server password | `string` | n/a | yes |
| <a name="input_sns_email"></a> [sns\_email](#input\_sns\_email) | The email address to send alerts to | `string` | n/a | yes |
| <a name="input_unique_id"></a> [unique\_id](#input\_unique\_id) | The ID of the deployment (used for tests) | `string` | `""` | no |
| <a name="input_world_name"></a> [world\_name](#input\_world\_name) | The Valheim world name | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_monitoring_url"></a> [monitoring\_url](#output\_monitoring\_url) | n/a |
| <a name="output_valheim_user_passwords"></a> [valheim\_user\_passwords](#output\_valheim\_user\_passwords) | n/a |
<!-- END_TF_DOCS -->
