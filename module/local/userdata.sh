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

useradd -m ${username}
su - ${username} -c "mkdir -p /home/${username}/valheim"

aws s3 cp s3://${bucket}/install_valheim.sh /home/${username}/valheim/install_valheim.sh
aws s3 cp s3://${bucket}/bootstrap_valheim.sh /home/${username}/valheim/bootstrap_valheim.sh
aws s3 cp s3://${bucket}/valheim.service /home/${username}/valheim/valheim.service

chmod +x /home/${username}/valheim/install_valheim.sh
chmod +x /home/${username}/valheim/bootstrap_valheim.sh

chown ${username}:${username} /home/${username}/valheim/install_valheim.sh
chown ${username}:${username} /home/${username}/valheim/bootstrap_valheim.sh
chown ${username}:${username} /home/${username}/valheim/valheim.service

cp /home/${username}/valheim/valheim.service /etc/systemd/system

su - ${username} -c "bash /home/${username}/valheim/install_valheim.sh"

systemctl daemon-reload
systemctl enable valheim.service
systemctl restart valheim
