#!/bin/bash

dpkg --add-architecture i386
apt update
apt install -y ca-certificates awscli lib32gcc1 lib32stdc++6 libsdl2-2.0-0:i386
bash <(curl -Ss https://my-netdata.io/kickstart.sh)

useradd -m vhserver

su - vhserver -c "mkdir -p /home/vhserver/valheim"

tee -a /home/vhserver/valheim/install_valheim.sh <<EOF
#!/bin/bash
set -e

mkdir -p /home/vhserver/steam && cd /home/vhserver/steam || exit
curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -

/home/vhserver/steam/steamcmd.sh +login anonymous +force_install_dir /home/vhserver/valheim +app_update 896660 validate +quit

EOF

tee -a /home/vhserver/valheim/start_valheim.sh <<EOF
#!/bin/bash
set -e

export templdpath=$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=./linux64:$LD_LIBRARY_PATH
export SteamAppId=892970

echo "Checking if world exists on local storage"

test -f /home/vhserver/.config/unity3d/IronGate/Valheim/worlds/justadickwiggle.fwl || 
    { echo "No world .fwl file found on local storage, downloading most recent backup" ;
    aws s3 cp s3://wahlfeld-valheim/justadickwiggle.fwl /home/vhserver/.config/unity3d/IronGate/Valheim/worlds/justadickwiggle.fwl ; }

test -f /home/vhserver/.config/unity3d/IronGate/Valheim/worlds/justadickwiggle.db || 
    { echo "No world .db file found on local storage, downloading most recent backup" ;
    aws s3 cp s3://wahlfeld-valheim/justadickwiggle.db /home/vhserver/.config/unity3d/IronGate/Valheim/worlds/justadickwiggle.db ; }

echo "Syncing admin list"
aws s3 cp s3://wahlfeld-valheim/adminlist.txt /home/vhserver/.config/unity3d/IronGate/Valheim/adminlist.txt

echo "Starting server PRESS CTRL-C to exit"

# Tip: Make a local copy of this script to avoid it being overwritten by steam.
# NOTE: Minimum password length is 5 characters & Password cant be in the server name.
# NOTE: You need to make sure the ports 2456-2458 is being forwarded to your server through your local router & firewall.
./valheim_server.x86_64 -name "curtos big server" -port 2456 -world "justadickwiggle" -password "bigpenis" -batchmode -nographics -public 1

export LD_LIBRARY_PATH=$templdpath

EOF

tee -a /home/vhserver/valheim/valheim.service <<EOF
[Unit]
Description=Valheim Service
Wants=network-online.target
After=syslog.target network.target nss-lookup.target network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
Restart=on-failure
RestartSec=10
User=vhserver
Group=vhserver
WorkingDirectory=/home/vhserver/valheim
ExecStartPre=/home/vhserver/steam/steamcmd.sh +login anonymous +force_install_dir /home/vhserver/valheim +app_update 896660 +quit
ExecStart=/home/vhserver/valheim/start_valheim.sh
KillSignal=SIGINT

EOF

tee -a /home/vhserver/valheim/backup_valheim.sh <<EOF
#!/bin/bash
set -e

echo "Backing up Valheim world data"

aws s3 cp /home/vhserver/.config/unity3d/IronGate/Valheim/worlds/justadickwiggle.fwl s3://wahlfeld-valheim/
aws s3 cp /home/vhserver/.config/unity3d/IronGate/Valheim/worlds/justadickwiggle.db s3://wahlfeld-valheim/

EOF

chown vhserver:vhserver /home/vhserver/valheim/install_valheim.sh
chown vhserver:vhserver /home/vhserver/valheim/start_valheim.sh
chown vhserver:vhserver /home/vhserver/valheim/backup_valheim.sh
chown vhserver:vhserver /home/vhserver/valheim/valheim.service

chmod +x /home/vhserver/valheim/install_valheim.sh
chmod +x /home/vhserver/valheim/start_valheim.sh
chmod +x /home/vhserver/valheim/backup_valheim.sh
cp /home/vhserver/valheim/valheim.service /etc/systemd/system

su - vhserver -c "bash /home/vhserver/valheim/install_valheim.sh"

(crontab -l ; echo "@reboot sleep 300 && /home/vhserver/valheim/backup_valheim.sh") | su - vhserver -c "crontab -"
(crontab -l ; echo "@reboot sleep 3600 && /home/vhserver/valheim/backup_valheim.sh") | su - vhserver -c "crontab -"

systemctl daemon-reload
systemctl enable valheim.service
systemctl restart valheim
