# 🚀 RDNS Manager v0.2.0

![RDNS Manager](assets/rdns-banner.svg)

> Secure Decision Node ↔ Exit Node RDNS deployment manager.

RDNS Manager v0.2.0 provides a lightweight RDNS client/server architecture with automatic DNS, SNI and QUIC interception.

## ✨ Features

- 🔐 Mutual TLS authentication
- 🌐 DNS interception
- 🔎 SNI interception
- ⚡ QUIC interception
- 🛡️ nftables automatic redirects
- 🔄 Automatic tunnel connection
- 📦 Ready-to-deploy client bundle
- 📋 Rule-based domain routing
- ⚙️ systemd service integration

## 🖥️ Supported OS

| OS | Status |
|---|---|
| Debian 13 | ✅ Supported |
| Debian 12 | ✅ Supported |
| Ubuntu 24.04 LTS | ✅ Supported |

## 📦 Included

```text
rdns-manager/
├── assets/
│   └── rdns-banner.svg
├── etc/
│   ├── rdns/
│   │   ├── ca.crt
│   │   ├── client.yaml
│   │   ├── rules.json
│   │   └── certs/
│   │       └── node.crt
│   └── systemd/
│       └── system/
│           └── rdns-client.service
├── rdns-client-v0.2.0
└── README.md
```

## 🔧 Client

The RDNS client provides:

- DNS interceptor on `0.0.0.0:5353`
- SNI interceptor on `0.0.0.0:14300`
- QUIC interceptor on `0.0.0.0:14400`
- Automatic nftables redirect rules
- Automatic tunnel connection
- Mutual TLS authentication

## 🚀 Deployment

Copy the client binary and configuration files to the target system, then enable the systemd service:

```bash
install -m 755 rdns-client-v0.2.0 /usr/local/bin/rdns-client

mkdir -p /etc/rdns/certs

cp etc/rdns/client.yaml /etc/rdns/
cp etc/rdns/ca.crt /etc/rdns/
cp etc/rdns/rules.json /etc/rdns/
cp etc/rdns/certs/node.crt /etc/rdns/certs/

cp etc/systemd/system/rdns-client.service /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now rdns-client
```

Check the service:

```bash
systemctl status rdns-client --no-pager -l
```

View logs:

```bash
journalctl -u rdns-client -f
```

## 🛡️ Security

RDNS Manager uses mutual TLS for node authentication. Keep private keys and sensitive credentials outside the public repository.

Configuration files containing private credentials should **not** be committed to Git.

## 📋 Version

**RDNS Manager:** `v0.2.0`

**Client:** `rdns-client-v0.2.0`

## 👤 Author

**EJAYWATTAPAK**

---

<p align="center">
  RDNS Manager • Smart RDNS Routing
</p>
