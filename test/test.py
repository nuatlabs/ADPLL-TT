# SPDX-FileCopyrightText: © 2026 NUAT Labs
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Starting ADPLL Tiny Tapeout Cocotb Test")

    # Set the reference clock period to 80 ns (12.5 MHz)
    clock = Clock(dut.clk, 80, unit="ns")
    cocotb.start_soon(clock.start())

    # Assert Reset
    dut._log.info("Asserting Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)

    # Release Reset
    dut._log.info("Releasing Reset")
    dut.rst_n.value = 1

    # Run for 100 reference clock cycles
    dut._log.info("Running ADPLL acquisition...")
    await ClockCycles(dut.clk, 100)

    # Verify that the output pins are active and driven
    dut._log.info(f"uo_out value: {dut.uo_out.value}")
    dut._log.info(f"uio_out value: {dut.uio_out.value}")

    # Check that outputs are not high-Z or undefined
    assert dut.uo_out.value.is_resolvable, "uo_out should be resolved to a valid binary value"
    assert dut.uio_out.value.is_resolvable, "uio_out should be resolved to a valid binary value"

    dut._log.info("ADPLL test completed successfully!")
