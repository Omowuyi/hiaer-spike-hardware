v12 build kit (crisdsc3).  Sources: simfix22 = fixes 1-28 + plasticity, gated by round 33.
  1. apply_v12.sh check   every verification, nothing changed (seconds)
  2. apply_v12.sh         gate on round 33 (ROUND33 GATE: PASS in /tmp/sim_round21_gate.log, from round21b_kit/gate_round21.sh); verify the project against the simulation base; copy simfix22's
                          8 changed files + 4 plasticity modules; top-level tie-offs (fix_top.py); verify every file
                          and all 22 ILA taps; add the modules to the Vivado project; elaboration gate (0 errors,
                          0 multi-driven; width warnings listed in v12_build/elab_width_warnings.txt)
  3. run_v12_build.sh trial      synthesis, ILA on core 1, placement; per-SLR utilization, post-placement timing,
                                 placed checkpoint (v12_build/placed.dcp)
  4. run_v12_build.sh finish     routing, timing, DRC, routed checkpoint, bitstream + probe file (only if timing is met)
  undo_v12.sh             restore the project's imports and remove the modules from the project
build_v12.tcl: build_ila.tcl's tap verification, core-1 identification, ILA settings, directives and false path,
verbatim; adds reports and checkpoints and splits trial / finish.
