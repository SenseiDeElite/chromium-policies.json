### 🟩  chromium-policies.json

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

`chromium-policies.json` is a **template** which aims to provide as much privacy and enhanced security as possible, reduce the attack surface, force-enable security features, and eliminate telemetry — while minimizing any loss of functionality and breakage (but it will happen).

It's inspired by what [arkenfox/user.js](https://github.com/arkenfox/user.js) does for Firefox, but for Chromium. It is also inspired by [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium), but without forking or compiling custom binaries — instead enforcing hardened local policies. At its core, this project is a personal Chromium configuration released to the open source community.

**Security is the primary focus**, sometimes placed above stability, though not universally for every critical setting. Privacy follows closely.

The current template covers:

- **Telemetry & reporting** — all metrics, crash reports, usage data, policy reports, WebRTC logs, and feedback pipelines are disabled
- **Google account & sync** — browser sign-in and sync are disabled; guest mode is blocked
- **Google & AI features** — Gemini, built-in AI APIs, Help Me Write, Tab Compare, AI-powered history search, live translation, shopping list, and related features are disabled or restricted
- **Security hardening** — HTTPS-only mode is force-enabled; DNS-over-HTTPS is set to secure mode; Encrypted Client Hello, post-quantum key agreement, site isolation, origin-keyed processes, audio sandbox, and network service sandbox are all enabled
- **Permissions** — geolocation, clipboard, sensors, Bluetooth, file system access, window management, local fonts, and popups are blocked by default; third-party cookies are blocked; WebRTC is restricted to the default public interface only
- **Autofill & passwords** — the built-in password manager, autofill for addresses and credit cards, password sharing, and automated password changes are all disabled for privacy and security reasons; users are expected to manage credentials through an external service of their choice
- **Remote access & debugging** — remote debugging, remote access connections, and firewall traversal for remote access are disabled
- **UI & behaviour** — full URLs are always shown in the address bar; search suggestions, translation, spellcheck service, autoplay, network prediction, and background mode are disabled; download location prompt is always shown; external extensions are blocked

> 🛡️ **Safe Browsing is disabled** in this configuration as it sends URLs to Google for evaluation, which is a privacy concern. To maintain protection against malicious sites, it is recommended to use [uBlock Origin Lite](https://github.com/uBlockOrigin/uBOL-home) and DNS-level content blocking with filter lists such as [uAssets badware filters](https://github.com/uBlockOrigin/uAssets/blob/master/filters/badware.txt) and [URLhaus malware filter](https://gitlab.com/malware-filter/urlhaus-filter).

> ⚠️ **Fingerprinting notice:** Using this configuration may make you stand out more easily to fingerprinting — unless there are enough other users adopting it too. It can also cause captchas to appear more frequently on sites such as Google or X (formerly Twitter).

---

### 🟪  What is a policies.json?

A `policies.json` is a configuration file that allows system administrators — and privacy-conscious users — to control Chromium settings at the browser policy level. Unlike extensions or flags, policies are applied at a deeper level and persist across profile resets.

The managed policy file path varies by OS:

- **Linux:** `/etc/chromium/policies/managed/policies.json`
- **macOS:** `/Library/Managed Preferences/policies.json`
- **Windows:** `C:\Program Files\Google\Chrome\Application\policies\managed\policies.json`

The filename can be changed, but must have a `.json` extension.

---

### 🟦  Installation

#### Linux
```bash
run0 mkdir -p /etc/chromium/policies/managed/
run0 cp --reflink=auto policies.json /etc/chromium/policies/managed/policies.json
```

#### MacOS
```bash
sudo mkdir -p "/Library/Managed Preferences/"
sudo cp policies.json "/Library/Managed Preferences/policies.json"
```

#### Windows
```powershell
New-Item -ItemType Directory -Force -Path "C:\Program Files\Google\Chrome\Application\policies\managed"
Copy-Item policies.json "C:\Program Files\Google\Chrome\Application\policies\managed\policies.json"
```

After copying, restart Chromium and verify policies are applied by visiting `chrome://policy`. All entries should show **Source: Platform**, **Level: Mandatory**, and **Status: OK**.

---

### 🟫  Contributions

Contributions are welcome, but are at the discretion of the project maintainer.

If you believe a relevant setting is missing from the default template, please open an issue or submit a pull request.

---

### 🟥  Acknowledgments

Inspired by [arkenfox/user.js](https://github.com/arkenfox/user.js) and [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium). All policies were independently researched and curated by the project maintainer from [official Google sources](https://chromeenterprise.google/policies).
