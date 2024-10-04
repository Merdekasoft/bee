#!/bin/bash

# Skrip untuk membuat atau memperbarui ISO Ubuntu Noble dengan KDE Neon User Edition

# Set variables
WORKDIR="/tmp/ubuntu-noble-iso"
CHROOTDIR="$WORKDIR/chroot"
MIRROR="http://archive.ubuntu.com/ubuntu"
NEON_REPO="https://archive.neon.kde.org/user"
DIST="noble"
ARCH="amd64"

# Pastikan dependensi yang dibutuhkan terpasang
sudo apt update
sudo apt install -y debootstrap squashfs-tools genisoimage isolinux syslinux-utils xorriso wget gnupg

# Buat direktori kerja jika belum ada
mkdir -p $WORKDIR
mkdir -p $CHROOTDIR

# Cek apakah debootstrap sudah dijalankan sebelumnya
if [ ! -d "$CHROOTDIR/proc" ]; then
    echo "Memulai debootstrap untuk Ubuntu Noble..."
    sudo debootstrap --arch=$ARCH $DIST $CHROOTDIR $MIRROR
else
    echo "Lingkungan debootstrap sudah ada, melanjutkan..."
fi

# Mount virtual filesystems hanya jika belum mounted
sudo mount --bind /dev $CHROOTDIR/dev
sudo mount --bind /proc $CHROOTDIR/proc
sudo mount --bind /sys $CHROOTDIR/sys

# Masuk ke chroot
sudo chroot $CHROOTDIR /bin/bash <<'EOF'
# Set environment
export LANG=C
export DEBIAN_FRONTEND=noninteractive

# Tambahkan repositori KDE Neon User jika belum ditambahkan
if ! grep -q "archive.neon.kde.org" /etc/apt/sources.list; then
    echo "Menambahkan repositori KDE Neon User..."
    echo "deb https://archive.neon.kde.org/user noble main" >> /etc/apt/sources.list

    # Tambahkan kunci GPG untuk KDE Neon User
    wget -qO - https://archive.neon.kde.org/public.key | apt-key add -
fi

# Update sistem
apt update

# Instal KDE Plasma dan paket yang diperlukan
apt install -y neon-desktop linux-generic casper lupin-casper discover kde-plasma-desktop

# Bersihkan chroot
apt clean
rm -rf /tmp/*
rm -rf /var/tmp/*
history -c

exit
EOF

# Unmount virtual filesystems
sudo umount $CHROOTDIR/dev
sudo umount $CHROOTDIR/proc
sudo umount $CHROOTDIR/sys

# Buat filesystem.squashfs jika belum ada
if [ ! -f "$WORKDIR/iso/casper/filesystem.squashfs" ]; then
    echo "Membuat filesystem.squashfs..."
    mkdir -p $WORKDIR/iso/casper
    sudo mksquashfs $CHROOTDIR $WORKDIR/iso/casper/filesystem.squashfs -comp xz
else
    echo "filesystem.squashfs sudah ada, melanjutkan..."
fi

# Salin kernel dan initrd ke direktori ISO jika belum disalin
if [ ! -f "$WORKDIR/iso/casper/vmlinuz" ]; then
    echo "Menyalin kernel dan initrd..."
    sudo cp $CHROOTDIR/boot/vmlinuz-* $WORKDIR/iso/casper/vmlinuz
    sudo cp $CHROOTDIR/boot/initrd.img-* $WORKDIR/iso/casper/initrd
else
    echo "Kernel dan initrd sudah disalin, melanjutkan..."
fi

# Buat direktori isolinux dan salin file boot jika belum ada
if [ ! -f "$WORKDIR/iso/isolinux/isolinux.bin" ]; then
    echo "Menyiapkan isolinux untuk booting..."
    mkdir -p $WORKDIR/iso/isolinux
    cp /usr/lib/ISOLINUX/isolinux.bin $WORKDIR/iso/isolinux/
    cp /usr/lib/syslinux/modules/bios/ldlinux.c32 $WORKDIR/iso/isolinux/
fi

# Buat konfigurasi isolinux untuk booting
cat <<EOF > $WORKDIR/iso/isolinux/isolinux.cfg
UI gfxboot bootlogo
DEFAULT linux
LABEL linux
  SAY Booting Ubuntu Noble with KDE Plasma...
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper quiet splash ---
EOF

# Buat file manifest jika belum ada
if [ ! -f "$WORKDIR/iso/casper/filesystem.manifest" ]; then
    echo "Membuat file manifest..."
    sudo chroot $CHROOTDIR dpkg-query -W --showformat='${Package} ${Version}\n' > $WORKDIR/iso/casper/filesystem.manifest
    cp $WORKDIR/iso/casper/filesystem.manifest $WORKDIR/iso/casper/filesystem.manifest-desktop
else
    echo "File manifest sudah ada, melanjutkan..."
fi

# Buat ISO
echo "Membuat ISO..."
cd $WORKDIR/iso
sudo xorriso -as mkisofs \
  -iso-level 3 \
  -o ../ubuntu-noble-kde.iso \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -volid "Ubuntu Noble KDE" \
  .

echo "ISO berhasil dibuat di $WORKDIR/ubuntu-noble-kde.iso"
