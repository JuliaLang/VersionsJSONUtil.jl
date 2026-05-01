# Usage:
# make build
# make test

ifdef CI
JULIA ?= julia
else
JULIA ?= julia +1.10
endif

# This is the default target:
# It's a phony target because you might want to re-build versions.json even if none of the
# files in this repo have changed.
.PHONY: build
build: _instantiate
	JULIA_LOAD_PATH='@' $(JULIA) --startup-file=no --project -e 'import VersionsJSONUtil; VersionsJSONUtil.main(".")'

# These are the post-build tests:
.PHONY: test
test: test-full

.PHONY: test-full
test-full: _instantiate
	JULIA_LOAD_PATH='@:@stdlib' $(JULIA) --startup-file=no --project test/post_build.jl versions.json full

.PHONY: test-partial
test-partial: _instantiate
	JULIA_LOAD_PATH='@:@stdlib' $(JULIA) --startup-file=no --project test/post_build.jl versions.json partial

.PHONY: check-schema
check-schema:
	(cd test/node && npx ajv -s ../../schema.json -d ../../versions.json)

# ------------------------------------------------------------------------------------------

.PHONY: _instantiate
_instantiate:
	JULIA_LOAD_PATH='@:@stdlib' $(JULIA) --startup-file=no --project -e 'import Pkg; Pkg.instantiate(); Pkg.precompile()'

.PHONY: _npm_ci
_npm_ci:
	(cd test/node && npm ci)


.PHONY: clean
clean:
	$(RM) -v internal.json

.PHONY: nuke
nuke:
	$(RM) -v internal.json
	$(RM) -v versions.json

.PHONY: _purge_node_modules
_purge_node_modules:
	$(RM) -r test/node/node_modules/

.PHONY: purge_download_cache_dir
purge_download_cache_dir:
	$(RM) -r cache/
