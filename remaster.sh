#!/bin/bash

# Skrip untuk membuat ISO B-OS (Ubuntu Noble + KDE Neon User Edition)

# Set variables
WORKDIR="/tmp/b-os-iso"
CHROOTDIR="$WORKDIR/chroot"
MIRROR="http://archive.ubuntu.com/ubuntu"
NEON_REPO="https://archive.neon.kde.org/user"
DIST="noble"
ARCH="amd64"

# Memastikan dependensi terpasang
echo "🔍 Memastikan dependensi terpasang..."
sudo apt update
sudo apt install -y debootstrap squashfs-tools genisoimage isolinux syslinux-utils xorriso wget

# Membuat direktori kerja
echo "📁 Membuat direktori kerja..."
mkdir -p $WORKDIR/iso/casper
mkdir -p $CHROOTDIR

# Memulai debootstrap
echo "📦 Memulai debootstrap untuk $DIST..."
if ! sudo debootstrap --arch=$ARCH $DIST $CHROOTDIR $MIRROR; then
    echo "❌ Kesalahan: debootstrap gagal."
    exit 1
fi

# Mount virtual filesystems
echo "🔧 Mengatur lingkungan chroot..."
sudo mount --bind /dev $CHROOTDIR/dev
sudo mount --bind /proc $CHROOTDIR/proc
sudo mount --bind /sys $CHROOTDIR/sys

# Masuk ke chroot dan konfigurasi
echo "🚪 Memasuki lingkungan chroot..."
sudo chroot $CHROOTDIR /bin/bash <<'EOT'
export LANG=C
export DEBIAN_FRONTEND=noninteractive

echo "➕ Menambahkan repositori KDE Neon..."
echo "deb https://archive.neon.kde.org/user noble main" >> /etc/apt/sources.list
wget -qO - https://archive.neon.kde.org/public.key | apt-key add -

echo "🔄 Memperbarui sistem..."
apt update

echo "🌐 Menginstal KDE Plasma dan paket pendukung..."
apt install -y neon-desktop linux-generic casper lupin-casper discover kde-plasma-desktop

echo "🧹 Membersihkan cache dan temporary..."
apt clean
rm -rf /tmp/* /var/tmp/*
history -c
EOT

# Unmount virtual filesystems
echo "🔓 Unmounting virtual filesystems..."
sudo umount $CHROOTDIR/dev
sudo umount $CHROOTDIR/proc
sudo umount $CHROOTDIR/sys

# Membuat squashfs filesystem
echo "🗜️ Membuat filesystem.squashfs..."
sudo mksquashfs $CHROOTDIR $WORKDIR/iso/casper/filesystem.squashfs -comp xz

# Menyalin kernel dan initrd
echo "📤 Menyalin kernel dan initrd..."
sudo cp $CHROOTDIR/boot/vmlinuz-* $WORKDIR/iso/casper/vmlinuz
sudo cp $CHROOTDIR/boot/initrd.img-* $WORKDIR/iso/casper/initrd

# Siapkan direktori isolinux
echo "🛠️ Menyiapkan direktori isolinux..."
mkdir -p $WORKDIR/iso/isolinux
cp /usr/lib/ISOLINUX/isolinux.bin $WORKDIR/iso/isolinux/
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 $WORKDIR/iso/isolinux/

# Konfigurasi bootloader
echo "⚙️ Membuat konfigurasi isolinux..."
cat <<EOF > $WORKDIR/iso/isolinux/isolinux.cfg
UI gfxboot bootlogo
DEFAULT linux
LABEL linux
  SAY Booting B-OS (Ubuntu Noble + KDE Plasma)...
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper quiet splash ---
EOF

# File manifest
echo "📄 Membuat file manifest..."
sudo chroot $CHROOTDIR dpkg-query -W --showformat='${Package} ${Version}\n' > $WORKDIR/iso/casper/filesystem.manifest
cp $WORKDIR/iso/casper/filesystem.manifest $WORKDIR/iso/casper/filesystem.manifest-desktop

# Pembuatan ISO final
echo "💿 Membuat file ISO B-OS..."
cd $WORKDIR/iso
sudo xorriso -as mkisofs \
  -iso-level 3 \
  -o ../B-OS.iso \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img \
  -no-emul-boot -isohybrid-gpt-basdat \
  -volid "B-OS" \
  .

echo "✅ ISO B-OS berhasil dibuat: $WORKDIR/B-OS.iso"
