APP := build/Pixel Workers Hub.app
INSTALLED := /Applications/Pixel Workers Hub.app

.PHONY: app install run test hooks unhooks uninstall icon screenshot clean

# Build the app into build/
app:
	@scripts/build-app.sh

# Build, copy to /Applications and open it
install: app
	@pkill -x PixelWorkersHub 2>/dev/null || true
	@rm -rf "$(INSTALLED)"
	@cp -R "$(APP)" "$(INSTALLED)"
	@open "$(INSTALLED)"
	@echo "Installed to $(INSTALLED). Look for the pixel worker in your menu bar."

# Run from the source tree, without bundling
run:
	swift run PixelWorkersHub

test:
	swift test

# Turn detailed status (Claude Code hooks) on or off from the command line
hooks:
	@"$(INSTALLED)/Contents/MacOS/PixelWorkersHub" --install-hooks
unhooks:
	@"$(INSTALLED)/Contents/MacOS/PixelWorkersHub" --remove-hooks

# Remove the hooks, quit the app and delete it
uninstall:
	@if [ -x "$(INSTALLED)/Contents/MacOS/PixelWorkersHub" ]; then "$(INSTALLED)/Contents/MacOS/PixelWorkersHub" --remove-hooks; fi
	@pkill -x PixelWorkersHub 2>/dev/null || true
	@rm -rf "$(INSTALLED)"
	@echo "Removed $(INSTALLED)."

# Redraw Support/AppIcon.icns from the sprites
icon:
	@swift scripts/make-icon.swift

clean:
	rm -rf .build build

# Redraw the README screenshots from made-up sessions
screenshot:
	@swift scripts/screenshot.swift
