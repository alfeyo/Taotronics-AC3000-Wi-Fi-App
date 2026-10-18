# Wi-Fi configuration — 1.9.0

The Wi-Fi screen presents **Nokia Wifi — Main Household Network** while retaining each TaoTronics configuration entry. Entries are not bands: observed BSSIDs/frequencies provide band evidence; the app does not rename index 0/1 into an assumed 2.4/5 GHz mapping.

- Show/Hide is available only for a known common password on a secured logical network.
- Router device totals are labelled as totals; a per-SSID device count is not invented.
- Main and duplicate profiles remain enabled. Index 2 remains disabled. No TaoTronics Wi-Fi mutation was performed during this release's hardware validation.
- `Game Labs-2.4G` remains observed-only because no verified editable endpoint was found.
- WPA3 remains excluded: this firmware previously normalized Encrypt=5 to unsecured. Use verified WPA2-PSK/AES.
- Per-entry editing, enable/disable and reported client/SSID isolation preserve the full current configuration. Successful acknowledgments require matching read-back. Firmware-returned extra fields survive.
- Guest writes first refresh the existing object, merge requested fields and verify the resulting object, including password.
- Unknown channel-width/broadcast controls remain explanatory, not speculative write buttons.
- Android scan observations over 120 seconds old are excluded. Precise-location denial is explained. SSID/MAC-prefix similarity alone does not prove a Nokia identity.

Nokia radios are shown separately from TaoTronics configuration. Root Beacon 2 reports 2.4 and 5 GHz profiles under different WebGUI keys. SSID, radio enable, BSSID, channel, standard and security come from those responses. Nokia radio/guest/channel setters remain unavailable until their full field-preservation and read-back behavior is validated. Joining a household SSID with the Nokia radios is a separate, potentially disruptive change requiring owner approval.

## Beacon 1 approved household migration — 18 October 2026

Both primary Nokia bands now use `Nokia Wifi`, the existing household key and WPA2/AES, with authenticated read-back and Fold4 internet verification on each BSSID. This operator migration used the firmware's full encrypted WebGUI save format; no general Nokia radio setter was added to Flutter. Existing channels, widths, bridge mode and other profiles were preserved. [Evidence and limits](NOKIA_BRIDGE_VALIDATION.md).
