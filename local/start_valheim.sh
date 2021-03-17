#!/bin/bash
set -e

echo "Syncing backup script"
aws s3 cp s3://${bucket}/backup_valheim.sh /home/${username}/valheim/backup_valheim.sh
chmod +x /home/${username}/valheim/backup_valheim.sh

echo "Setting crontab"
aws s3 cp s3://${bucket}/crontab /home/${username}/crontab
crontab < /home/${username}/crontab

echo "Preparing to start server"

%{ if use_domain ~}
echo "Updating cname"
aws s3 cp s3://${bucket}/update_cname.json /home/${username}/update_cname.json
aws s3 cp s3://${bucket}/update_cname.sh /home/${username}/update_cname.sh
bash /home/${username}/update_cname.sh
%{ endif ~}

export templdpath=$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=./linux64:$LD_LIBRARY_PATH
export SteamAppId=892970

echo "Checking if world exists on local storage"

test -f /home/${username}/.config/unity3d/IronGate/Valheim/worlds/justadickwiggle.fwl || 
    { echo "No world .fwl file found on local storage, downloading most recent backup" ;
    aws s3 cp s3://${bucket}/justadickwiggle.fwl /home/${username}/.config/unity3d/IronGate/Valheim/worlds/justadickwiggle.fwl ; }

test -f /home/${username}/.config/unity3d/IronGate/Valheim/worlds/justadickwiggle.db || 
    { echo "No world .db file found on local storage, downloading most recent backup" ;
    aws s3 cp s3://${bucket}/justadickwiggle.db /home/${username}/.config/unity3d/IronGate/Valheim/worlds/justadickwiggle.db ; }

echo "Syncing admin list"
aws s3 cp s3://${bucket}/adminlist.txt /home/${username}/.config/unity3d/IronGate/Valheim/adminlist.txt

echo "Starting server PRESS CTRL-C to exit"

# Tip: Make a local copy of this script to avoid it being overwritten by steam.
# NOTE: Minimum password length is 5 characters & Password cant be in the server name.
# NOTE: You need to make sure the ports 2456-2458 is being forwarded to your server through your local router & firewall.
./valheim_server.x86_64 -name "curtos big server" -port 2456 -world "justadickwiggle" -password "bigpenis" -batchmode -nographics -public 1

export LD_LIBRARY_PATH=$templdpath
