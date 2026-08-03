#!/usr/bin/env python3
"""
Fix coreID encoding in fpga_controller.py for multicore support.
Run this on crisdsc0 after restoring from L6j_working_software backup.

Changes Format A encoding from:
    coreBits = np.binary_repr(coreID, 5) + '000'   (coreID in upper bits)
To:
    coreBits = '000' + np.binary_repr(coreID, 5)   (coreID in lower bits)

This matches Format B (np.binary_repr(coreID, 8)) so ALL command types
encode coreID in bits [499:496] where the fixed pcie_tdest_generator reads it.
"""

FC = '/home/omowuyi/testing/hs_bridge/hs_bridge/FPGA_Execution/fpga_controller.py'

with open(FC) as f:
    fc = f.read()

old = "np.binary_repr(coreID,5)+3*'0'"
new = "'000'+np.binary_repr(coreID,5)"

count = fc.count(old)
if count == 0:
    print("FAIL: Format A pattern not found. Is the file already patched or from wrong backup?")
    exit(1)

fc = fc.replace(old, new)

with open(FC, 'w') as f:
    f.write(fc)

print(f"fpga_controller.py: {count} Format A encodings fixed (coreID moved to lower bits).")
print("All command types now encode coreID in bits [499:496].")
