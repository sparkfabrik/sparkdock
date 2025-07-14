FROM mcr.microsoft.com/vscode/devcontainers/base:2.0-ubuntu24.04

RUN apt-get -y update && \
    apt-get install --no-install-recommends -y \
    apt-transport-https ca-certificates gnupg curl dnsutils file ansible

# Install the Google Cloud SDK
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    apt-get update -y && apt-get install google-cloud-cli -y --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

ARG USERNAME=vscode
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    && mkdir /commandhistory \
    && touch /commandhistory/.bash_history \
    && chown -R $USERNAME /commandhistory \
    && echo "$SNIPPET" >> "/home/$USERNAME/.bashrc"

# Set custom aliases.
RUN echo "alias dc=docker-compose" >> /etc/bash.bashrc
