# SayTTS build wrapper around xcodebuild.

CONFIGURATION ?= Debug
PROJECT = SayTTS.xcodeproj
SCHEME = SayTTS
DERIVED = $(HOME)/Library/Developer/Xcode/DerivedData/SayTTS-acwezdtwubufazcortbxflwjeexx/Build/Products/$(CONFIGURATION)

.PHONY: build release test clean run

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Debug -destination 'platform=macOS' build

release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release -destination 'platform=macOS' build

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Debug -destination 'platform=macOS' test

# Launch the app with the settings panel open, for manual checks.
run: build
	open -a "$(DERIVED)/SayTTS.app" --args --open-settings

clean:
	rm -rf "$(HOME)/Library/Developer/Xcode/DerivedData/SayTTS-"*
