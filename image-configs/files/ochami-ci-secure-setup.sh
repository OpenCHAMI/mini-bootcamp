#!/bin/sh
set -e -o pipefail

output_dir="/var/run/cloud-init-data/"

# As configured in systemd, we expect to inherit the "ochami_ci_url_secure"
# cmdline parameter as an env var. Exit if this is not the case.
if [ -z "${ochami_ci_url_secure}" ];
then
    echo "ERROR: Failed to find the 'ochami_ci_url_secure' environment variable."
    echo "It should be specified on the kernel cmdline, and will be inherited from there."
    exit 2
fi
echo "Found secure OpenCHAMI cloud-init URL '${ochami_ci_url_secure}'"

# Fetch cloud-init config...
curl \
    "${ochami_ci_url_secure}{meta-data,user-data,vendor-data}" \
    --create-dirs --output "$output_dir#1" \
    --header "Authorization: Bearer $(</var/run/cloud-init-jwt)" \
    --location --fail
# ...and allow only root access
chmod -R go= "$output_dir"

# Write a cloud-config that points to the data we just downloaded
config="$(</etc/cloud/cloud.cfg.d/ochami.cfg.template)"
echo -n "${config/SEEDFROM_URL_PLACEHOLDER/file://$output_dir}" > /etc/cloud/cloud.cfg.d/ochami.cfg
# NOTE: You'd think there would be a better way of doing non-regex string
# replacement, but there doesn't seem to be. Feel free to update this if you
# find one.

# Run all relevant cloud-init stages with the new datasource
# NOTE: This is very non-ideal. Cloud-init does NOT want to run multiple times,
# so we need to clear its caches and rerun the relevant stages manually.
cloud-init clean
cloud-init init --local
cloud-init init
cloud-init modules --mode config
cloud-init modules --mode final
