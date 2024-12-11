

## Install and Enable libvirt

```bash
sudo dnf install -y libvirt qemu-kvm virt-install virt-manager dnsmasq

sudo systemctl enable --now libvirtd
sudo systemctl start libvirtd

sudo usermod -aG libvirt $(whoami)
newgrp libvirt
```

## Create the network.

Don't forget to change the boot file and server

```bash
cat <<EOF > pxe-test-net.xml
<network>
  <name>pxe-test-net</name>
  <bridge name="virbr-pxe" />
  <forward mode='nat'/>
  <ip address="192.168.100.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.100.10" end="192.168.100.100" />
      <bootp file="boot.ipxe" server="192.168.13.3"/>
    </dhcp>
  </ip>
</network>
EOF

sudo virsh net-define pxe-test-net.xml
sudo virsh net-start pxe-test-net
sudo virsh net-autostart pxe-test-net
```
## Ensure your artifacts are in place

```bash
tftp 192.168.13.3 -c get boot.ipxe
curl -O http://192.168.13.3/initramfs-5.14.0-503.15.1.el9_5.x86_64.img
curl -O http://192.168.13.3/rootfs-5.14.0-503.15.1.el9_5.x86_64.squashfs
curl -O http://192.168.13.3/vmlinuz-5.14.0-503.15.1.el9_5.x86_64
```

## Create and boot the VM

```bash
sudo virt-install   --name ipxe-test   --memory 4096   --vcpus 1   --disk none   --pxe   --os-variant generic   --network network:pxe-test-net,model=virtio   --boot network,hd  --nographics --tpm backend.type=emulator,backend.version=2.0,model=tpm-tis
```

### Useful to destroy and undefine for iterations
```bash
sudo virsh destroy ipxe-test && sudo virsh undefine ipxe-test
```

## Image Build Script

```bash
CNAME=$(buildah from scratch)
MNAME=$(buildah mount $CNAME)

dnf groupinstall -y --installroot=$MNAME --releasever=9 "Minimal Install"
dnf install -y --installroot=$MNAME kernel dracut-live fuse-overlayfs cloud-init nfs-utils kernel-modules

buildah run --tty $CNAME bash -c ' \
     dracut \
     --add "dmsquash-live-autooverlay dmsquash-live squash livenet network-manager nfs" \
     --kver $(basename /lib/modules/*) \
     -N \
     -f \
     '

OUTPUT_DIR=$(date +%Y%m%d)
rm -Rf $OUTPUT_DIR/*
KVER=$(ls $MNAME/lib/modules)

cp $MNAME/boot/initramfs-$KVER.img $OUTPUT_DIR
chmod o+r $OUTPUT_DIR/initramfs-$KVER.img
cp $MNAME/boot/vmlinuz-$KVER $OUTPUT_DIR
mksquashfs $MNAME $OUTPUT_DIR/rootfs-$KVER.squashfs -noappend -no-progress

cat <<EOF > $OUTPUT_DIR/boot.ipxe
#!ipxe

# Define the HTTP location where kernel and initrd are hosted
set base-url http://192.168.13.3:8080

# Set the kernel and initrd filenames
set kernel vmlinuz-$KVER
set initrd initramfs-$KVER.img
set rootfs rootfs-$KVER.squashfs

# Download the kernel
kernel $\{base-url}/$\{kernel} initrd=$\{initrd} root=live:$\{base-url}/$\{rootfs}  overlayroot=tmpfs,size=1G ro console=ttyS0,115200 rd.driver.pre=overlay rd.driver.pre=brd cloud-init=enabled ds=nocloud-net;s=${base-url} vm.overcommit_memory=1 selinux=0

# Download the initrd
initrd $\{base-url}/$\{initrd}

# Boot the downloaded kernel and initrd
boot
EOF
```

## Cloud-Init Notes

the nocloud client will request `meta-data` first.
if it succeeds, it will attempt `user-data` second.
if it succeeds, it will attempt `vendor-data`

When the same user is defined in both the user-data and the vendor-data in cloud-init, the user-data takes precedence. This behavior aligns with the principle that user-supplied configurations (like user-data) should override vendor defaults (like vendor-data).

vendor-data can contain a #include file which will subsequently download all the urls in it.

a single vendor-data (or user-data) can't have both #include and #cloud-config in the same file

Jinja templating can be used, but only in #cloud-config files if they have #template: jinja before the #cloud-config line

