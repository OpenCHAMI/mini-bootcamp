#!/bin/sh
set -e -o pipefail

# As configured in systemd, we expect to inherit the "ochami_ci_url" cmdline
# parameter as an env var. Exit if this is not the case.
if [ -z "${ochami_ci_url}" ];
then
    echo "ERROR: Failed to find the 'ochami_ci_url' environment variable."
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
echo "Found OpenCHAMI cloud-init URL '${ochami_ci_url}'"

# Write a cloud-config that points to the specified URL
config="$(</etc/cloud/cloud.cfg.d/ochami.cfg.template)"
echo -n "${config/SEEDFROM_URL_PLACEHOLDER/$ochami_ci_url}" > /etc/cloud/cloud.cfg.d/ochami.cfg
# NOTE: You'd think there would be a better way of doing non-regex string
# replacement, but there doesn't seem to be. Feel free to update this if you
# find one.
