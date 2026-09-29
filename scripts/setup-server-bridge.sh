#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Esegui questo script come root." >&2
  exit 1
fi

vpn_domain="${1:?dominio VPN mancante}"
bridge_root=/etc/wallet-skins
private_dir=/etc/swanctl/private
server_cert_dir=/etc/swanctl/x509
ca_cert_dir=/etc/swanctl/x509ca
vpn_user=wallet-bridge

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y strongswan-swanctl charon-systemd libcharon-extra-plugins libstrongswan-extra-plugins openssl

install -d -m 0700 "$bridge_root" "$private_dir"
install -d -m 0755 "$server_cert_dir" "$ca_cert_dir" /etc/swanctl/conf.d

ca_key="$private_dir/wallet-skins-ca-key.pem"
ca_cert="$ca_cert_dir/wallet-skins-ca-cert.pem"
server_key="$private_dir/wallet-skins-server-key.pem"
server_csr="$bridge_root/wallet-skins-server.csr"
server_cert="$server_cert_dir/wallet-skins-server-cert.pem"

if [ ! -s "$ca_key" ] || [ ! -s "$ca_cert" ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$ca_key"
  openssl req -x509 -new -sha256 -days 3650 -key "$ca_key" -out "$ca_cert" \
    -subj "/CN=Wallet Skins VPN CA/O=Wallet Skins"
fi

if [ ! -s "$server_key" ] || [ ! -s "$server_cert" ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$server_key"
  openssl req -new -sha256 -key "$server_key" -out "$server_csr" \
    -subj "/CN=$vpn_domain/O=Wallet Skins"
  openssl x509 -req -sha256 -days 825 -in "$server_csr" -CA "$ca_cert" -CAkey "$ca_key" \
    -CAcreateserial -out "$server_cert" \
    -extfile <(printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\nkeyUsage=digitalSignature,keyEncipherment\n' "$vpn_domain")
fi

chmod 0600 "$ca_key" "$server_key"
chmod 0644 "$ca_cert" "$server_cert"

credentials="$bridge_root/credentials"
if [ ! -s "$credentials" ]; then
  umask 077
  printf '%s\n' "$(openssl rand -base64 36 | tr -d '\n')" > "$credentials"
fi
vpn_password="$(tr -d '\r\n' < "$credentials")"

install -m 0600 /dev/null /etc/swanctl/conf.d/wallet-skins.conf
sed \
  -e "s|@@VPN_DOMAIN@@|$vpn_domain|g" \
  -e "s|@@VPN_USER@@|$vpn_user|g" \
  -e "s|@@VPN_PASSWORD@@|$vpn_password|g" \
  > /etc/swanctl/conf.d/wallet-skins.conf <<'SWANCTL'
connections {
  wallet-skins {
    version = 2
    local_addrs = 0.0.0.0
    proposals = aes256gcm16-prfsha256-ecp256
    pools = wallet-skins
    fragmentation = yes
    send_cert = always
    unique = replace
    dpd_delay = 30s
    local {
      auth = pubkey
      certs = wallet-skins-server-cert.pem
      id = @@VPN_DOMAIN@@
    }
    remote {
      auth = eap-mschapv2
      eap_id = %any
    }
    children {
      wallet-bridge {
        local_ts = 10.66.0.0/24
        esp_proposals = aes256gcm16-ecp256
        start_action = none
        dpd_action = clear
      }
    }
  }
}
pools {
  wallet-skins {
    addrs = 10.66.0.2-10.66.0.254
  }
}
secrets {
  private-wallet-skins {
    file = wallet-skins-server-key.pem
  }
  eap-wallet-skins {
    id = @@VPN_USER@@
    secret = "@@VPN_PASSWORD@@"
  }
}
SWANCTL

install -m 0644 /dev/null /etc/systemd/system/wallet-skins-address.service
sed 's/^      //' > /etc/systemd/system/wallet-skins-address.service <<'UNIT'
      [Unit]
      Description=Wallet Skins private gateway address
      Before=strongswan.service docker.service

      [Service]
      Type=oneshot
      ExecStart=/sbin/ip address replace 10.66.0.1/32 dev lo
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now wallet-skins-address.service
systemctl enable --now strongswan.service
swanctl --load-all

ca_der="$bridge_root/wallet-skins-ca-cert.der"
openssl x509 -in "$ca_cert" -outform DER -out "$ca_der"
ca_base64="$(base64 -w0 "$ca_der")"
install -m 0600 /dev/null "$bridge_root/bridge.env"
{
  printf 'VPN_REMOTE_ADDRESS=%s\n' "$vpn_domain"
  printf 'VPN_REMOTE_IDENTIFIER=%s\n' "$vpn_domain"
  printf 'VPN_USERNAME=%s\n' "$vpn_user"
  printf 'VPN_PASSWORD=%s\n' "$vpn_password"
  printf 'VPN_CA_CERT_BASE64=%s\n' "$ca_base64"
} > "$bridge_root/bridge.env"
chmod 0600 "$bridge_root/bridge.env"

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  ufw allow 500/udp
  ufw allow 4500/udp
fi

echo "Wallet Skins IKEv2 configurata per $vpn_domain."
