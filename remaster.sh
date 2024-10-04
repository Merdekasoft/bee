#!/bin/bash

# Skrip untuk membuat ISO Ubuntu Noble dengan KDE Neon User Edition

# Set variables
WORKDIR="/tmp/ubuntu-noble-iso"
CHROOTDIR="$WORKDIR/chroot"
MIRROR="http://archive.ubuntu.com/ubuntu"
NEON_REPO="https://archive.neon.kde.org/user"
DIST="noble"
ARCH="amd64"

# Pastikan dependensi yang dibutuhkan terpasang
echo "Memastikan dependensi terpasang..."
sudo apt update
sudo apt install -y debootstrap squashfs-tools genisoimage isolinux syslinux-utils xorriso wget

# Buat direktori kerja
echo "Membuat direktori kerja..."
mkdir -p $WORKDIR
mkdir -p $CHROOTDIR

# Mulai debootstrap untuk Ubuntu Noble
echo "Memulai debootstrap untuk $DIST..."
if ! sudo debootstrap --arch=$ARCH $DIST $CHROOTDIR $MIRROR; then
    echo "Kesalahan: debootstrap gagal. Silakan periksa log untuk detail lebih lanjut."
    exit 1
fi

# Masuk ke chroot
echo "Mengatur chroot..."
sudo mount --bind /dev $CHROOTDIR/dev
sudo mount --bind /proc $CHROOTDIR/proc
sudo mount --bind /sys $CHROOTDIR/sys

# Masuk ke dalam chroot
echo "Memasuki lingkungan chroot..."
sudo chroot $CHROOTDIR /bin/bash <<'EOF'
# Set environment
export LANG=C
export DEBIAN_FRONTEND=noninteractive

# Tambahkan repositori KDE Neon User
echo "Menambahkan repositori KDE Neon User..."
echo "deb $NEON_REPO $DIST main" >> /etc/apt/sources.list

# Tambahkan kunci GPG untuk KDE Neon User
wget -qO - https://archive.neon.kde.org/public.key | apt-key add -

# Update sistem dan install KDE Plasma
echo "Memperbarui sistem dan menginstal KDE Plasma..."
if ! apt update; then
    echo "Kesalahan: Gagal memperbarui sistem."
    exit 1
fi

if ! apt install -y neon-desktop linux-generic casper lupin-casper discover kde-plasma-desktop; then
    echo "Kesalahan: Gagal menginstal paket yang diperlukan."
    exit 1
fi

# Bersihkan chroot
echo "Membersihkan lingkungan chroot..."
apt clean
rm -rf /tmp/*
rm -rf /var/tmp/*
history -c

# Keluar dari chroot
exit
EOF

# Unmount virtual filesystems
echo "Unmounting virtual filesystems..."
sudo umount $CHROOTDIR/dev
sudo umount $CHROOTDIR/proc
sudo umount $CHROOTDIR/sys

# Buat filesystem.squashfs
echo "Membuat filesystem.squashfs..."
if ! sudo mksquashfs $CHROOTDIR $WORKDIR/iso/casper/filesystem.squashfs -comp xz; then
    echo "Kesalahan: Gagal membuat filesystem.squashfs."
    exit 1
fi

# Copy kernel dan initrd ke direktori ISO
echo "Menyalin kernel dan initrd ke direktori ISO..."
sudo cp $CHROOTDIR/boot/vmlinuz-* $WORKDIR/iso/casper/vmlinuz
sudo cp $CHROOTDIR/boot/initrd.img-* $WORKDIR/iso/casper/initrd

# Buat direktori untuk ISO boot
echo "Membuat direktori untuk ISO boot..."
mkdir -p $WORKDIR/iso/isolinux
cp /usr/lib/ISOLINUX/isolinux.bin $WORKDIR/iso/isolinux/
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 $WORKDIR/iso/isolinux/

# Buat konfigurasi isolinux untuk booting
echo "Membuat konfigurasi isolinux untuk booting..."
cat <<EOF > $WORKDIR/iso/isolinux/isolinux.cfg
UI gfxboot bootlogo
DEFAULT linux
LABEL linux
  SAY Booting Ubuntu Noble with KDE Plasma...
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper quiet splash ---
EOF

# Buat file manifest
echo "Membuat file manifest..."
sudo chroot $CHROOTDIR dpkg-query -W --showformat='${Package} ${Version}\n' > $WORKDIR/iso/casper/filesystem.manifest
cp $WORKDIR/iso/casper/filesystem.manifest $WORKDIR/iso/casper/filesystem.manifest-desktop

# Buat ISO
echo "Membuat ISO..."
cd $WORKDIR/iso
if ! sudo xorriso -as mkisofs \
  -iso-level 3 \
  -o ../ubuntu-noble-kde.iso \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img \
  -no-emul-boot -isohybrid-gpt-basdat \
  -volid "Ubuntu Noble KDE" \
  .; then
    echo "Kesalahan: Gagal membuat ISO."
    exit 1
fi

echo "ISO berhasil dibuat di $WORKDIR/ubuntu-noble-kde.iso"
