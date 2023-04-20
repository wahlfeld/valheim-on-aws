#!/bin/bash
set -e

echo "Backing up Valheim world data"

aws s3 cp "/home/${username}/.config/unity3d/IronGate/Valheim/worlds_local/${world_name}.fwl" s3://${bucket}/
aws s3 cp "/home/${username}/.config/unity3d/IronGate/Valheim/worlds_local/${world_name}.db" s3://${bucket}/
