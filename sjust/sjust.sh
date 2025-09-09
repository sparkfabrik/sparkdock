#!/usr/bin/env bash

# check if just is installed, otherwise install it with brew.
if ! command -v just &> /dev/null
then
    echo "just could not be found, installing it with brew"
    brew install just
fi

just --justfile /opt/sparkdock/sjust/Justfile "${@}"