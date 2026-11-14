#This is the target constraints file.
#Doing setup debug in Vivado should cause debug constraints to be written into this file.

# In Vivado 2019.1, Vivado Hardware Manager seems to have a problem
# communicating with the HBM APBs if the debug hub clock is different to the
# HBM's APB_n_PCLK signals. So ensure that they are the same signal.


