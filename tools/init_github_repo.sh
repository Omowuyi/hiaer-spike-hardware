#!/bin/bash
# Initialize HiAER-Spike Hardware GitHub Repository
# Run on crisdsc0 where git is configured for omowuyi
set -e

REPO_DIR="/home/omowuyi/hiaer-spike-hardware"

if [ -d "$REPO_DIR" ]; then
    echo "ERROR: $REPO_DIR already exists. Remove or rename it first."
    exit 1
fi

echo "=== Creating repository at $REPO_DIR ==="
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

git init
git config user.name "Omowuyi Olajide"
git config user.email "omowuyi@gmail.com"

# Copy documentation (user should have extracted the tar.gz here first)
echo "=== Copying documentation ==="
# The docs/ directory should already be in place from the tar.gz extraction

# Copy working software from backup
echo "=== Copying working software state ==="
mkdir -p software/working_state software/patches
if [ -d "/home/omowuyi/L6j_working_software" ]; then
    for f in api.py neuron_models.py fpga_controller.py network.py test_bitstream_hardware_fast.py; do
        if [ -f "/home/omowuyi/L6j_working_software/$f" ]; then
            cp "/home/omowuyi/L6j_working_software/$f" software/working_state/
            echo "  Copied $f"
        fi
    done
fi

# Copy patch scripts if they exist
for f in fix_coreid_crisdsc0.py fix_tdest_crisdsc2.py patch_16core.py; do
    if [ -f "/home/omowuyi/$f" ]; then
        cp "/home/omowuyi/$f" software/patches/
        echo "  Copied patch: $f"
    fi
done

# Copy test scripts
mkdir -p scripts
for f in run_all_tests.sh run_all_tests_multicore.sh; do
    if [ -f "/home/omowuyi/$f" ]; then
        cp "/home/omowuyi/$f" scripts/
        echo "  Copied script: $f"
    fi
done

# Create .gitignore
cat > .gitignore << 'GITEOF'
*.bit
*.bin
__pycache__/
*.pyc
*.runs/
*.cache/
*.hw/
*.ip_user_files/
*.jou
*.log
.Xil/
.DS_Store
.vscode/
.idea/
GITEOF

# Create dependency record
cat > software/commits.txt << 'COMMITEOF'
# Verified working software dependencies (June 2026)
hs_api:           testing-suite branch e526b6f (infrastructure), fb811b4 (test files)
hs_bridge:        1e3a114 (with patches from L6d backup)
connectome_utils:  dev branch, 181f8a8

# Locations on crisdsc0:
hs_api:           /home/omowuyi/testing/hs_api/
hs_bridge:        /home/omowuyi/testing/hs_bridge/
connectome_utils:  /home/omowuyi/testing/connectome_utils/
Working backup:   /home/omowuyi/L6j_working_software/
L6d backup:       /home/omowuyi/L6d_backup_software/
COMMITEOF

# Create bitstream inventory
cat > bitstreams/README.md << 'BSEOF'
# Bitstream Inventory

Bitstreams are stored on crisdsc0 at `/bitstreams/`. Too large for git (~30MB each).

| Filename | Version | Cores | Status |
|----------|---------|-------|--------|
| multi_neuron_type_param_mem_fix_08132024.bit | 2024 ref | 1 | Reference (64.24% DVS) |
| sixteen_core_top_L6m.bit | L6m | 1 | Verified baseline (42/42, 56.60%) |
| sixteen_core_top_multicore_1.bit | multicore_1 | 16 | tdest bug, core 0 only |
| sixteen_core_top_multicore_2.bit | multicore_2 | 16 | tdest fix, validating |
BSEOF

# Initial commit
git add -A
git commit -m "Initial commit: Complete HiAER-Spike hardware documentation

Bitstream history: 2024 reference through L6m baseline to 16-core multicore
- Every RTL edit documented with Verilog code
- Software configuration for each bitstream version
- Neuron parameter encoding (write_neuron_type bit fields)
- 16-core multicore design with tdest routing fix
- DVS accuracy gap root cause (XDMA IP version)
- Roadmap: NoC, Firefly, 40-FPGA cluster (8 FPGAs x 5 servers)
- 10 critical debugging lessons
- Working software state backup"

echo ""
echo "=== Repository initialized at $REPO_DIR ==="
echo ""
echo "Push to GitHub:"
echo "  cd $REPO_DIR"
echo "  gh repo create hiaer-spike-hardware --public --source=. --push"
echo ""
echo "Or manually:"
echo "  git remote add origin git@github.com:omowuyi/hiaer-spike-hardware.git"
echo "  git branch -M main"
echo "  git push -u origin main"
