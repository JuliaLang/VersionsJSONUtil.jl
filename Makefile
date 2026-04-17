# Usage: make versions.json

JULIA ?= julia +1.10

# This is the default target:
# It's a phony target because you might want to re-build versions.json even if none of the
# files in this repo have changed.
.PHONY: versions.json
versions.json:
	JULIA_LOAD_PATH='@:@stdlib' $(JULIA) --startup-file=no --project -e 'import Pkg; Pkg.instantiate(); Pkg.precompile()'
	JULIA_LOAD_PATH='@' $(JULIA) --startup-file=no --project -e 'import VersionsJSONUtil; VersionsJSONUtil.main("versions.json")'
