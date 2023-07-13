#!/bin/bash

# Update packages and install the Nginx web server

sudo apt update
sudo apt install nginx -y

# Start and enable Nginx to automatically start at boot time

systemctl start nginx
systemctl enable --now nginx

