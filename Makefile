# Prefer Lua 5.1-compatible tools to match Lightroom. See DEVELOPING.md
# for SDK compiler setup; override LUA and LUAC as needed.

PLUGIN := vaultphotos.lrplugin
SDK_LUAC := $(HOME)/Downloads/LrC_15/Lua Compiler/mac/luac
LUAC ?= $(if $(wildcard $(subst $() ,\ ,$(SDK_LUAC))),$(SDK_LUAC),luac)
LUA ?= $(if $(shell command -v luajit),luajit,lua)

.PHONY: all check

all: check

check:
	for t in tests/*_test.lua; do $(LUA) $$t || exit 1; done
	"$(LUAC)" -p $(PLUGIN)/*.lua
