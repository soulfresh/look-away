.DEFAULT_GOAL := help

SCHEME = LookAway
PROJECT = LookAway.xcodeproj
DESTINATION = 'platform=macOS'
CONFIGURATION = Debug

# Use .PHONY to declare targets that are not files.
.PHONY: configure build run test test-unit clean help

configure: ## Makes the XCode configuration available to sourcekit-lsp.
	xcode-build-server config \
		-project $(SCHEME).xcodeproj

build: ## Builds the application in Debug mode.
	xcodebuild build \
		-scheme $(SCHEME) \
		-project $(PROJECT) \
		-destination $(DESTINATION) \
		-configuration $(CONFIGURATION)

run: ## Runs the application in Debug mode.
	@open "DerivedData/$(SCHEME)/Build/Products/$(CONFIGURATION)/$(SCHEME).app"

TEST_ARGS =

test: ## Runs all test suites in the scheme. You can override TEST_ARGS to run specific tests to run. Example: make test TEST_ARGS="-only-testing LookAwayTests/BreakTests"
	xcodebuild test \
		-scheme $(SCHEME) \
		-project $(PROJECT) \
		-destination $(DESTINATION) \
		$(TEST_ARGS)

test-unit: ## Runs only the LookAwayTests target
	$(MAKE) test TEST_ARGS="-only-testing LookAwayTests"

clean: ## Cleans the build folder
	xcodebuild clean \
		-scheme $(SCHEME) \
		-project $(PROJECT)

help: ## Show this help message.
	@echo "Usage: make [target] [ARGUMENTS]"
	@echo ""
	@echo "Targets:"
	@awk -F ':.*?## ' '/^[a-zA-Z0-9_-]+:.*?## / { \
	 help[$$1] = $$2; \
	 if (length(help[$$1]) == 0) { help[$$1] = " "; } \
	 current = $$1; \
	} \
	/^# / { \
	 if (current) { \
		help[current] = help[current] "\n" substr($$0, 3); \
	 } \
	} \
	END { \
	 for (target in help) { \
		printf "  \033[36m%-20s\033[0m", target; \
		split(help[target], lines, "\n"); \
		for (i in lines) { \
		 if (i > 1) { printf "  %-20s", ""; } \
		 print lines[i]; \
		} \
	 } \
	}' $(MAKEFILE_LIST) | sort | awk -v width=$$(tput cols) 'BEGIN { indent = 24 } { \
	 if (length($$0) > width) { \
		s = $$0; \
		while (length(s) > 0) { \
		 line = substr(s, 1, width - indent); \
		 rem = substr(s, width - indent + 1); \
		 n = match(rem, / /); \
		 if (n) { \
			print substr(line, 1, length(line) + n); \
			s = substr(rem, n + 1); \
		 } else { \
			print s; \
			s = ""; \
		 } \
		 if (length(s) > 0) { printf "  %-22s", ""; } \
		} \
	 } else { print $$0; } \
	}'
