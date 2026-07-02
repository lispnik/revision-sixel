# Makefile --- tvision-sixel
#
# Usage:
#   make        # compile/load the system (build check)
#   make test   # headless (no-tty) test suite
#   make clean  # remove this project's fasl cache

SBCL ?= sbcl

define asdf-load
$(SBCL) --non-interactive \
	--eval '(require :asdf)' \
	--eval '(handler-bind ((warning (function muffle-warning))) $(1))' \
	--eval '(uiop:quit 0)'
endef

SOURCES := tvision-sixel.asd $(wildcard src/*.lisp)

.DEFAULT_GOAL := all
.PHONY: all test bin clean

all: $(SOURCES)
	$(call asdf-load,(asdf:load-system "tvision-sixel"))

test: $(SOURCES) $(wildcard tests/*.lisp)
	$(call asdf-load,(asdf:test-system "tvision-sixel"))

# Standalone, self-contained executable (samples baked in).
bin: tvision-sixel-demo
tvision-sixel-demo: $(SOURCES) build.lisp
	$(SBCL) --script build.lisp

clean:
	rm -rf $(HOME)/.cache/common-lisp/*/$(CURDIR)
	rm -f tvision-sixel-demo
