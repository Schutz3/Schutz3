#!/bin/bash

CLOUDFLARE_API_TOKEN=""
ZONE_ID=""
DNS_RECORD_ID=""
DNS_RECORD_NAME=""
DNS_RECORD_TYPE=""

# ===================================================================
# BAGIAN BARU: Cek dan Instal Dependensi
# ===================================================================
# Skrip ini memerlukan 'curl' dan 'jq'. Cek apakah keduanya terinstal.

# Cek untuk curl
if ! command -v curl &> /dev/null; then
    echo "Dependensi 'curl' tidak ditemukan. Memasang sekarang..."
    # Jalankan update sebelum install
    sudo apt-get update
    sudo apt-get install -y curl
fi

# Cek untuk jq
if ! command -v jq &> /dev/null; then
    echo "Dependensi 'jq' tidak ditemukan. Memasang sekarang..."
    # Jika curl baru saja diinstal, update tidak perlu lagi,
    # namun tetap aman untuk menjalankannya jika diperlukan.
    sudo apt-get update
    sudo apt-get install -y jq
fi
# ===================================================================
# AKHIR BAGIAN BARU
# ===================================================================


# Definisikan path lengkap ke perintah agar skrip bisa dijalankan dengan cron
CURL="/usr/bin/curl"
JQ="/usr/bin/jq"

# Dapatkan alamat IP publik saat ini
IP=$($CURL -s http://ipv4.icanhazip.com)
echo "IP Publik saat ini: $IP"

# Endpoint API Cloudflare untuk mendapatkan record DNS saat ini
GET_API_ENDPOINT="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_RECORD_ID"

# Dapatkan alamat IP pada record DNS dari Cloudflare
current_ip=$($CURL -s -X GET "$GET_API_ENDPOINT" \
     -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
     -H "Content-Type: application/json" | $JQ -r '.result.content')

# Cek apakah alamat IP berbeda
if [[ "$IP" == "$current_ip" ]]; then
  echo "Tidak perlu update. Alamat IP tidak berubah: $IP"
else
  echo "Alamat IP berubah dari $current_ip ke $IP. Memperbarui record..."

  # Endpoint API Cloudflare untuk memperbarui record DNS
  UPDATE_API_ENDPOINT="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_RECORD_ID"

  # Perbarui record DNS
  response=$($CURL -s -X PUT "$UPDATE_API_ENDPOINT" \
       -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
       -H "Content-Type: application/json" \
       --data '{
         "type": "'"$DNS_RECORD_TYPE"'",
         "name": "'"$DNS_RECORD_NAME"'",
         "content": "'"$IP"'",
         "ttl": 0,
         "proxied": false
       }')

  # Cek apakah pembaruan berhasil
  if [[ $response == *"\"success\":true"* ]]; then
    echo "Record DNS berhasil diperbarui ke IP: $IP"
  else
    echo "Gagal memperbarui record DNS. Respons dari Cloudflare: $response"
  fi
fi