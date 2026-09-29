#!/usr/bin/env bash
set -euo pipefail

echo "strongswan=$(systemctl is-active strongswan.service 2>/dev/null || true)"
echo "address=$(ip -4 address show dev lo | grep -q '10.66.0.1/32' && echo ready || echo missing)"
echo "ike_port_500=$(ss -H -lun | grep -qE '(:|\])500[[:space:]]' && echo listening || echo missing)"
echo "ike_port_4500=$(ss -H -lun | grep -qE '(:|\])4500[[:space:]]' && echo listening || echo missing)"
echo "dns_port=$(ss -H -lun | grep -qE '10\.66\.0\.1:53[[:space:]]' && echo listening || echo missing)"

if swanctl --list-sas --raw 2>/dev/null | grep -q 'uniqueid='; then
  echo "iphone_vpn_session=active"
else
  echo "iphone_vpn_session=none"
fi

diag_log="$(mktemp)"
trap 'rm -f "$diag_log"' EXIT
journalctl -u strongswan.service --since '-10 minutes' --no-pager -o cat > "$diag_log" 2>/dev/null || true
count_pattern() {
  local pattern="$1"
  grep -Eic "$pattern" "$diag_log" 2>/dev/null || true
}
echo "ike_packets_received=$(count_pattern 'received packet|IKE_SA_INIT request')"
echo "ike_auth_failures=$(count_pattern 'authentication.*failed|EAP.*failed')"
echo "ike_proposal_failures=$(count_pattern 'no proposal chosen|NO_PROPOSAL_CHOSEN')"
echo "ike_connections_established=$(count_pattern 'IKE_SA.*established|CHILD_SA.*established')"

python3 - <<'PY'
import socket, struct

def query(name):
    packet = bytearray(struct.pack("!HHHHHH", 0x5342, 0x0100, 1, 0, 0, 0))
    for label in name.split("."):
        data = label.encode("ascii")
        packet.append(len(data))
        packet.extend(data)
    packet.extend(b"\x00\x00\x01\x00\x01")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3)
    try:
        sock.sendto(packet, ("10.66.0.1", 53))
        response, _ = sock.recvfrom(4096)
        flags, answers = struct.unpack("!HH", response[2:6])[0], struct.unpack("!H", response[6:8])[0]
        return (flags & 0x000f) == 0 and answers > 0
    except OSError:
        return False
    finally:
        sock.close()

print("public_dns_forwarding=" + ("ready" if query("example.com") else "failed"))
PY

cd /opt/wallet-skins
if docker compose ps --status running -q wallet-skins | grep -q .; then
  echo "wallet_api=running"
else
  echo "wallet_api=stopped"
fi
