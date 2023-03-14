#!/usr/bin/env bash
sudo chown terra:terra /entrypoint/*
chmod +x /entrypoint/*.sh
find /entrypoint/*.sh -maxdepth 1 -type f -exec {} \; | tee -a /var/log/cosmovisor/entrypoint.log