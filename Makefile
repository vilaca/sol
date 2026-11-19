.PHONY: help bootstrap project test test-core test-app test-oldest sim sim-oldest device test-device dev-ipa beta release icon clean

help: ## List the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

bootstrap: ## One-time setup: tools, signing config, Xcode project
	scripts/bootstrap.sh

project: ## Regenerate Sol.xcodeproj from project.yml
	xcodegen generate

test: test-core test-app ## All tests

test-core: ## Game-rule unit tests on the Mac (fast, no simulator)
	scripts/test-core.sh

test-app: ## App unit + UI tests on an iPhone 13 simulator
	scripts/test-app.sh

test-oldest: ## App tests on the oldest supported iOS (16) — install that runtime first
	SIM_DEVICE="iPhone 8" SIM_RUNTIME=16 scripts/test-app.sh

sim: ## Build and run the Dev app on an iPhone 13 simulator
	scripts/simulator.sh

sim-oldest: ## Build and run on an iPhone 8 simulator with iOS 16
	SIM_DEVICE="iPhone 8" SIM_RUNTIME=16 scripts/simulator.sh

device: ## Build, install and launch the Dev app on a connected iPhone
	scripts/device.sh

test-device: ## Run the unit + UI tests on a connected iPhone
	scripts/device.sh --test

dev-ipa: ## Development-signed IPA for registered test iPhones -> dist/
	bundle exec fastlane dev

beta: ## Test release: build and upload to TestFlight
	bundle exec fastlane beta

release: ## Upload a build to App Store Connect for review (you submit it there)
	bundle exec fastlane release

icon: ## Redraw the app icon
	python3 scripts/make-icon.py

clean: ## Remove build output and the generated project
	rm -rf .build dist Sol.xcodeproj
