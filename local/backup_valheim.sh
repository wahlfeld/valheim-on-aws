#!/bin/bash
set -e

echo "Backing up Valheim world data"

aws s3 cp /home/${username}/.config/unity3d/IronGate/Valheim/worlds/justadickwiggle.fwl s3://${bucket}/
aws s3 cp /home/${username}/.config/unity3d/IronGate/Valheim/worlds/justadickwiggle.db s3://${bucket}/
