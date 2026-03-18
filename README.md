### 🟩  chromium-policies.json

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

`chromium-policies.json` is a **hardened policy template** for Chromium-based browsers, built to maximise privacy and security, strip telemetry, and tighten the attack surface — with the goal of preserving usability wherever possible (though some breakage is expected).

Unlike browser extensions or experimental flags, Chromium policies are enforced at the system level and apply to all profiles. This project takes that mechanism and applies it to the same problems that [arkenfox/user.js](https://github.com/arkenfox/user.js) solves for Firefox — but for Google's Chromium. It draws similar inspiration from [ungoogled-software/ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium), achieving comparable hardening through enforced local policies rather than a custom build.

**Security is the primary focus**, occasionally at the expense of stability. Privacy is a close second.

The current template covers:

- **Telemetry & reporting** — all metrics, crash reports, usage data, policy reports, WebRTC logs, and feedback pipelines are disabled;
- **Google account & sync** — browser sign-in and sync are disabled; guest mode is blocked;
- **Google & AI features** — Gemini, built-in AI APIs, Help Me Write, Tab Compare, AI-powered history search, live translation, shopping list, and related features are disabled or restricted;
- **Security hardening** — HTTPS-only mode is force-enabled; DNS-over-HTTPS is set to secure mode; Encrypted Client Hello, post-quantum key agreement, site isolation, origin-keyed processes, audio sandbox, and network service sandbox are all enabled;
- **Permissions** — geolocation, clipboard, sensors, Bluetooth, file system access, window management, local fonts, and popups are blocked by default; third-party cookies are blocked; WebRTC is restricted to the default public interface only;
- **Autofill & passwords** — the built-in password manager, autofill for addresses and credit cards, password sharing, and automated password changes are all disabled for privacy and security reasons; users are expected to manage credentials through an external service of their choice;
- **Remote access & debugging** — remote debugging, remote access connections, and firewall traversal for remote access are disabled;
- **UI & behaviour** — full URLs are always shown in the address bar; search suggestions, translation, spellcheck service, autoplay, network prediction, and background mode are disabled; download location prompt is always shown; external extensions are blocked.

> 🛡️ **Safe Browsing is disabled** in this configuration as it sends URLs to Google for evaluation, which is a privacy concern. To maintain protection against malicious sites, it is recommended to use [uBlock Origin Lite](https://github.com/uBlockOrigin/uBOL-home) and DNS-level content blocking with filter lists such as [uAssets badware filter](https://github.com/uBlockOrigin/uAssets/blob/master/filters/badware.txt) and [URLhaus malware filter](https://gitlab.com/malware-filter/urlhaus-filter).

> ⚠️ **Fingerprinting notice:** Using this configuration may make you stand out more easily to fingerprinting — unless there are enough other users adopting it too. It can also cause captchas to appear more frequently on websites such as Google or X (formerly Twitter).

---

### 🟪  What is a policies.json?

A `policies.json` lets system administrators — and privacy-conscious individuals — manage Chromium settings at the policy layer rather than the profile layer. Changes made here persist across profile resets and take precedence over user-facing preferences.

---

### 🟦  Installation

#### Linux
```bash
run0 mkdir -p /etc/chromium/policies/managed/
run0 cp --reflink=auto policies.json /etc/chromium/policies/managed/policies.json
```

#### macOS (untested)
Run the interactive setup script:
```zsh
sudo ./setup-macos.sh
```
The script reads `policies.json` from the same directory and writes it as a plist to `/Library/Managed Preferences/com.google.Chrome.plist`. Python 3 is required.

#### Windows
Run the interactive setup script from an **Administrator** PowerShell session:
```powershell
powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
```
The script reads `policies.json` from the same directory and writes each policy as a registry value under `HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\Chrome`.

After applying policies, restart Chromium and verify at `chrome://policy`. All entries should show **Source: Platform**, **Level: Mandatory**, and **Status: OK**.

---

### 🟧  Uninstallation

#### Linux
```bash
run0 rm -f /etc/chromium/policies/managed/policies.json
```

#### macOS
```zsh
sudo ./setup.sh
```
Choose **[2] Uninstall** when prompted.

#### Windows
```powershell
powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
```
Choose **[2] Uninstall** when prompted.

---

### 🟫  Contributions

Contributions are welcome, but are at the discretion of the project maintainer.

If you believe a relevant setting is missing from the default template, please open an issue or submit a pull request.

---

### 🟥  Acknowledgments

**Inspired** by [arkenfox/user.js](https://github.com/arkenfox/user.js), [ungoogled-software/ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium). All policies were independently researched and curated by the project maintainer from [official Google sources](https://chromeenterprise.google/policies).

**I am not affiliated with nor endorsed by any of the projects mentioned. They are present for reference purposes only.**
