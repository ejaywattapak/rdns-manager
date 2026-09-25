# 🚀 RDNS Manager v0.2.0

![RDNS Manager](assets/rdns-banner.svg)

> Secure Decision Node ↔ Exit Node RDNS deployment manager.

RDNS Manager v0.2.0 provides a lightweight RDNS client deployment bundle with automatic DNS, SNI and QUIC interception.

## ✨ Features

- 🔐 Mutual TLS authentication
- 🌐 DNS interception
- 🔎 SNI interception
- ⚡ QUIC interception
- 🛡️ Automatic nftables redirects
- 🔄 Automatic tunnel connection
- 📋 Rule-based domain routing
- ⚙️ systemd service integration

## 🖥️ Supported OS

| OS | Status |
|---|---|
| Debian 13 | ✅ Supported |
| Debian 12 | ✅ Supported |
| Ubuntu 24.04 LTS | ✅ Supported |

## 📦 Repository Contents

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
├── .gitignore
└── README.md
```

## 🚀 Installation

### Copy & Paste

```bash
apt-get install -y wget && wget -qO installer.sh https://raw.githubusercontent.com/ejaywattapak/rdns-manager/main/installer.sh && bash installer.sh
```

## ⚠️ Important

The client configuration and certificate included in this repository must correspond to a node authorized by the RDNS server.

**Do not start `rdns-client-v0.2.0` manually after the systemd service is already running.** Doing so starts a second client instance and can produce:

```text
bind: address already in use
```

For example, port `5353` is expected to be occupied by the running RDNS client.

If you need to restart the client:

```bash
systemctl restart rdns-client
```

Check whether the service is already running:

```bash
systemctl is-active rdns-client
```

## 🔐 Security

The RDNS client uses mutual TLS authentication.

Keep private keys and other sensitive credentials outside the public repository. This repository intentionally does not include private `.key` files.

Before deploying to another VPS, make sure that VPS has the correct authorized client certificate/configuration.

## 🧹 Uninstall

To remove the client:

```bash
systemctl disable --now rdns-client
rm -f /etc/systemd/system/rdns-client.service
rm -f /usr/local/bin/rdns-client
rm -rf /etc/rdns
systemctl daemon-reload
```

## 📋 Version

- RDNS Manager: `v0.2.0`
- RDNS Client: `v0.2.0`

## 👤 Author

**EJAYWATTAPAK**

---

<p align="center">
  RDNS Manager • Smart RDNS Routing
</p>
