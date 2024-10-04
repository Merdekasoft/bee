#!/bin/bash

set -e  # Menghentikan skrip jika ada perintah yang gagal
set -u  # Menghentikan skrip jika ada variabel yang tidak terdefinisi

# Variabel Konfigurasi
WORKDIR="/tmp/ubuntu-noble-iso"
CHROOTDIR="$WORKDIR/chroot"
MIRROR="http://archive.ubuntu.com/ubuntu"
NEON_REPO="https://archive.neon.kde.org/user"
DIST="noble"
ARCH="amd64"
ISO_NAME="ubuntu-noble-kde.iso"

# Fungsi untuk Menampilkan Pesan
log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S')]: $*"
}

# Pastikan skrip dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
    log "Skrip ini harus dijalankan dengan hak akses root. Gunakan sudo."
    exit 1
fi

# Instalasi Dependensi yang Diperlukan
log "Memeriksa dan menginstal dependensi yang diperlukan..."
apt update
apt install -y debootstrap squashfs-tools genisoimage isolinux syslinux-utils xorriso wget gnupg

# Membuat Direktori Kerja
log "Membuat direktori kerja di $WORKDIR..."
mkdir -p "$WORKDIR"
mkdir -p "$CHROOTDIR"

# Memulai atau Melanjutkan debootstrap
if [ ! -d "$CHROOTDIR/debootstrap" ]; then
    log "Memulai debootstrap untuk Ubuntu Noble..."
    debootstrap --arch="$ARCH" "$DIST" "$CHROOTDIR" "$MIRROR"
else
    log "Lingkungan debootstrap sudah ada, melanjutkan..."
fi

# Mount Filesystems Virtual
log "Mounting /dev, /proc, dan /sys ke chroot..."
mount --bind /dev "$CHROOTDIR/dev"
mount --bind /proc "$CHROOTDIR/proc"
mount --bind /sys "$CHROOTDIR/sys"

# Menjalankan Perintah di dalam Chroot
log "Menjalankan perintah di dalam chroot..."
chroot "$CHROOTDIR" /bin/bash <<'EOF'
set -e
set -u

export LANG=C
export DEBIAN_FRONTEND=noninteractive

# Memperbarui apt dan menginstal wget dan gnupg jika belum terinstal
apt update
apt install -y wget gnupg

# Menambahkan Repositori KDE Neon User melalui file terpisah
if [ ! -f /etc/apt/sources.list.d/kde-neon-user.list ]; then
    echo "deb https://archive.neon.kde.org/user noble main" > /etc/apt/sources.list.d/kde-neon-user.list
fi

# Menambahkan Kunci GPG KDE Neon User
if ! apt-key list | grep -q "KDE Neon"; then
    wget -qO - https://archive.neon.kde.org/public.key | apt-key add -
fi

# Memperbarui apt setelah menambahkan repositori baru
apt update

# Menginstal KDE Plasma dan paket-paket yang Diperlukan
apt install -y neon-desktop linux-generic casper lupin-casper discover kde-plasma-desktop

# Menginstal paket tambahan yang mungkin diperlukan
apt install -y systemd-sysv

# Membersihkan Cache APT
apt clean
rm -rf /tmp/* /var/tmp/*

# Menghapus riwayat bash
history -c

EOF

# Unmount Filesystems Virtual
log "Unmounting /dev, /proc, dan /sys dari chroot..."
umount "$CHROOTDIR/dev"
umount "$CHROOTDIR/proc"
umount "$CHROOTDIR/sys"

# Memeriksa Instalasi Kernel dan Initrd
if [ ! -f "$CHROOTDIR/boot/vmlinuz-$(uname -r)" ] || [ ! -f "$CHROOTDIR/boot/initrd.img-$(uname -r)" ]; then
    log "Kernel atau initrd tidak ditemukan di chroot. Memastikan instalasi kernel..."
    chroot "$CHROOTDIR" /bin/bash -c "apt update && apt install -y linux-generic"
fi

# Membuat filesystem.squashfs jika belum ada
if [ ! -f "$WORKDIR/iso/casper/filesystem.squashfs" ]; then
    log "Membuat filesystem.squashfs..."
    mkdir -p "$WORKDIR/iso/casper"
    mksquashfs "$CHROOTDIR" "$WORKDIR/iso/casper/filesystem.squashfs" -comp xz
else
    log "filesystem.squashfs sudah ada, melanjutkan..."
fi

# Menyalin Kernel dan Initrd ke Direktori ISO jika belum disalin
if [ ! -f "$WORKDIR/iso/casper/vmlinuz" ] || [ ! -f "$WORKDIR/iso/casper/initrd" ]; then
    log "Menyalin kernel dan initrd ke direktori ISO..."
    cp "$CHROOTDIR/boot/vmlinuz-"* "$WORKDIR/iso/casper/vmlinuz"
    cp "$CHROOTDIR/boot/initrd.img-"* "$WORKDIR/iso/casper/initrd"
else
    log "Kernel dan initrd sudah disalin, melanjutkan..."
fi

# Membuat Direktori untuk ISO Boot jika belum ada
if [ ! -f "$WORKDIR/iso/isolinux/isolinux.bin" ]; then
    log "Menyiapkan isolinux untuk booting..."
    mkdir -p "$WORKDIR/iso/isolinux"
    cp /usr/lib/ISOLINUX/isolinux.bin "$WORKDIR/iso/isolinux/"
    cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "$WORKDIR/iso/isolinux/"
fi

# Membuat Konfigurasi isolinux untuk Booting
log "Membuat konfigurasi isolinux.cfg..."
cat <<EOF > "$WORKDIR/iso/isolinux/isolinux.cfg"
UI gfxboot bootlogo
DEFAULT linux
LABEL linux
  SAY Booting Ubuntu Noble with KDE Plasma...
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper quiet splash ---
EOF

# Membuat File Manifest jika belum ada
if [ ! -f "$WORKDIR/iso/casper/filesystem.manifest" ]; then
    log "Membuat file manifest..."
    chroot "$CHROOTDIR" dpkg-query -W --showformat='${Package} ${Version}\n' > "$WORKDIR/iso/casper/filesystem.manifest"
    cp "$WORKDIR/iso/casper/filesystem.manifest" "$WORKDIR/iso/casper/filesystem.manifest-desktop"
else
    log "File manifest sudah ada, melanjutkan..."
fi

# Membuat ISO
log "Membuat ISO Ubuntu Noble dengan KDE Plasma..."
cd "$WORKDIR/iso"
xorriso -as mkisofs \
  -iso-level 3 \
  -o "../$ISO_NAME" \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -volid "Ubuntu_Noble_KDE" \
  .

log "ISO berhasil dibuat di $WORKDIR/$ISO_NAME"
