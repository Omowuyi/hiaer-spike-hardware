#!/bin/bash
# Flash L6m bitstream and set up PCIe/DMA
set -e
sudo /bitstreams/scripts/flash.sh /bitstreams/sixteen_core_top_L6m.bit
sleep 3; echo 1 | sudo tee /sys/bus/pci/rescan > /dev/null
sleep 3; sudo modprobe adxdma
echo "4144 0902" | sudo tee /sys/bus/pci/drivers/adxdma/new_id > /dev/null 2>&1 || true
sudo chmod 666 /dev/adxdma0*
echo "L6m flashed and ready"
