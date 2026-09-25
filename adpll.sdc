# ==============================================================================
# Organization: NUAT Labs (https://github.com/nuatlabs)
# Project:      NUAT All-Digital Phase-Locked Loop (ADPLL) Silicon IP
# File:         adpll.sdc
# Author:       NUAT Labs Engineering Team (admin@nuatlabs.com)
# Description:  Synopsys Design Constraints (SDC) for SCL 180nm CMOS
# ==============================================================================

# Set time unit: nanoseconds
set_units -time ns -resistance kOhm -capacitance pF -voltage V -current mA

# ------------------------------------------------------------------------------
# 1. Reference Clock (12.5 MHz -> Period = 80.0 ns)
# ------------------------------------------------------------------------------
create_clock -name ref_clk -period 80.0 [get_ports ref_clk]
set_clock_uncertainty 0.20 [get_clocks ref_clk]
set_clock_transition  0.30 [get_clocks ref_clk]

# ------------------------------------------------------------------------------
# 2. DCO Generated Clock (100 MHz -> Period = 10.0 ns)
# ------------------------------------------------------------------------------
# In internal DCO mode, clk_out is generated inside dco_digital
create_clock -name dco_clk -period 10.0 [get_ports clk_out]
set_clock_uncertainty 0.10 [get_clocks dco_clk]
set_clock_transition  0.15 [get_clocks dco_clk]

# ------------------------------------------------------------------------------
# 3. Divided Feedback Clock (12.5 MHz -> Generated from DCO clock / 8)
# ------------------------------------------------------------------------------
create_generated_clock -name fb_clk \
    -source [get_ports clk_out] \
    -divide_by 8 \
    [get_pins u_div/clk_out]

# ------------------------------------------------------------------------------
# 4. Asynchronous Clock Domain Groups (CDC)
# ------------------------------------------------------------------------------
# The ref_clk domain and the DCO/fb_clk domain run asynchronously during acquisition.
# Setting clock groups as asynchronous prevents false cross-domain timing violations:
set_clock_groups -asynchronous \
    -group [get_clocks ref_clk] \
    -group [get_clocks {dco_clk fb_clk}]

# ------------------------------------------------------------------------------
# 5. IO Delays (Realistic 180nm IO Pad Boundaries)
# ------------------------------------------------------------------------------
set_input_delay  -clock ref_clk 2.0 [get_ports rst_n]
set_input_delay  -clock ref_clk 2.0 [get_ports otw_init*]
set_output_delay -clock ref_clk 2.0 [get_ports freq_locked]
set_output_delay -clock ref_clk 2.0 [get_ports otw*]
