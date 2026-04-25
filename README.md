## 🌐 chromium-policies.json

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/SenseiDeElite/chromium-policies.json/blob/main/LICENSE)

`chromium-policies.json` is a policy file for Chromium-based browsers, built to maximise security and privacy, including stripping telemetry, and tightening the attack surface – with the goal of preserving usability wherever possible (though some breakage is expected).

Unlike browser extensions or experimental flags, policies are enforced at the system level and apply to all profiles. This project takes that mechanism and employs it to the same problems that [arkenfox/user.js](https://github.com/arkenfox/user.js) solves for Firefox – but for Google's Chromium. It draws similar inspiration from [ungoogled-software/ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium), achieving comparable hardening through local policies rather than a custom build.

The current template covers:

- **Telemetry & reporting –** all known metrics, crash reports, usage data, policy reports, WebRTC logs, and feedback pipelines are disabled;
- **Google account & sync –** browser sign-in and sync are disabled; guest mode is blocked;
- **Google & AI features –** Gemini, built-in AI APIs, Help Me Write, Tab Compare, AI-powered history search, live translation, and related features that phone home are disabled or restricted;
- **Security hardening –** HTTPS-only mode is force enabled; DNS over HTTPS is set to secure mode; Encrypted Client Hello, post-quantum key agreement, site isolation, origin-keyed processes, audio & network service sandbox are all enabled;
- **Permissions –** geolocation, clipboard, sensors, Bluetooth, file system access, window management, local fonts, and popups are blocked by default; third-party cookies are blocked; WebRTC is restricted to the default public interface only;
- **Autofill & passwords –** the built-in password manager, autofill for addresses and credit cards, password sharing, and automated password changes are all disabled for privacy and security reasons; users are expected to manage credentials through an external trusted service;
- **Remote access & debugging –** remote debugging, remote access connections, and firewall traversal for remote access are disabled;
- **UI & behaviour –** full URLs are always shown in the address bar; search suggestions, translation, spellcheck service, autoplay, network prediction, and background mode are disabled; download location prompt is always shown; external extensions are blocked;
- **+** Relevant early & experimental features are also expected.

> 🛡️ **Safe Browsing is disabled** in this configuration as it sends URLs to Google for evaluation, which is a privacy concern. To maintain protection against malicious sites, it is recommended to use [uBlock Origin Lite](https://github.com/uBlockOrigin/uBOL-home) and DNS-level content blocking with filter lists such as [uAssets badware filter](https://github.com/uBlockOrigin/uAssets/blob/master/filters/badware.txt) and [URLhaus malware filter](https://gitlab.com/malware-filter/urlhaus-filter).

> 🫆 **Fingerprinting notice:** Using this configuration may make you stand out more easily to fingerprinting – unless there are enough users adopting it too.

---

### ⬇️ Installation

Download and make sure that you are in the same directory as [`policies.json`](https://github.com/SenseiDeElite/chromium-policies.json/blob/main/policies.json) – this file is required for all platforms.

The setup script will prompt you to use [curl](https://github.com/curl/curl) to fetch it in case it's not already there. It should be available in all supported platforms by default.

#### 🐧 Linux
Run the interactive setup script with elevated privileges:
```bash
run0 setup-linux.sh
```

You can also try `sudo-rs`, `doas`, `pkexec`, `sudo` and `su` if `run0` isn't available.

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

After applying policies, restart your Chromium-based browser and verify at `chrome://policy`. All entries should show **Source: Platform**, **Level: Mandatory**, and **Status: OK**.

---

### 🗑️ Uninstallation

Just run the same setup script again, then choose **`Uninstall`** when prompted.

---

### 🫂 Contributions

Contributions are welcome at the discretion of the project maintainer.

If you believe a relevant policy is missing or something is broken, please open an issue or submit a pull request.

---

### 👏 Acknowledgments

**Inspired** by [arkenfox/user.js](https://github.com/arkenfox/user.js), [ungoogled-software/ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium). All policies were independently researched and curated by the project maintainer from [official Google sources](https://chromeenterprise.google/policies).

**I am not affiliated with nor endorsed by any of the projects mentioned. They are present for reference purposes only.**
