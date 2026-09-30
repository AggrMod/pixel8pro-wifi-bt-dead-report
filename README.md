# Pixel 8 Pro: Wi-Fi and Bluetooth both dead — diagnosis log and a workaround that stopped working

**Status: one phone, two sessions eleven days apart. This is a field report, not a verified fix.**

**Update (day 12): the workaround no longer works.** The radios were dead again, and neither the bootloader
reboot (twice) nor a full power-off brought them back, at a cool temperature. I now treat this unit as a hardware
fault. See [section 5a](#5a-day-12-the-workaround-stopped-working) and, for a way to get the phone online anyway,
[section 5b](#5b-internet-without-wi-fi-usb-reverse-tethering).

A Pixel 8 Pro (Tensor G3, Android 17) came up after a factory reset with **no Wi-Fi and no Bluetooth at all**.
Reinstalling Android did not help. On day 1, rebooting **through the bootloader** brought both radios back, three
times out of three, while the two ordinary boots I observed (first boot after the factory reset, first boot after
the update) did not. On day 12 it did not. The evidence fits an intermittent, worsening
fault in the combined Wi-Fi/Bluetooth chip; I could not prove that, and it is not proven here.

If your Pixel 8 Pro shows the signatures below, this might save you some hours. If it works for you, or doesn't,
please open an issue with your result: more units are the only way to learn what is actually going on.

---

## 1. The unit

| | |
|---|---|
| Phone | Pixel 8 Pro (`husky`), Tensor G3, 12 GB RAM, 256 GB |
| Software | Android 17, build `CP2A.260805.005` (Aug 2026), later `CP3A.260905.009` (Sep 2026) |
| Bootloader | locked, verified boot `green`, stock, never modified |
| Wi-Fi/BT chip | Broadcom; driver module `bcmdhd4398.ko` is present in `/vendor_dlkm` |
| SIM | none (cellular modem was healthy the whole time) |

## 2. Symptoms in the failing state

Everything below was read over `adb` with no root.

**Wi-Fi**
- Settings toggle does nothing. No `wlan0` in `/sys/class/net`.
- `lsmod` has no `bcmdhd4398`, although the `.ko` file exists.
- Logcat, repeating on every attempt:
  ```
  WifiHAL : Timed out waiting on Driver ready ...
  vendor.google.wifi_ext-service-vendor: Failed to start legacy HAL: TIMED_OUT
  WifiChipAidlImpl: configureChip failed ... timed out (code 9)
  vendor.google.wifi_ext-service-vendor: Unknown iface name: wlan0
  ```
- PCIe: `/sys/bus/pci/devices` showed the cellular modem's endpoint (`0000:01:00.0`, driver `s51xx`) but the second
  root port `0001:00:00.0` had **nothing behind it**. In the working state a chip appears at `0001:01:00.0`
  (driver `pcieh`). So in the dead state the Wi-Fi chip was not enumerating on the bus at all.

**Bluetooth**
- Stays off. `dumpsys bluetooth_manager` shows `Address: [address is null]` and `Bluetooth crashed N times`
  (6 times in 4 minutes at first boot).
- Each crash is `system/gd/hal/hci_backend_aidl.cc:103 ... The Bluetooth HAL died.`
- The Bluetooth HAL logged `Failed to write message to coex device: Bad file descriptor`.

`android.hardware.wifi` and Bluetooth services were all running normally; the failure is below them.

## 3. What did *not* help

| Attempt | Result |
|---|---|
| Factory reset | Failure was already present on the very first boot after it |
| Full OTA sideload (recovery, locked bootloader, keeps data) of a newer build, after a fresh factory reset | Identical failure afterwards |
| Toggling Wi-Fi / Bluetooth, retrying | No effect. Also see the lockout note in section 5 |
| Ordinary boots (first after the reset, first after the update) | Dead both times |

Not tried: rolling back to an older firmware (needs an unlocked bootloader, and Pixel 8-series bootloaders have
anti-rollback since May 2025 — see "Related reports"); a controlled cold test (ice pack); root or custom ROMs.

## 4. What brought the radios back

```
adb reboot bootloader        # reboot into the bootloader...
fastboot reboot              # ...and straight back to Android. Nothing is flashed or changed.
```

After that boot, all of these were true, every time (three times):

- `wlan0` and `wlan1` exist; `bcmdhd4398` is in `lsmod`; PCIe shows the chip at `0001:01:00.0`.
- Bluetooth reports a real address and stays on.
- The radio scans and sees 16 to 24 networks.

On the third attempt I also turned Bluetooth **off** immediately after boot and only then enabled Wi-Fi
(`cmd bluetooth_manager disable`, `settings put global ble_scan_always_enabled 0`, `cmd wifi set-wifi-enabled enabled`).
Wi-Fi then joined a WPA2 network normally (173 Mbps link, validated internet) and stayed connected.
Because the bootloader reboot and the Bluetooth change happened together, I can't say which mattered.

## 5. What still went wrong when the radios were up

- **Chip firmware crash.** In one working boot, about 17 seconds after the first connection attempt, the log showed
  `vendor.google.wifi_ext-service-vendor: Attempting to invoke onSubsystemRestart callback`, and the chip did not
  come back until the next boot. Bluetooth was also active at the time.
- **Android's own lockout.** After repeated failed starts Android stops trying:
  `WifiSelfRecovery: Already restarted wifi 10 times in last 1 hour. Disabling wifi`.
  My repeated retries made this worse. A reboot clears it.
- The failure signature changes once the driver has loaded: `WifiHAL : Could not create handle` instead of
  `Timed out waiting on Driver ready`.

## 5a. Day 12: the workaround stopped working

Eleven days after day 1 (Wi-Fi had been working in between; I don't know exactly when it failed), the phone was
connected again with the radios dead. Same build (`CP3A.260905.009`), nothing changed on the phone.

Read-only check (section 8) on the running phone:

- No `wlan` interface, `bcmdhd4398` not loaded, Wi-Fi disabled.
- PCIe: `0000:00:00.0`, `0000:01:00.0` (modem, `s51xx`), `0001:00:00.0` — **nothing at `0001:01:00.0`**. Same
  signature as day 1: the chip is not on the bus.
- `Timed out waiting on Driver ready` 5 times, the Wi-Fi self-recovery lockout 4 times, `The Bluetooth HAL died`
  7 times (`Bluetooth crashed 7 times`) in that boot.
- Battery temperature 26.2 °C. That's not the SoC temperature, but the phone was not warm.

| Attempt (each followed by Bluetooth off + Wi-Fi on, re-checked after boot settled) | Result |
|---|---|
| Bootloader reboot (section 4) | Chip absent, Wi-Fi disabled |
| Bootloader reboot, second time | Chip absent, Wi-Fi disabled |
| Full power-off, left off at least 30 s, powered on by hand | Chip absent, Wi-Fi disabled |

I stopped there on purpose so I wouldn't run into the lockout. The bootloader path is not a reliable fix, a cold
power cycle didn't help either, and a warm phone isn't needed for the fault to show up.

## 5b. Internet without Wi-Fi: USB reverse tethering

With no working radio (and no usable cellular data), the phone can still get online through a computer's
connection over USB using [Gnirehtet](https://github.com/Genymobile/gnirehtet) (open source, Genymobile). It
needs USB debugging and no root. It installs a small client app on the phone that shows up as a VPN (key icon).

```
gnirehtet run          # from the gnirehtet folder; set ADB=<path to adb> if adb isn't on PATH
```

On this phone Android marked the connection `VALIDATED` within seconds, and Google services and Play synced.
Notes:
- **Ping is not a valid test.** Gnirehtet relays TCP and UDP only, so ICMP always shows 100% loss even while
  everything works. Check `dumpsys connectivity` for `VALIDATED`, or just open a web page.
- The phone must stay plugged in and the relay must keep running on the computer.
- To undo it: stop the relay, `adb reverse --remove-all`, `adb uninstall com.genymobile.gnirehtet`.

It's a stopgap for backing up and getting through setup until the repair, not a fix.

## 6. What I think is going on (unproven)

1. **Intermittent hardware fault** in the combined chip or its board connection. This matches the public reports
   below (heat-sensitive, temporarily fixed by cooling). Consistent with "chip absent on PCIe until it happens to
   come up".
2. **The bootloader path resets the chip more completely** than a warm reboot (rails, reset line). Consistent with
   three out of three on day 1, but **contradicted on day 12** (0 of 2, and a full power-off also failed). At most
   it helped while the fault was milder.
3. **Bluetooth load contributing to Wi-Fi firmware crashes** (shared chip). One observation; weak.

Day 12 makes explanation 1 the most likely one, and suggests the fault is getting worse over time.

Experiments that would separate these, which I did not run: a controlled cold test; Bluetooth on versus off with
the same boot path; repeat counts on more phones. (Full power-off versus the bootloader path: tried on day 12,
and both failed.)

## 7. Related reports

- Android Police: [Pixel 8 Pro Wi-Fi and Bluetooth issues just won't go away](https://www.androidpolice.com/google-pixel-8-pro-wi-fi-bluetooth-issues-just-wont-go-away/)
  — same signature (Wi-Fi HAL cannot see the interface the kernel presents), worse when warm, cooling reportedly helps.
- Trusted Reviews: [Pixel 8 Pro Wi-Fi and Bluetooth issues aren't getting any better](https://www.trustedreviews.com/news/google-pixel-8-pro-wi-fi-and-bluetooth-issues)
- Google Pixel Community: "[Critical Failure] Pixel 8 Pro / Android 16: Wi-Fi & Bluetooth Totally Dead (Drivers Failed)"
- Anti-rollback on Pixel 8-series since May 2025: [Android Police](https://www.androidpolice.com/may-2025-google-pixel-security-update-anti-rollback-bootloader/)
  — do **not** try to flash older factory images without reading this; mistakes can permanently brick the phone.

I only read the first article in full; the others are from search results.

## 8. Check your own phone

`tools/pixel-radio-check.ps1` is **read-only**. It prints the signatures above and never prints your serial number.

```powershell
.\tools\pixel-radio-check.ps1 -Adb C:\path\to\adb.exe
```

Needs USB debugging on and the computer authorised. If more than one Android device is attached, set
`ANDROID_SERIAL` to the phone's serial first. I've run the script against the phone in this report in both the
**working** state (day 1) and the **dead** state (day 12, output summarised in section 5a), and with no phone
attached.

## 9. If it is hardware

The reports above suggest a solder or board fault, so the realistic fixes are a warranty or repair claim, or a
board-level repair shop. Reinstalling Android will not fix a chip that is not answering. Do not heat the phone.

## 10. Limits

- One phone. Two sessions. No root, so no kernel log from boot; the driver's own load messages were never visible.
- I never ran a controlled cold test. All I can say about temperature is that the fault showed up with the phone
  at room temperature (day 12).
- The commands in section 4 are exactly what I ran, but I have not packaged them as a script.

## 11. Privacy and provenance

Wi-Fi names, addresses, the serial number and account details were removed. The diagnosis and this write-up were
produced in a working session with Claude (Anthropic) driving `adb` on a phone I was holding; I reviewed the
findings before publishing.

Released under the [Unlicense](LICENSE).
