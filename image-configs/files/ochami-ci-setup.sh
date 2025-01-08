#!/bin/sh
set -e -o pipefail

# As configured in systemd, we expect to inherit the "ochami_ci_url" cmdline
# parameter as an env var. Exit if this is not the case.
if [ -z "${ochami_wg_ip}" ];
then
    echo "ERROR: Failed to find the 'ochami_wg_url' environment variable."
    echo "It should be specified on the kernel cmdline, and will be inherited from there."
    if [ -f "/etc/cloud/cloud.cfg.d/ochami.cfg" ];
    then
        echo "Removing ochami-specific cloud-config; cloud-init will use other defaults"
        rm /etc/cloud/cloud.cfg.d/ochami.cfg
    else
        echo "Not writing ochami-specific cloud-config; cloud-init will use other defaults"
    fi
    exit 0
fi
echo "Found OpenCHAMI cloud-init URL '${ochami_wg_ip}'"
echo "!!!!Starting pre cloud-init config!!!!"

echo "Loading wireguard kernel mod"
modprobe wireguard

echo "Generating Wireguard keys"
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key

echo "Making Request to configure wireguard tunnel"
PUBLIC_KEY=$(cat /etc/wireguard/public.key)
PAYLOAD="{ \"public_key\": \"${PUBLIC_KEY}\" }"
WG_PAYLOAD=$(curl -s -X POST -d "${PAYLOAD}" http://${ochami_wg_ip}:27777/cloud-init/wg-init)

echo $WG_PAYLOAD | jq

CLIENT_IP=$(echo $WG_PAYLOAD | jq -r '."client-vpn-ip"')
SERVER_IP=$(echo $WG_PAYLOAD | jq -r '."server-ip"' | awk -F'/' '{print $1}')
SERVER_PORT=$(echo $WG_PAYLOAD | jq -r '."server-port"')
SERVER_KEY=$(echo $WG_PAYLOAD | jq -r '."server-public-key"')

echo "Setting up local wireguard interface"
ip link add dev wg0 type wireguard
ip address add dev wg0 ${CLIENT_IP}/16
wg set wg0 private-key /etc/wireguard/private.key
ip link set wg0 up
wg set wg0 peer ${SERVER_KEY} allowed-ips ${SERVER_IP}/32 endpoint ${ochami_wg_ip}:${SERVER_PORT}

echo "Setting cloud-init to use wireguard server"
ochami_ci_url="http://${SERVER_IP}:27777/cloud-init"
# Write a cloud-config that points to the specified URL
config="$(</etc/cloud/cloud.cfg.d/ochami.cfg.template)"
echo -n "${config/SEEDFROM_URL_PLACEHOLDER/$ochami_ci_url}" > /etc/cloud/cloud.cfg.d/ochami.cfg
# NOTE: You'd think there would be a better way of doing non-regex string
# replacement, but there doesn't seem to be. Feel free to update this if you
# find one.
