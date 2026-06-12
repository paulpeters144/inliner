TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/

.PHONY: test lint lint-lua format format-lua install-hooks

test:
	@nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}' }"

lint-lua:
	@stylua --check lua/ plugin/ tests/
	@luacheck lua/ plugin/ tests/

lint: lint-lua

format-lua:
	@stylua lua/ plugin/ tests/

format: format-lua

install-hooks: scripts/pre-commit
	@cp scripts/pre-commit .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
