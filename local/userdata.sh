#!/bin/bash

set -e

dpkg --add-architecture i386
apt update
apt install -y \
    autoconf \
    autoconf-archive \
    autogen \
    automake \
    awscli \
    ca-certificates \
    cmake \
    gcc \
    git \
    jq \
    lib32gcc1 \
    lib32stdc++6 \
    libelf-dev \
    libjson-c-dev \
    libjudy-dev \
    liblz4-dev \
    libmnl-dev \
    libsdl2-2.0-0:i386 \
    libssl-dev \
    libtool \
    libuv1-dev \
    make \
    pkg-config \
    uuid-dev \
    zlib1g-dev

bash <(curl -Ss https://my-netdata.io/kickstart.sh)

useradd -m vhserver

su - vhserver -c "mkdir -p /home/vhserver/valheim"

tee -a /home/vhserver/valheim/install_valheim.sh <<EOF
#!/bin/bash
set -e

mkdir -p /home/vhserver/steam && cd /home/vhserver/steam || exit
curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -

/home/vhserver/steam/steamcmd.sh +login anonymous +force_install_dir /home/vhserver/valheim +app_update 896660 validate +quit

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'echo "\"$${last_command}\" command filed with exit code $?."' EXIT

EOF

tee -a /home/vhserver/valheim/start_valheim.sh <<EOF
#!/bin/bash
set -e

%{ if use_domain ~}
echo "Updating cname"
aws s3 cp s3://wahlfeld-valheim/update_cname.json /home/vhserver/update_cname.json
aws s3 cp s3://wahlfeld-valheim/update_cname.sh /home/vhserver/update_cname.sh
bash /home/vhserver/update_cname.sh
%{ endif ~}

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

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'echo "\"$${last_command}\" command filed with exit code $?."' EXIT

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

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'echo "\"$${last_command}\" command filed with exit code $?."' EXIT

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
(crontab -l ; echo "@hourly && /home/vhserver/valheim/backup_valheim.sh") | su - vhserver -c "crontab -"

systemctl daemon-reload
systemctl enable valheim.service
systemctl restart valheim

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'echo "\"$${last_command}\" command filed with exit code $?."' EXIT
