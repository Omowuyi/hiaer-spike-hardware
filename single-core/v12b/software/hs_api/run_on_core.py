# Run a pytest suite with every CRI_network defaulting to the given core.
# Usage: python run_on_core.py <core> <pytest args...>
import sys, functools
CORE = int(sys.argv[1])
import hs_api.api as api
_orig = api.CRI_network.__init__
@functools.wraps(_orig)
def _init(self, *a, **k):
    k.setdefault("coreID", CORE)
    return _orig(self, *a, **k)
api.CRI_network.__init__ = _init
import pytest
print("running on core", CORE, flush=True)
sys.exit(pytest.main(sys.argv[2:]))
