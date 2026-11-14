v14 build kit (crisdsc3, multi-core folder /data/omowuyi/multicore_noc_v13)

v14 = v13 (round 40's sources) + fix 31 (count packets wait for FIFO space) + fix 32 (pointer row waits for column FIFO room)
                                                 + fix 33 (Phase 2 keeps each neuron's spike flag)
                                                 + fix 34 (no pointer for inputs beyond num_inputs or of length 0)
                                                 + fix 35 (1,024-word pointer lanes: no drop, no stall)
                                                 + fix 32 (a pointer row waits until every column pointer FIFO it writes has room)
The sources are exactly noc16_v14d/src, the snapshot the v14 gate simulated.

Order:
 1. ./v14_kit/apply_v14.sh check   every verification (gate results, v13-state basis, v14 sources proven = v13 + fixes 31/32), nothing changed
 2. ./v14_kit/apply_v14.sh         copy into the project, core-1 taps, top tie-offs + R1, verify every file, elaboration gate
 3. ./v14_kit/run_v14_build.sh trial    synthesis, ILA, placement, post-placement timing, CDC review (hours)
 4. ./v14_kit/run_v14_build.sh finish   routing, timing, bitstream + probes (only if timing is met)
Output: v14_build/sixteen_core_noc_v14_ila.bit and .ltx (copied to the multi-core folder with md5).
The v13-state project imports are saved once in imports_before_v14.
