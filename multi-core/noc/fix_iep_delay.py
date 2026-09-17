#!/usr/bin/env python3
"""
Fix internal_events_processor.v:
  1. Fix multi-driven net: move delay_add defaults to correct always block
  2. Pipeline delay match: pre-register dm comparison using uram_raddr
  3. Use registered dm signals in URAM write data (removes ~1.5 ns from critical path)
"""
import sys

IEP_PATH = "/home/omowuyi/single_core_a/single_core/multi_core.srcs/sources_1/imports/internal_events_processor.v"
BACKUP_PATH = IEP_PATH + ".bak_before_delay_fix"

with open(IEP_PATH, 'r') as f:
    content = f.read()

# Verify it's the original (unfixed) version
assert content.count("Default assignments prevent latches for delay signals") == 1, \
    "File doesn't look like the original IEP"
assert content.count("delay_add_pending = 1'b0;") == 1, \
    "delay_add_pending default not found exactly once"

# Save backup
with open(BACKUP_PATH, 'w') as f:
    f.write(content)
print(f"Backup saved to {BACKUP_PATH}")

# ============================================================
# FIX 1: Remove delay defaults from FIRST always block
# ============================================================
# Remove the 5 defaults + comment from the first always block
old_first_block = """    // Default assignments prevent latches for delay signals
    delay_add_pending = 1'b0;
    delay_add_addr_comb = 13'd0;
    delay_add_group_comb = 4'd0;
    dm_upper = 1'b0;
    dm_lower = 1'b0;
    for (i = 0; i < NEURON_GROUPS; i=i+1) begin"""

new_first_block = """    for (i = 0; i < NEURON_GROUPS; i=i+1) begin"""

assert old_first_block in content, "Could not find first always block pattern"
content = content.replace(old_first_block, new_first_block)
print("FIX 1: Removed delay defaults from first always block")

# ============================================================
# FIX 2: Add delay defaults to SECOND always block + pipeline
# ============================================================
# Find the start of the URAM write data always block
old_second_block = """    if (curr_state==STATE_INIT_URAM) begin"""

new_second_block = """    // FIX: delay defaults must be in same always block as assignments (multi-driven net fix)
    delay_add_pending = 1'b0;
    delay_add_addr_comb = 13'd0;
    delay_add_group_comb = 4'd0;
    // FIX: Use PRE-REGISTERED delay match signals (dm_match_pipe/dm_is_upper_pipe)
    // instead of computing full 13-bit comparison in combinational path.
    // The expensive comparisons are absorbed into register setup time.
    dm_upper = 1'b0;
    dm_lower = 1'b0;
    if (curr_state==STATE_INIT_URAM) begin"""

assert old_second_block in content, "Could not find second always block pattern"
content = content.replace(old_second_block, new_second_block, 1)
print("FIX 2: Added delay defaults to second always block")

# ============================================================
# FIX 3: Add pipeline registers for delay match
# ============================================================
# Add after the delay sequential management always block
old_delay_seq = """always @(*) begin
    // FIX: delay defaults must be in same always block as assignments (multi-driven net fix)
    delay_add_pending = 1'b0;"""

new_delay_seq = """// =========================================================================
// TIMING FIX: Pre-register delay match comparison
// The delay match logic (13-bit addr compare + 4-bit counter check + AND gates)
// was adding ~1.5 ns to the Phase 0 URAM write combinational path.
// By pre-registering using uram_raddr (which equals uram_waddr on the next cycle),
// the expensive comparisons are absorbed into register setup time.
// What remains in the combinational path: 1 registered bit + 4-bit constant match = ~0.1 ns
// =========================================================================
reg dm_match_pipe;      // Registered: delay_pending && counter==0 && addr match
reg dm_is_upper_pipe;   // Registered: uram_raddr[0] (upper/lower half-word)

always @(posedge clk) begin
    if (~resetn) begin
        dm_match_pipe <= 1'b0;
        dm_is_upper_pipe <= 1'b0;
    end else begin
        // Pre-compute delay match one cycle ahead using uram_raddr
        // On the next cycle, uram_waddr = uram_raddr (latched), so this aligns correctly
        dm_match_pipe <= delay_pending && (delay_counter == 4'd0) && (delay_addr == uram_raddr[12:0]);
        dm_is_upper_pipe <= uram_raddr[0];
    end
end

always @(*) begin
    // FIX: delay defaults must be in same always block as assignments (multi-driven net fix)
    delay_add_pending = 1'b0;"""

content = content.replace(old_delay_seq, new_delay_seq)
print("FIX 3: Added pipeline registers for delay match")

# ============================================================
# FIX 4: Replace combinational dm_upper/dm_lower with pipelined version
# ============================================================
# Replace all occurrences of the full combinational dm computation
# There are 2 occurrences (upper half-word and lower half-word in the for loop)

old_dm_upper = """            dm_upper = delay_pending && (delay_counter == 4'd0) &&
                       (delay_addr == uram_waddr[i]) && (delay_group == i[3:0]) && uram_waddr[i][0];"""

new_dm_upper = """            // TIMING FIX: Use pre-registered match (absorbs 13-bit compare into register)
            dm_upper = dm_match_pipe && (delay_group == i[3:0]) && dm_is_upper_pipe;"""

old_dm_lower = """            dm_lower = delay_pending && (delay_counter == 4'd0) &&
                       (delay_addr == uram_waddr[i]) && (delay_group == i[3:0]) && !uram_waddr[i][0];"""

new_dm_lower = """            // TIMING FIX: Use pre-registered match (absorbs 13-bit compare into register)
            dm_lower = dm_match_pipe && (delay_group == i[3:0]) && !dm_is_upper_pipe;"""

assert content.count(old_dm_upper) == 1, f"dm_upper pattern found {content.count(old_dm_upper)} times, expected 1"
assert content.count(old_dm_lower) == 1, f"dm_lower pattern found {content.count(old_dm_lower)} times, expected 1"

content = content.replace(old_dm_upper, new_dm_upper)
content = content.replace(old_dm_lower, new_dm_lower)
print("FIX 4: Replaced combinational dm with pipelined version")

# ============================================================
# VERIFY
# ============================================================
# Multi-driven net fix: delay_add_pending default should appear exactly once
assert content.count("delay_add_pending = 1'b0;") == 1, "delay_add_pending default count wrong"
# Pipeline: dm_match_pipe should appear multiple times
assert content.count("dm_match_pipe") >= 4, "dm_match_pipe not found enough times"
# Old combinational dm should be gone
assert "delay_addr == uram_waddr[i]" not in content, "Old combinational dm still present!"
# delay_add_pending assignments in logic should still exist (in spike detection)
assert content.count("delay_add_pending = 1'b1;") == 2, "delay_add_pending logic assignments changed"

print("\nAll verifications passed.")

# Write
with open(IEP_PATH, 'w') as f:
    f.write(content)
print(f"Written to {IEP_PATH}")
print(f"Lines: {len(content.splitlines())}")
