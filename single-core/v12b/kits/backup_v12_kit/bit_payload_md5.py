#!/usr/bin/env python3
"""bit_payload_md5.py FILE.bit -- md5 of a bitstream from its sync word (AA 99 55 66) onward.  The .bit header carries
the build date and time, so two builds of the same design differ there; the configuration data after the sync word is
what must match."""
import sys, hashlib
b = open(sys.argv[1], "rb").read(); i = b.find(bytes.fromhex("AA995566"))
if i < 0: sys.exit("no sync word in %s" % sys.argv[1])
print("%s  %s (payload from byte %d, %d bytes)" % (hashlib.md5(b[i:]).hexdigest(), sys.argv[1], i, len(b) - i))
