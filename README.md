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

### 1. Clone the repository

```bash
cd /root
git clone https://github.com/ejaywattapak/rdns-manager.git
cd rdns-manager
```

### 2. Install the RDNS client

```bash
install -m 755 rdns-client-v0.2.0 /usr/local/bin/rdns-client

mkdir -p /etc/rdns/certs

install -m 644 etc/rdns/client.yaml /etc/rdns/client.yaml
install -m 644 etc/rdns/ca.crt /etc/rdns/ca.crt
install -m 644 etc/rdns/rules.json /etc/rdns/rules.json
install -m 644 etc/rdns/certs/node.crt /etc/rdns/certs/node.crt

install -m 644 etc/systemd/system/rdns-client.service     /etc/systemd/system/rdns-client.service
```

### 3. Start the service

```bash
systemctl daemon-reload
systemctl enable --now rdns-client
```

### 4. Verify

```bash
systemctl status rdns-client --no-pager -l
```

Check the listening ports:

```bash
ss -lntup | grep -E ':5353|:14300|:14400'
```

View live logs:

```bash
journalctl -u rdns-client -f
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
