.PHONY: build test install uninstall status lint clean

build:
	mkdir -p build
	swiftc -O src/awake-on-ac.swift -o build/awake-on-ac

# Smoke test that changes nothing on the system
test: build
	./build/awake-on-ac --version
	./build/awake-on-ac --dry-run --once

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

status:
	./scripts/status.sh

# Validates the scripts and the rendered templates without installing them
lint:
	shellcheck -x scripts/*.sh
	sed "s/__USER__/$$(id -un)/g" sudoers/awake-on-ac.template > build/sudoers.check
	/usr/sbin/visudo -cf build/sudoers.check
	sed -e "s|__BIN__|/tmp/awake-on-ac|g" -e "s|__LOG__|/tmp/awake-on-ac.log|g" \
		launchd/io.github.alejandro945.awake-on-ac.plist.template > build/agent.plist
	plutil -lint build/agent.plist

clean:
	rm -rf build
