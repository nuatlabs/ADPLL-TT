![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# All-Digital Phase-Locked Loop (ADPLL) - Tiny Tapeout

A synthesizable **All-Digital Phase-Locked Loop (ADPLL)** designed for automated manufacturing and verification via **Tiny Tapeout**.

- **Top Module**: `tt_um_nuatlabs_adpll`
- **Target Clock Frequency**: 12.5 MHz Reference Clock (`clk`) $\rightarrow$ 100 MHz Locked DCO Clock (`uo_out[0]`) ($N = 8$)
- **Automated Flow**: LibreLane / OpenLane ASIC Hardening, GDSII layout streaming, and Cocotb CI testing
- [Read the Tiny Tapeout Datasheet](docs/info.md)

---

## 1. System Architecture

```
                    +--------+     +-------------+      +--------------+
 ref_clk (12.5M) -> |        |     |             |      |              |
                    |  BBPD  |---->| Loop Filter |----->|   DCO Core   |---+--> clk_out (100 MHz)
 fb_clk  (12.5M) -> |        |up_dn|  (AFC + PI) | OTW  | (dco_digital)|   |
                    +--------+     +-------------+      +--------------+   |
                         ^                                                 |
                         |                   +---------------+             |
                         +-------------------|  /8 Divider   |<------------+
                           fb_clk (12.5 MHz) +---------------+
```

The ADPLL employs a **dual-stage acquisition loop**:
1. **Coarse Automatic Frequency Control (AFC)**: Uses a 200-cycle reference window edge counter to eliminate phase-aliasing and false-locking.
2. **Fine Bang-Bang PI Tracking**: Proportional-Integral (PI) loop eliminates steady-state phase error and achieves tight limit-cycle lock.

---

## 2. Tiny Tapeout Pinout Mapping

| Pin | Type | Signal Name | Description |
|:---|:---|:---|:---|
| **`clk`** | Input | `ref_clk` | 12.5 MHz Golden Reference Clock |
| **`rst_n`**| Input | `rst_n` | Active-low asynchronous reset |
| **`ena`** | Input | `ena` | Chip enable (must be high for operation) |
| **`ui_in[7:0]`** | Input | `otw_init[15:8]` | Optional coarse tuning override (default `0x00` $\rightarrow$ 16'd28000) |
| **`uo_out[0]`** | Output | `clk_out` | **100 MHz Locked Output Clock** |
| **`uo_out[1]`** | Output | `fb_clk` | 12.5 MHz Divided Feedback Clock |
| **`uo_out[2]`** | Output | `freq_locked` | Lock Detection Flag (1 = Locked) |
| **`uo_out[3]`** | Output | `up_dn` | 1-bit Bang-Bang Phase Detector Output |
| **`uo_out[7:4]`**| Output | `otw[15:12]` | Top 4 MSBs of the Oscillator Tuning Word |
| **`uio_out[7:0]`**| Output | `otw[11:4]` | Middle 8 bits of the Oscillator Tuning Word |
| **`uio_oe[7:0]`**| Output | `8'hFF` | Configured as outputs for full 12-bit real-time OTW monitoring |

---

## 3. Specifications Summary

| Parameter | Value | Unit | Notes |
|:---|:---|:---|:---|
| **Supply Voltage (VDD)** | 1.8 | V | Standard core logic voltage |
| **Reference Clock (`F_REF`)** | 12.5 | MHz | Reference period `T_REF = 80.0 ns` |
| **DCO Output Frequency (`F_DCO`)** | 100.0 | MHz | Nominal period `T_DCO = 10.0 ns` |
| **Multiplication Factor (`N`)** | 8 | - | Integer divide ratio |
| **Tuning Word Bus Width (`OTW`)** | 16 | bits | 65,536 frequency levels |
| **Nominal Center Code** | 32768 | - | Midscale code producing 100.0 MHz |
| **DCO Gain Sensitivity (`K_DCO`)** | 0.20 | ps/LSB | Linear period shift per LSB |
| **Frequency Error at Lock** | < 0.015% | - | Measured period = 9998.8 ps |
| **Coarse Lock Time** | < 48 | us | 3 measurement windows (200 cycles each) |

---

## 4. Source Files (`src/`)

```
src/
├── config.json             # Tiny Tapeout OpenLane / LibreLane synthesis config
├── project.v               # Top-level Tiny Tapeout wrapper (tt_um_nuatlabs_adpll)
├── adpll_digital_top.v     # Core synthesizable ADPLL loop module
├── bbpd.v                  # Bang-Bang Phase Detector
├── loop_filter.v           # Dual-Stage Loop Filter (Coarse AFC + Fine Bang-Bang PI)
├── clk_divider.v           # Programmable /8 feedback clock divider
├── dco_digital.v           # Synthesizable DCO module with linear tuning
├── dco_ring_structural.v   # Gate-level structural ring oscillator model
└── dco_model.v             # Behavioral simulation model
```

---

## 5. Verification & Testing

### 5.1 Local Simulation (Icarus Verilog)
```powershell
iverilog -g2012 -I src -o sim_tt.out test/tb.v src/project.v src/adpll_digital_top.v src/bbpd.v src/clk_divider.v src/loop_filter.v src/dco_digital.v
vvp sim_tt.out
```

### 5.2 Standalone 180nm Testbench
```powershell
iverilog -g2012 -o sim_180nm.out tb_adpll_digital.v src/adpll_digital_top.v src/bbpd.v src/clk_divider.v src/dco_digital.v src/loop_filter.v
vvp sim_180nm.out
```

**Verified Simulation Output**:
```text
[160290318600 ps] 180nm ADPLL LOCKED! Measured period = 10073.600 ps (target 10000.000 ps), OTW=32400
TEST PASSED: 180nm ADPLL locked successfully! Final OTW=32774, period=9998.800 ps
Reference Freq = 12.5 MHz (Period = 80000.0 ps), Target DCO Freq = 100 MHz (Period = 10000.0 ps)
```

### 5.3 View Waveforms in GTKWave
```powershell
C:\iverilog\gtkwave\bin\gtkwave.exe adpll_180nm.vcd
```
- Append `clk`, `uo_out[0]` (`clk_out`), `uo_out[1]` (`fb_clk`), `uo_out[2]` (`freq_locked`), and `uo_out[7:4]` / `uio_out[7:0]` (`otw`).
- Right-click `otw` -> **Data Format** -> **Decimal** -> **Analog** -> **Step** to visualize the settling staircase trajectory.

---

## 6. Automated Tiny Tapeout Build & GDS Generation

When pushed to GitHub, the Tiny Tapeout GitHub Actions workflows automatically:
1. **`test.yaml`**: Runs Cocotb verification using `test/test.py`.
2. **`gds.yaml`**: Hardens the design using OpenLane, checks DRC/LVS, and outputs the final GDSII macro.
3. **`docs.yaml`**: Generates and deploys the project datasheet to GitHub Pages.

---

## 7. License

Released under the [Apache 2.0 License](LICENSE).
