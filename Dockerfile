FROM python:3.11-slim-buster

ARG TF_VERSION

RUN pip install --upgrade pip \
    pip install checkov \
    pip install pre-commit==2.21.0

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    shellcheck \
    unzip && \
    rm -rf /var/lib/apt/lists/*

RUN curl -LO https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip && \
    unzip terraform_${TF_VERSION}_linux_amd64.zip -d /usr/local/bin  && \
    rm terraform_${TF_VERSION}_linux_amd64.zip

RUN curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

RUN curl -LO https://github.com/minamijoyo/tfupdate/releases/download/v0.6.7/tfupdate_0.6.7_linux_amd64.tar.gz && \
    tar -xzf tfupdate_0.6.7_linux_amd64.tar.gz -C /usr/local/bin && \
    rm tfupdate_0.6.7_linux_amd64.tar.gz

WORKDIR /workdir/
RUN git config --global --add safe.directory /workdir
