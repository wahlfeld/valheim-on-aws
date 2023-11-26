#!/bin/bash
set -e

echo "Syncing startup script"

aws s3 cp s3://${bucket}/start_valheim.sh /home/${username}/valheim/start_valheim.sh
chmod +x /home/${username}/valheim/start_valheim.sh

bash /home/${username}/valheim/start_valheim.sh
