# 📓 AOT Changelog

## v1.0.0 - 2026-03-31 (Release Candidate)
*   **First Init Release (Not Sure about working or not Just Concept is READY)**
*   **Special Thanks**: @indianets

---
## v1.0.0 - 2026-03-31 (Stable Release)
*   **AOT Stable Release**: Official 1.0.0 release with production-ready USB and Ethernet tethering.
*   **Always-On Persistence**: Robust boot restoration for both USB and Ethernet interfaces (120s settling delay).
*   **Stability Fixes**: Improved NDC backend with "Double-Lock" validation to prevent malformed IP assignment.
*   **Kernel Diagnostics**: Integrated `dmesg` and `logcat` snippets into the diagnostics dashboard for easier troubleshooting.
*   **WebUI Dashboard**: Enhanced real-time status view showing Active Gateway IP and Client IP.
*   **ADB over Tethering**: Fully synchronized ADB startup with interface readiness.
*   **Material Design 3**: Professional WebUI for all tethering and ADB management.

---

## [0.9.0] - Beta Preview
### Added
- **Core Engine**: Switched to Android's native `ndc` (netd) stack.
- **Watchdog**: 5s background monitor for bridge health.
- **DNS Redirection**: Custom DNS support (Google, Cloudflare, etc.).
