# valheim-on-aws

[![build](https://github.com/wahlfeld/valheim-on-aws/actions/workflows/build.yml/badge.svg)](https://github.com/wahlfeld/valheim-on-aws/actions/workflows/build.yml)

## Why does this project exist?

This project exists because I wanted a cheaper and more efficient way to host a
Valheim server. Using AWS and Terraform this project will create a single
Valheim server which is ready to join from the Valheim server browser. It will
automatically turn off after ~15 minutes of inactivity (saving you loads of
money), and you have the option of using the AWS app to turn it back on whenever
you want to play.

## Features

* Cheap (~$0.049 USD per hour)
* Updates
* Backups
* Alerts
* Monitoring (Netdata)
* Remote management (AWS app)

## Requirements

* MacOS required to run this code (or Linux, but will require some fiddling
  around)
* AWS account including CLI configured on your machine
* Terraform v1.4+

## Usage

1. Create a Terraform backend S3 bucket to store your state files
2. Copy and paste the `template` folder somewhere on your computer
3. Configure `terraform.tf` to point at the S3 bucket you just created
4. Create a file called `terraform.tfvars` as per the input descriptions in
   `inputs.tf` E.g.
```
aws_region       = "ap-southeast-2"    // Choose a region closest to your physical location
domain           = "fakedomain.com"    // (Optional) Used as the monitoring URL
keybase_username = "fakeusername"      // Use Keybase to encrypt AWS user passwords
sns_email        = "mrsmith@gmail.com" // Alert go here e.g. server started, server stopped
world_name       = "super cheap world"
server_name      = "super cheap server"
server_password  = "nohax"
admins = {
  "bob"   = 76561197993928955 // Create an AWS user for remote management and make Valheim admin using SteamID
  "jane"  = 76561197994340319
  "sally" = ""                // Create an AWS user for remote management but don't make Valheim admin
}
```
5. Run `terraform init && terraform apply`

### Example folder structure

```
valheim-on-aws           // (this project)
└── your-valheim-server  // (create me)
    ├── inputs.tf        // (copied from ./template)
    ├── main.tf          // (copied from ./template)
    ├── outputs.tf       // (copied from ./template)
    ├── terraform.tf     // (copied from ./template)
    └── terraform.tfvars // (create me, example above)
```

### Monitoring

To view server monitoring metrics visit the `monitoring_url` output from
Terraform after deploying. Note that this URL will change every time the server
starts unless you're using your own domain in AWS. In this case I find it's
easier to just take note of the public IP address when you turn the server on.

### Timings

* It usually takes around 1 minute for Terraform to deploy all the components
* Upon the first deployment the server will take 5-10 minutes to become ready
* Subsequent starts will take 2-3 minutes before appearing on the server browser

### Backups

The server logic around backups is as follows:

1. Check if world files exist locally and if so start the server using those
2. If no files exist, try to fetch from backup store and use those
3. If no backup files exist, create a new world and start the server
4. Five minutes after the server has started perform a backup
5. Perform backups every hour after boot

### Restores

todo

## Infracost

The following breakdown is an estimate based on the region `ap-southeast-2` and
the **monthly** cost. A more accurate estimate is the **hourly** cost since the
server is designed to shutdown automatically when not in use.

I.e. `35.74 * 12 / 52 / 7 / 24 =` **$0.049 USD per hour**

```
 Name                                                            Quantity  Unit                Monthly Cost

 module.main.aws_cloudwatch_metric_alarm.valheim_stopped
 └─ Standard resolution                                                 1  alarm metrics              $0.10

 module.main.aws_instance.valheim
 ├─ Instance usage (Linux/UNIX, on-demand, t3a.medium)                730  hours                     $34.67
 ├─ CPU credits                                           Cost depends on usage: $0.05 per vCPU-hours
 └─ root_block_device
    └─ Storage (general purpose SSD, gp2)                               8  GB-months                  $0.96

 module.main.aws_route53_record.valheim[0]
 ├─ Standard queries (first 1B)                           Cost depends on usage: $0.40 per 1M queries
 ├─ Latency based routing queries (first 1B)              Cost depends on usage: $0.60 per 1M queries
 └─ Geo DNS queries (first 1B)                            Cost depends on usage: $0.70 per 1M queries

 module.main.aws_s3_bucket.valheim
 └─ Standard
    ├─ Storage                                            Cost depends on usage: $0.03 per GB-months
    ├─ PUT, COPY, POST, LIST requests                     Cost depends on usage: $0.0055 per 1k requests
    ├─ GET, SELECT, and all other requests                Cost depends on usage: $0.00044 per 1k requests
    ├─ Select data scanned                                Cost depends on usage: $0.00225 per GB-months
    └─ Select data returned                               Cost depends on usage: $0.0008 per GB-months

 module.main.aws_sns_topic.valheim
 └─ Requests                                              Cost depends on usage: $0.50 per 1M requests

 PROJECT TOTAL                                                                                       $35.74
```
Source: Infracost v0.8.5 `infracost breakdown --path . --show-skipped --no-color`

## Install dependencies

* Terraform
* AWS CLI
* Docker
* Golang

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admins"></a> [admins](#input\_admins) | List of AWS users/Valheim server admins (use their SteamID) | `map(any)` | <pre>{<br>  "default_valheim_user": ""<br>}</pre> | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | The AWS region to create the Valheim server | `string` | n/a | yes |
| <a name="input_domain"></a> [domain](#input\_domain) | Domain name used to create a static monitoring URL | `string` | `""` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | AWS EC2 instance type to run the server on (t3a.medium is the minimum size) | `string` | `"t3a.medium"` | no |
| <a name="input_pgp_key"></a> [pgp\_key](#input\_pgp\_key) | The base64 encoded PGP public key to encrypt AWS user passwords with. Can use keybase syntax, e.g., 'keybase:username'. | `string` | `"keybase:marypoppins"` | no |
| <a name="input_purpose"></a> [purpose](#input\_purpose) | The purpose of the deployment | `string` | `"prod"` | no |
| <a name="input_s3_lifecycle_expiration"></a> [s3\_lifecycle\_expiration](#input\_s3\_lifecycle\_expiration) | The number of days to keep files (backups) in the S3 bucket before deletion | `string` | `"90"` | no |
| <a name="input_server_name"></a> [server\_name](#input\_server\_name) | The server name | `string` | n/a | yes |
| <a name="input_server_password"></a> [server\_password](#input\_server\_password) | The server password | `string` | n/a | yes |
| <a name="input_sns_email"></a> [sns\_email](#input\_sns\_email) | The email address to send alerts to | `string` | n/a | yes |
| <a name="input_unique_id"></a> [unique\_id](#input\_unique\_id) | The ID of the deployment (used for tests) | `string` | `""` | no |
| <a name="input_world_name"></a> [world\_name](#input\_world\_name) | The Valheim world name | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bucket_id"></a> [bucket\_id](#output\_bucket\_id) | The S3 bucket name |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | The EC2 instance ID |
| <a name="output_monitoring_url"></a> [monitoring\_url](#output\_monitoring\_url) | URL to monitor the Valheim Server |
| <a name="output_valheim_server_name"></a> [valheim\_server\_name](#output\_valheim\_server\_name) | Name of the Valheim server |
| <a name="output_valheim_user_passwords"></a> [valheim\_user\_passwords](#output\_valheim\_user\_passwords) | List of AWS users and their encrypted passwords |
<!-- END_TF_DOCS -->

## todo

- Add docs on performing restores
- Don't include empty keys in admin list
- Add tests, e.g., cron, cname update, etc
