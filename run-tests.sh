#!/bin/sh
# Runs the Exposition test suites. Needs Lua 5.1, the interpreter WoW ships.
set -e
cd "$(dirname "$0")"
lua5.1 tests/run.lua
echo
lua5.1 tests/integration.lua
