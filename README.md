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

## 🖥️ Supported OS

| OS | Status |
|---|---|
| Debian 13 | ✅ Supported |
| Debian 12 | ✅ Supported |
| Ubuntu 24.04 LTS | ✅ Supported |
| Ubuntu 22.04 LTS | ✅ Supported |
| Rocky Linux 10 | ⚠️ Experimental |

## 🏗️ Architecture

```text
                 ┌─────────────────────┐
                 │    Decision Node    │
                 └──────────┬──────────┘
                            │
                       Mutual TLS
                            │
                            ▼
                 ┌─────────────────────┐
                 │      Exit Node      │
                 └──────────┬──────────┘
                            │
                 ┌──────────┼──────────┐
                 │          │          │
               DNS         SNI        QUIC
              :53        :14300      :14400
```

## 📁 Included Files

```text
etc/
└── rdns/
    ├── ca.crt
    ├── client.yaml
    ├── rules.json
    └── certs/
        └── node.crt

etc/systemd/system/
└── rdns-client.service

rdns-client-v0.2.0
```

## 🚀 Installation

Run the installation script as root:

```bash
sudo bash install.sh
```

Then check the service:

```bash
systemctl status rdns-client --no-pager
```

## 🔧 Service Management

Restart:

```bash
systemctl restart rdns-client
```

Status:

```bash
systemctl status rdns-client --no-pager -l
```

Live logs:

```bash
journalctl -u rdns-client -f
```

## 🔒 Security

This project uses mutual TLS between the Decision Node and Exit Node.

Private keys, secrets and authentication tokens should never be committed to the repository.

## 📌 Notes

The RDNS client automatically manages:

- DNS interception
- SNI interception
- QUIC interception
- nftables redirects
- RDNS tunnel connection

## 📜 Version

**RDNS Manager v0.2.0**

Decision Node ↔ Exit Node RDNS Architecture
