<p align="center">
  <img src="/icons/Chromium_Logo.svg" alt="Chromium logo" width="120" />
</p>

<h1 align="center">chromium-policies.json</h1>

<p align="center">
  A <b>policy</b> file for configuration and hardening of <b>Chromium-based</b> browsers.
</p>

<p align="center">
  <a href="https://github.com/SenseiDeElite/chromium-policies.json/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-D9D9D9?style=for-the-badge&labelColor=1a1a1a&logo=opensourceinitiative&logoColor=white" alt="License: MIT" />
  </a>
</p>

`chromium-policies.json` is a policy file for Chromium-based browsers, built to maximise security and privacy, including stripping telemetry, and tightening the attack surface – with the goal of preserving usability wherever possible (though some breakage is expected).

Unlike browser extensions or experimental flags, policies are enforced at the system level and apply to all profiles.

The current template covers:

- **Telemetry & reporting –** all known metrics, crash reports, URL-keyed usage data, domain reliability reporting, browser network time queries, WebRTC logs, feedback and surveys are disabled;
- **Google account & sync –** browser sign-in and sync are disabled; guest mode is blocked;
- **Google & AI features –** Gemini, built-in AI APIs, Help Me Write, Tab Compare, AI-powered history search, live translation, and related features that phone home are disabled or restricted;
- **Security hardening –** HTTPS-only mode is force enabled; DNS over HTTPS is set to secure mode; Encrypted Client Hello, WebRTC post-quantum key agreement, site isolation, origin-keyed processes, audio & network service sandbox are all enabled; the JavaScript optimizer (JIT) and insecure content are blocked by default;
- **Permissions –** geolocation, clipboard, sensors, idle detection, Bluetooth, file system access, window management, local fonts, and popups are blocked by default; third-party cookies are blocked; WebRTC is restricted to the default public interface only;
- **Autofill & passwords –** the built-in password manager, autofill (all types), password sharing, password leak detection, payment method queries, and automated password changes are all disabled for privacy and security reasons; users are expected to manage credentials through an external trusted service;
- **Remote access & debugging –** remote debugging and all Chrome Remote Desktop host features (remote access and support connections, relayed connections, firewall traversal, file transfer, PIN authentication, client pairing, URL forwarding) are disabled; the curtain is required and the host is matched to the local username if access is ever re-enabled;
- **UI & behaviour –** full URLs are always shown in the address bar; search suggestions, translation, spellcheck service, autoplay, network prediction, background mode, promotions, shopping list, side search, media recommendations, the Web Store icon, and Outlook/SharePoint NTP cards are disabled or hidden; download location prompt is always shown;
- **Updates & variations –** component updates are disabled, Chrome Variations are limited to critical fixes only, and Chrome for Testing is blocked;
- **+** Relevant early & experimental features are also expected.

> 🛡️ **Safe Browsing is disabled** in this configuration as it sends URLs to Google for evaluation, which is a privacy concern. To maintain protection against malicious sites, it is recommended to use [uBlock Origin Lite](https://github.com/uBlockOrigin/uBOL-home) and DNS-level content blocking with filter lists such as [URLhaus malware filter](https://gitlab.com/malware-filter/urlhaus-filter).

> 🫆 **Fingerprinting notice:** Using this configuration may make you stand out more easily to fingerprinting – unless there are enough users adopting it too.

---

### 🌐 Supported browsers

Each setup script lists these browsers in the same order. Browsers that read the same location share a single policy file, key or plist, so applying policies to one applies them to all of its siblings.

| Browser            | Linux | Windows | macOS |
| ------------------ | :---: | :-----: | :---: |
| Google Chrome      |   ☑️   |    ☑️    |   ☑️   |
| Chromium           |   ☑️   |    ☑️    |   ☑️   |
| Ungoogled Chromium |   ☑️   |    ☑️    |   ☑️   |
| Microsoft Edge     |   ☑️   |    ☑️    |   ☑️   |
| Vivaldi            |   ☑️   |    ☑️    |   ☑️   |
| Brave              |   ☑️   |    ☑️    |   ☑️   |
| Yandex Browser     |   ☑️   |    ☑️    |   ☑️   |
| Cromite            |   ☑️   |    ☑️    |   ❌   |
| Helium             |   ☑️   |    ☑️    |   ☑️   |
| Thorium            |   ☑️   |    ☑️    |   ☑️   |

- **Cromite** has no macOS build, so it is not offered by `setup-macos.sh`.
- **Linux –** Chromium, Ungoogled Chromium, Vivaldi, Helium and Thorium all use `/etc/chromium/policies/managed`.
- **Windows –** Chromium, Ungoogled Chromium, Helium and Thorium all use `HKLM\SOFTWARE\Policies\Chromium`. Vivaldi has its own key.
- **macOS –** Chromium and Ungoogled Chromium share one bundle ID (`org.chromium.Chromium`) and therefore one plist. Every other browser has its own.

Policies that a given browser doesn't implement are simply ignored by it.

---

### ⬇️ Installation

Download and make sure that you are in the same directory as [`policies.json`](https://github.com/SenseiDeElite/chromium-policies.json/blob/main/policies.json) – this file is required for all platforms.

The setup script will prompt you to use [curl](https://github.com/curl/curl) to fetch it in case it's not already there. `curl` ships with macOS and with Windows as `curl.exe`; on Linux it must be installed if you want the remote fetch. Pass `-s` / `--skip` (`-Skip` on Windows) to disable the remote fetch entirely and use a local `policies.json` only.

#### 🐧 Linux
Run the interactive setup script with elevated privileges:
```bash
run0 ./setup-linux.sh
```

You can also try `sudo-rs`, `doas`, `pkexec`, `sudo` and `su` if `run0` (systemd) isn't available.

#### 🪟 Windows
Run the interactive setup script from an Administrator PowerShell session:
```powershell
powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
```

#### 🍎 macOS
Run the interactive setup script with elevated privileges. Python 3 is required.
```zsh
sudo ./setup-macos.sh
```

After applying policies, restart your Chromium-based browser and verify at `chrome://policy` (or the browser's own scheme). All entries should show **Source: Platform**, **Level: Mandatory**, and **Status: OK**.

---

### 🗑️ Uninstallation

Just run the same setup script again, then choose **`Uninstall`** when prompted.

---

### 🫂 Contributions

Contributions are welcome at the discretion of the project maintainer.

If you believe a relevant policy is missing or something is broken, please open an issue or submit a pull request.

---

All policies were independently researched and curated by the project maintainer from [official Google sources](https://chromeenterprise.google/policies).
