# Yamaha RX-V671 — development todo

Bottom-up: XML protocol → HTTP service → settings → controller → overlay.

Live-checked on `192.168.2.2`: HTTP is always POST to `/YamahaRemoteControl/ctrl`. Result is XML `RC` (`0` = OK, `4` = not available in this state). GET `Basic_Status` works in Standby. PUT Input / Volume need Power On first; input then persists through Standby.

---

## Layer 0 — Protocol + model (no I/O)

- [x] `YamahaStatus` — `power` (`On` / `Standby`), `inputSel`, `volumeTenthsDb`, `mute`
- [x] `YamahaProtocol` — endpoint path, XML builders, parse GET body + `RC` (XPath)
  - GET `Basic_Status`
  - PUT `Power` `On` / `Standby`
  - PUT `Input_Sel` (raw name, e.g. `HDMI4`)
  - PUT absolute volume; service steps ±0.5 dB (`Val` tenths of a dB)

---

## Layer 1 — HTTP facade

- [x] `YamahaService` — POST XML, timeout, return parsed status or success/`RC`
  - `getBasicStatus(ip)`
  - `setPower(ip, YamahaPower)`
  - `selectInput(ip, inputSel)`
  - `volumeUp(ip)` / `volumeDown(ip)` (GET, then PUT ±5 tenths dB)
- [x] Inject IP as an argument (same pattern as `NetworkService.ping`)
- [x] Unit tests: builders + parser (fixture XML from the live GET); local HTTP fake for the service

---

## Layer 2 — Settings

- [x] Persist receiver IP
- [x] Settings UI fields (with radio player IP)

---

## Layer 3 — Controller + overlay

- [x] Thin controller: call service, hold last `YamahaStatus`, wake-then-command when Standby
- [x] Overlay: power, input dropdown (from receiver list), volume +/−
- [x] Android cleartext HTTP for Yamaha Network Control (LAN)

---

## First slice

Layer 0 + Layer 1 only. No overlay, no `RadioController` wiring.
