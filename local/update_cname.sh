#!/bin/bash

set -e

aws s3 cp s3://"${bucket}"/update_cname.json /home/vhserver/valheim/update_cname.json

PUBLIC_DNS=$(aws ec2 describe-instances --region "${aws_region}" --instance-ids $(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id) --query 'Reservations[].Instances[].PublicDnsName' | jq -r '.[]')

cat <<< $(jq --arg public_dns "$${PUBLIC_DNS}" '.Changes[0].ResourceRecordSet.ResourceRecords[0].Value = $public_dns' /home/vhserver/valheim/update_cname.json) > /home/vhserver/valheim/update_cname.json

aws route53 change-resource-record-sets --hosted-zone-id "${zone_id}" --change-batch file:///home/vhserver/valheim/update_cname.json

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'echo "\"$${last_command}\" command filed with exit code $?."' EXIT
