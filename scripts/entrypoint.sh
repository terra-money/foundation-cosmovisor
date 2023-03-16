#!/usr/bin/env bash
sudo chown -R ubuntu:ubuntu /app/data
sudo chown ubuntu:ubuntu /entrypoint/*
chmod +x /entrypoint/*.sh
find /entrypoint/*.sh -maxdepth 1 -type f -exec {} \; | tee -a /var/log/cosmovisor/entrypoint.log