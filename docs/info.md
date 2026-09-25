<!---
This file is used to generate your project datasheet on the Tiny Tapeout website.
-->

## How it works

This project implements an **All-Digital Phase-Locked Loop (ADPLL)** that multiplies a 12.5 MHz reference clock up to a 100 MHz high-speed output clock ($N = 8$).

The loop architecture consists of:
1. **Bang-Bang Phase Detector (BBPD)**: A digital flip-flop sampling the feedback clock on every reference clock rising edge (`up_dn = ~fb_clk`).
2. **Dual-Stage Digital Loop Filter**:
   - **Stage 1 (Coarse AFC)**: Bypasses the 1-bit phase detector during startup and directly counts feedback clock edges over a 200-cycle reference window to eliminate phase-aliasing and false-locking.
   - **Stage 2 (Fine Bang-Bang PI)**: Once frequency is within $\pm 0.5\%$, hands off to a Proportional-Integral (PI) tracking loop to eliminate steady-state phase error and minimize output jitter.
3. **Digitally Controlled Oscillator (DCO)**: A synthesizable standard-cell ring oscillator controlled by the 16-bit Oscillator Tuning Word (`otw[15:0]`).
4. **Feedback Divider (/8)**: Generates a 50% duty-cycle 12.5 MHz feedback clock.

### Pinout Mapping

- **Inputs (`ui_in`)**:
  - `ui_in[7:0]`: Optional coarse `otw_init[15:8]` override (leave `0x00` for default 16'd28000 acquisition).
- **Outputs (`uo_out`)**:
  - `uo_out[0]`: Primary 100 MHz locked DCO clock (`clk_out`).
  - `uo_out[1]`: 12.5 MHz divided feedback clock (`fb_clk`).
  - `uo_out[2]`: Lock status flag (`freq_locked`: 1 = locked).
  - `uo_out[3]`: 1-bit Bang-Bang phase detector decision (`up_dn`).
  - `uo_out[7:4]`: Top 4 bits of Tuning Word (`otw[15:12]`).
- **Bidirectional IOs (`uio_out`)**:
  - `uio_out[7:0]`: Middle 8 bits of Tuning Word (`otw[11:4]`).
  - `uio_oe[7:0]`: Configured as outputs (`0xFF`).

---

## How to test

1. Provide a **12.5 MHz square-wave clock** on the `clk` pin.
2. Assert active-low reset (`rst_n = 0`) for at least 10 clock cycles, then deassert (`rst_n = 1`).
3. Leave `ui_in = 0x00` (or set a custom starting tuning word).
4. Monitor `uo_out[2]` (`freq_locked`):
   - At power-up, `freq_locked = 0` (coarse AFC acquisition active).
   - Within $\approx 160\text{ }\mu\text{s}$ (3 measurement windows), `freq_locked` transitions to `1`.
5. Connect an oscilloscope or spectrum analyzer to `uo_out[0]` (`clk_out`) to measure the locked 100 MHz clock.
6. Connect a logic analyzer to `uo_out[7:4]` and `uio_out[7:0]` to observe the 12-bit real-time `otw[15:4]` settling trajectory.

---

## External hardware

- Oscilloscope or logic analyzer to probe `uo_out[0]` (100 MHz output) and `uo_out[2]` (lock flag).
- Standard 12.5 MHz or 10 MHz signal generator connected to `clk`.
