# Sonocles
#
# The Swift package lives in app/ so a marketing site and docs can sit beside it
# without SwiftPM trying to build them. Every target here works from the repo
# root; nothing needs you to cd anywhere.

APP      := app
DIST     := dist
BUNDLE   := $(DIST)/Sonocles.app
CONFIG   ?= release
PORT     ?= 7357
SIGN_ID  ?= Developer ID Application: Artisan Build, Inc (83AD4SGJLW)

# Curl's -u only appends credentials when both are set, so the control targets
# work unauthenticated by default and lock down the moment you export these.
USER     ?=
PASS     ?=
AUTH     := $(if $(USER),-u $(USER):$(PASS),)

.DEFAULT_GOAL := help
.PHONY: help build test run baseline idle app launch install uninstall \
        status start stop events clean fmt lint

help: ## Show this help
	@echo "Sonocles — on-device speech sidecar"
	@echo
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  CONFIG=debug        build unoptimised (default: release)"
	@echo "  PORT=7357           control API port for status/start/stop"
	@echo "  USER=x PASS=y       credentials, when the control API is locked"

build: ## Build everything
	swift build -c $(CONFIG) --package-path $(APP)

test: ## Run the test suite
	swift test --package-path $(APP)

run: build ## Run the CLI monitor (Parakeet 160ms)
	$(APP)/.build/$(CONFIG)/sonocles-cli

baseline: build ## Run the CLI on Apple's engine, to compare against
	$(APP)/.build/$(CONFIG)/sonocles-cli --engine apple

idle: build ## Run the CLI with sockets up but capture off, for API testing
	$(APP)/.build/$(CONFIG)/sonocles-cli --idle

app: ## Build and sign Sonocles.app into dist/
	SIGN_ID="$(SIGN_ID)" CONFIG=$(CONFIG) $(APP)/Scripts/bundle.sh

launch: app ## Build the app and start it
	@pkill -f "Sonocles.app/Contents/MacOS/Sonocles" 2>/dev/null || true
	open $(BUNDLE)

install: app ## Copy the app to /Applications
	@pkill -f "Sonocles.app/Contents/MacOS/Sonocles" 2>/dev/null || true
	rm -rf /Applications/Sonocles.app
	cp -R $(BUNDLE) /Applications/Sonocles.app
	@echo "installed /Applications/Sonocles.app"

uninstall: ## Remove the app from /Applications
	@pkill -f "Sonocles.app/Contents/MacOS/Sonocles" 2>/dev/null || true
	rm -rf /Applications/Sonocles.app

status: ## Ask the running sidecar what it is doing
	@curl -s $(AUTH) http://127.0.0.1:$(PORT)/status && echo

start: ## Tell the running sidecar to begin listening
	@curl -s $(AUTH) -X POST http://127.0.0.1:$(PORT)/start && echo

stop: ## Tell the running sidecar to stop listening
	@curl -s $(AUTH) -X POST http://127.0.0.1:$(PORT)/stop && echo

events: ## Tail the event stream (-N matters: without it curl buffers)
	@curl -sN http://127.0.0.1:$(PORT)/events

fmt: ## Format the Swift sources in place
	@xcrun swift-format --in-place --recursive $(APP)/Sources $(APP)/Tests

lint: ## Check formatting without changing anything
	@xcrun swift-format lint --recursive $(APP)/Sources $(APP)/Tests

clean: ## Remove build products
	rm -rf $(APP)/.build $(DIST)
