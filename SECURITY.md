# Security policy

## Supported versions

Security fixes are applied to the latest code on the `main` branch. Release assets may lag behind `main`; check the latest release notes before testing a report.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability, leaked secret, unsafe exported Android component, command injection path, VPN routing bypass, or privacy-sensitive log exposure.

Use GitHub's **Security → Report a vulnerability** flow when it is available. If private vulnerability reporting is unavailable, contact the maintainer privately through the contact information on the [GitHub profile](https://github.com/xxkingstuggle).

Include:

- the affected version or commit;
- the Android and macOS versions and device architecture;
- a minimal reproduction;
- the potential impact;
- relevant sanitized logs or proof-of-concept code;
- any suggested mitigation.

You can expect an initial acknowledgement within 7 days. Please allow time for investigation and a coordinated fix before public disclosure.

## Scope notes

USB LinkMic uses ADB, an Android VPN service, microphone access, and macOS network configuration. These capabilities are expected, but they should only activate after explicit user action and required operating-system authorization. Reports showing behavior outside those boundaries are especially valuable.
