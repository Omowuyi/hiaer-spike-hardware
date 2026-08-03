#!/usr/bin/env bash
# Restructure hiaer-spike-hardware into single-core / multi-core, with the NoC
# and Firefly work given their own trees.
#
# Uses git mv so history is preserved -- git log --follow keeps working on every
# RTL file that moves.
#
#   cd /home/omowuyi/hw-repo
#   bash migrate_repo_v2.sh
#   git status --short          # review before committing
#
# Creates the branch, moves what exists, scaffolds the rest.  Nothing is
# committed; nothing is deleted.

set -e

[ -d .git ] || { echo "ABORT: run from the root of the hiaer-spike-hardware clone."; exit 1; }
[ -d multi-core ] && { echo "ABORT: multi-core/ exists -- already migrated?"; exit 1; }

git rev-parse --verify restructure >/dev/null 2>&1 || git checkout -b restructure
git checkout restructure 2>/dev/null || true

# ---------------------------------------------------------------- layout ----
mkdir -p single-core/L6m/rtl
mkdir -p single-core/exp_psc/{rtl,patches,software,tests,sim,docs}
mkdir -p multi-core/noc/{rtl,patches,software,sim,docs}
mkdir -p multi-core/noc_exp_psc/{rtl,docs}
mkdir -p multi-core/firefly/docs
mkdir -p multi-core/server-to-server/docs
mkdir -p tools bitstreams

# ------------------------------------------------- move the L6m sources ------
if [ -d hardware_files/single_core_L6m ]; then
    for f in hardware_files/single_core_L6m/*; do
        [ -e "$f" ] && git mv "$f" single-core/L6m/rtl/
    done
    rmdir hardware_files/single_core_L6m hardware_files 2>/dev/null || true
    echo "  moved L6m RTL -> single-core/L6m/rtl/ (history preserved)"
fi

# ------------------------------------------------- move existing tooling -----
[ -f software/patches/fix_coreid_crisdsc0.py ] && \
    git mv software/patches/fix_coreid_crisdsc0.py single-core/exp_psc/software/ 2>/dev/null || true
[ -f scripts/init_github_repo.sh ] && git mv scripts/init_github_repo.sh tools/ 2>/dev/null || true
rmdir software/patches software scripts 2>/dev/null || true

# ------------------------------------------------------- placeholder docs ---
ph () {   # $1 path, $2 title, $3 note
    [ -f "$1" ] && return 0
    printf '# %s\n\n> TODO: %s\n' "$2" "$3" > "$1"
    echo "  scaffolded $1"
}

ph docs/00_platform_reference.md "Platform Reference" \
   "CMD opcodes, packet formats, URAM and HBM layout, clock domains"
ph docs/02_architecture.md "Execution Architecture" \
   "phases 0-4, microphase decomposition, 16-group URAM banking"
ph docs/04_verification_methodology.md "Verification Methodology" \
   "what separates a hardware-verified claim from a simulated or unverified one"

ph single-core/README.md "Single-Core Designs" \
   "feature matrix with per-feature verification status"
ph single-core/L6m/README.md "L6m -- Verified Baseline" \
   "42/42 hardware tests, DVS large 56.60%"
ph single-core/exp_psc/README.md "exp_psc -- Biological Neuron Model" \
   "eight features, 64-bit synapse format, delay, STDP, spike backpressure"
ph single-core/exp_psc/docs/FEATURES.md "Biological Features" \
   "per feature: mechanism, parameters, verification evidence"
ph single-core/exp_psc/docs/FIXES.md "RTL and Compiler Fixes" \
   "FIX A through Z: symptom, mechanism, fix, evidence"
ph single-core/exp_psc/docs/OPEN_ISSUES.md "Open Issues" \
   "microphase boundary, delay and STDP status, what is eliminated"
ph single-core/exp_psc/MANIFEST.md "Build Manifest" \
   "per build: RTL commit, software commits, content hashes, WNS, results"

ph multi-core/README.md "Multi-Core Designs" \
   "16-core NoC, inter-FPGA Firefly, inter-server fabric"
ph multi-core/noc/README.md "Network-on-Chip" \
   "4x4 crossbar: 4 clusters of 4 cores, L1 and L2"
ph multi-core/noc/docs/NOC.md "NoC Architecture" \
   "routers, injectors, L1/L2 buses, 32-bit packet format"
ph multi-core/noc/docs/ROUTING_TABLES.md "Routing Tables" \
   "256 entries per core indexed by spike_addr[16:9], 6-bit level+mask, CMD 15"
ph multi-core/noc/docs/PARTITIONING.md "Partitioning" \
   "hierarchical hypergraph, lambda-1 objective, 512-neuron granularity"
ph multi-core/noc/docs/VERIFICATION.md "NoC Verification" \
   "xsim testbenches and results per module"
ph multi-core/noc/MANIFEST.md "NoC Build Manifest" \
   "per build: commits, hashes, WNS, test results"

ph multi-core/noc_exp_psc/README.md "NoC + Biological Core" \
   "the merge: 16 biological cores on the crossbar"
ph multi-core/noc_exp_psc/docs/MERGE.md "Merge Notes" \
   "which files came from where, and why the NoC is orthogonal to the neuron model"
ph multi-core/noc_exp_psc/MANIFEST.md "Merged Build Manifest" \
   "per build: commits, hashes, WNS, results"

ph multi-core/firefly/README.md "Firefly -- Inter-FPGA" \
   "Aurora 64B/66B across 8 FPGAs in a server"
ph multi-core/firefly/docs/FIREFLY.md "Firefly Design" \
   "REMOTE encoding, remote destination table, TS buffering, barrier, relay"

ph multi-core/server-to-server/README.md "Server-to-Server" \
   "5 servers x 8 FPGAs x 16 cores = 640 cores"
ph multi-core/server-to-server/docs/SYSTEM.md "Full System" \
   "100G spike plane, three network planes"

ph bitstreams/MANIFEST.md "Bitstream Index" \
   "one entry per build; .bit files are NOT committed"

cat <<'DONE'

structure created.  Review, then commit in stages so each shows separately:

  git status --short
  git add -A && git commit -m "Restructure: separate single-core and multi-core designs"
  git push -u origin restructure

RTL and tooling still to copy in from the build machines:

  single-core/exp_psc/rtl/       7 files from single_core_exp_psc/.../imports/
  single-core/exp_psc/patches/   fix_spike_backpressure.py, add_microphase_diag.py,
                                 fix_delay_slot_reset.py, verify_rtl_state.py,
                                 xsim_prep.py
  single-core/exp_psc/software/  fix_syn64_spike_entries.py, fix_syn_delay_padding.py,
                                 fix_syn64_src.py, patch_syn_delay.py
  single-core/exp_psc/tests/     test_bio_features2.py, test_delay_construct.py,
                                 test_microphase_lowload.py, hbm_calibrate.py
  multi-core/noc/rtl/            7 NoC sources + noc_integration.v
  multi-core/noc/patches/        add_route_cmd15.py
  multi-core/noc/software/       noc_routing.py, noc_partition.py
  multi-core/noc/sim/            run_xsim.sh, tb_router.sv, tb_l1.sv, tb_l2.sv
  tools/                         verify_rtl_state.py

Bitstreams are deliberately not committed -- 68 MB each and they change every
build.  The manifests record commit, hashes, WNS and results, which is enough
to rebuild exactly.
DONE
