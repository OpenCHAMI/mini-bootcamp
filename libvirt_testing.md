

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
sudo virt-install   --name ipxe-test   --memory 2048   --vcpus 1   --disk none   --pxe   --os-variant generic   --network network:pxe-test-net,model=virtio   --boot network,hd  --nographics
```



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
kernel ${base-url}/${kernel} initrd=${initrd} root=live:http://192.168.13.3:8080/${rootfs}  overlayroot=tmpfs ro console=ttyS0,115200 rd.driver.pre=overlay rd.driver.pre=brd cloud-init=enabled ds=nocloud-net seedfrom=http://192.168.13.17/cloud-init/

# Download the initrd
initrd \${base-url}/\${initrd}

# Boot the downloaded kernel and initrd
boot
EOF


## Not Needed?

mkdir -p $MNAME/etc/dracut.conf.d
echo 'add_drivers+=" overlay "' | tee $MNAME/etc/dracut.conf.d/overlay.conf
echo 'add_drivers+=" brd "' | tee $MNAME/etc/dracut.conf.d/brd.conf
mkdir -p $MNAME/usr/lib/dracut/hooks/pre-udev
echo '#!/bin/bash
modprobe overlay
modprobe brd
' > $MNAME/usr/lib/dracut/hooks/pre-udev/30-load-modules.sh
chmod +x $MNAME/usr/lib/dracut/hooks/pre-udev/30-load-modules.sh