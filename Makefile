NVIM ?= nvim
STYLUA ?= $(shell command -v stylua 2>/dev/null || echo $(HOME)/.local/share/nvim/mason/bin/stylua)

# `make test` runs every spec, `make test FILTER=git` only specs whose file name contains "git".
.PHONY: test smoke lint fmt check

test:
	$(NVIM) --clean -l tests/run.lua $(FILTER)

# `nvim diff` goes through VimEnter, which `nvim -l` never fires: run a real startup instead.
smoke:
	sh tests/smoke.sh

lint:
	$(STYLUA) --check lua plugin tests

fmt:
	$(STYLUA) lua plugin tests

check: lint test smoke
