#!/bin/bash

# ==============================================================================
# Skrip Otomatis untuk Setup Remote Desktop (XFCE + VNC + noVNC) di Debian/Ubuntu
# ==============================================================================
# Deskripsi:
# Skrip ini mengotomatiskan seluruh proses instalasi dan konfigurasi untuk:
# 1. Desktop Environment XFCE yang ringan.
# 2. TigerVNC sebagai server VNC.
# 3. noVNC sebagai klien VNC berbasis web.
# 4. Layanan Systemd agar VNC & noVNC berjalan otomatis saat boot.
# 5. Browser web Chromium.
# ==============================================================================

# Hentikan skrip jika ada perintah yang gagal
set -e

# --- KONFIGURASI (Bisa diubah jika perlu) ---
NOVNC_PORT="9006" # Port yang akan digunakan untuk mengakses desktop di browser

# --- Variabel Internal ---
# Mendeteksi username non-root yang menjalankan sudo
if [ -n "$SUDO_USER" ]; then
    USERNAME=$SUDO_USER
else
    echo "Kesalahan: Skrip ini harus dijalankan dengan 'sudo'. Contoh: sudo ./setup_desktop.sh"
    exit 1
fi
USER_HOME="/home/$USERNAME"
VNC_DIR="$USER_HOME/.vnc"
NOVNC_DIR="$USER_HOME/noVNC"

# --- Fungsi untuk menampilkan pesan ---
info() {
    echo "[INFO] $1"
}

success() {
    echo "[BERHASIL] $1"
}

# --- 1. Instalasi Paket yang Dibutuhkan ---
info "Memperbarui daftar paket..."
apt-get update

info "Menginstall paket-paket yang dibutuhkan (XFCE, VNC, Git, Chromium)..."
apt-get install -y xfce4 xfce4-goodies tigervnc-standalone-server tigervnc-common git dbus-x11 chromium

# --- 2. Konfigurasi VNC untuk Pengguna ---
info "Membuat direktori konfigurasi VNC di $VNC_DIR..."
mkdir -p "$VNC_DIR"

info "Silakan masukkan kata sandi untuk VNC (minimal 6 karakter)."
# Meminta pengguna memasukkan kata sandi VNC secara aman
vncpasswd "$VNC_DIR/passwd"

info "Membuat file startup VNC (xstartup)..."
cat << EOF > "$VNC_DIR/xstartup"
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
/usr/bin/xfce4-session
EOF

info "Memberikan izin eksekusi pada xstartup..."
chmod +x "$VNC_DIR/xstartup"

# --- 3. Instalasi noVNC ---
info "Mengunduh noVNC dari GitHub ke $NOVNC_DIR..."
if [ -d "$NOVNC_DIR" ]; then
    info "Direktori noVNC sudah ada, proses unduh dilewati."
else
    # Menjalankan git clone sebagai pengguna, bukan root
    sudo -u "$USERNAME" git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
fi

# --- 4. Membuat Layanan Systemd ---
info "Membuat file layanan systemd untuk VNC Server..."
cat << EOF > /etc/systemd/system/vncserver@.service
[Unit]
Description=Start TigerVNC server at startup for display %i
After=syslog.target network.target

[Service]
Type=forking
User=$USERNAME
ExecStart=/usr/bin/vncserver :%i -localhost yes -geometry 1280x800 -depth 24 -passwd $VNC_DIR/passwd
ExecStop=/usr/bin/vncserver -kill :%i

[Install]
WantedBy=multi-user.target
EOF

info "Membuat file layanan systemd untuk noVNC..."
# Menggunakan novnc_proxy yang merupakan metode terbaru
cat << EOF > /etc/systemd/system/novnc.service
[Unit]
Description=noVNC VNC Web Client
Requires=vncserver@1.service
After=vncserver@1.service

[Service]
Type=simple
User=$USERNAME
ExecStart=$NOVNC_DIR/utils/novnc_proxy --vnc localhost:5901 --listen $NOVNC_PORT
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

info "Membereskan kepemilikan file di direktori home pengguna..."
chown -R "$USERNAME":"$USERNAME" "$USER_HOME"

# --- 5. Mengaktifkan dan Menjalankan Layanan ---
info "Memuat ulang konfigurasi systemd..."
systemctl daemon-reload

info "Mengaktifkan dan menjalankan vncserver@1.service..."
systemctl enable --now vncserver@1.service

info "Mengaktifkan dan menjalankan novnc.service..."
systemctl enable --now novnc.service

# Menunggu sejenak agar layanan sempat berjalan
sleep 5

# --- 6. Menampilkan Hasil Akhir ---
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "IP_PUBLIK_ANDA")

success "================================================================="
success "SETUP SELESAI!"
success "================================================================="
echo ""
echo "Remote desktop Anda sekarang seharusnya sudah berjalan."
echo ""
echo "AKSI YANG PERLU ANDA LAKUKAN:"
echo "1. Buka AWS Console dan pergi ke Security Group instans ini."
echo "2. Tambahkan Inbound Rule baru untuk mengizinkan trafik TCP pada port $NOVNC_PORT."
echo ""
echo "Setelah itu, akses desktop Anda melalui browser di alamat:"
echo "   http://$PUBLIC_IP:$NOVNC_PORT/vnc.html"
echo ""
echo "Gunakan kata sandi VNC yang baru saja Anda buat untuk login."
echo "Browser Chromium sudah terinstall di dalam desktop."
echo "================================================================="

# Verifikasi status layanan
if systemctl is-active --quiet vncserver@1.service && systemctl is-active --quiet novnc.service; then
    success "Status Layanan: VNC dan noVNC aktif dan berjalan."
else
    echo "[PERINGATAN] Satu atau lebih layanan gagal dimulai. Cek status dengan:"
    echo "systemctl status vncserver@1.service"
    echo "systemctl status novnc.service"
fi