.PHONY: build test install icons

build:
	./scripts/build-app.sh

test:
	./scripts/test.sh

install: build
	./scripts/install.sh

icons:
	swift scripts/make-icons.swift "$(CURDIR)"
