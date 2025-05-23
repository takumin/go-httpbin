# The version that will be used in docker tags (e.g. to push a
# go-httpbin:latest image use `make imagepush VERSION=latest)`
VERSION    ?= $(shell git rev-parse --short HEAD)
DOCKER_TAG ?= mccutchen/go-httpbin:$(VERSION)

# Built binaries will be placed here
DIST_PATH  	  ?= dist

# Default flags used by the test, testci, testcover targets
COVERAGE_PATH ?= coverage.txt
COVERAGE_ARGS ?= -covermode=atomic -coverprofile=$(COVERAGE_PATH)
TEST_ARGS     ?= -race

# 3rd party tools
FMT         := go run mvdan.cc/gofumpt@v0.7.0
LINT        := go run github.com/mgechev/revive@v1.7.0
REFLEX      := go run github.com/cespare/reflex@v0.3.1
STATICCHECK := go run honnef.co/go/tools/cmd/staticcheck@2025.1.1

# Host and port to use when running locally via `make run` or `make watch`
HOST ?= 127.0.0.1
PORT ?= 8080

# Determine the name of the static binary for the release build
GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
ifeq (x$(GOOS)x,xwindowsx)
GOENVS ?= GOOS=$(GOOS) GOARCH=$(GOARCH)
BINNAME ?= go-httpbin-$(GOOS)-$(GOARCH).exe
else
ifeq (x$(GOARCH)x,xarmx)
GOENVS ?= GOOS=$(GOOS) GOARCH=$(GOARCH) GOARM=$(GOARM)
BINNAME ?= go-httpbin-$(GOOS)-$(GOARCH)v$(GOARM)
else
GOENVS ?= GOOS=$(GOOS) GOARCH=$(GOARCH)
BINNAME ?= go-httpbin-$(GOOS)-$(GOARCH)
endif
endif

# =============================================================================
# build
# =============================================================================
build:
	mkdir -p $(DIST_PATH)
	CGO_ENABLED=0 go build -ldflags="-s -w" -o $(DIST_PATH)/go-httpbin ./cmd/go-httpbin
.PHONY: build

buildexamples: build
	./examples/build-all
.PHONY: buildexamples

buildtests:
	CGO_ENABLED=0 go test -ldflags="-s -w" -v -c -o $(DIST_PATH)/go-httpbin.test ./httpbin
.PHONY: buildtests

clean:
	rm -rf $(DIST_PATH) $(COVERAGE_PATH) .integrationtests
.PHONY: clean


# =============================================================================
# test & lint
# =============================================================================
test:
	go test $(TEST_ARGS) ./...
.PHONY: test

# Test command to run for continuous integration, which includes code coverage
# based on codecov.io's documentation:
# https://github.com/codecov/example-go/blob/b85638743b972bd0bd2af63421fe513c6f968930/README.md
testci: build buildexamples
	AUTOBAHN_TESTS=1 go test $(TEST_ARGS) $(COVERAGE_ARGS) ./...
.PHONY: testci

testcover: testci
	go tool cover -html=$(COVERAGE_PATH)
.PHONY: testcover

# Run the autobahn fuzzingclient test suite
testautobahn:
	AUTOBAHN_TESTS=1 AUTOBAHN_OPEN_REPORT=1 go test -v -run ^TestWebSocketServer$$ $(TEST_ARGS) ./...
.PHONY: autobahntests

lint:
	test -z "$$($(FMT) -d -e .)" || (echo "Error: $(FMT) failed"; $(FMT) -d -e . ; exit 1)
	go vet ./...
	$(LINT) -set_exit_status ./...
	$(STATICCHECK) ./...
.PHONY: lint


# =============================================================================
# run locally
# =============================================================================
run: build
	HOST=$(HOST) PORT=$(PORT) $(DIST_PATH)/go-httpbin
.PHONY: run

watch:
	$(REFLEX) -s -r '\.(go|html|tmpl)$$' make run
.PHONY: watch


# =============================================================================
# docker images
# =============================================================================
image:
	DOCKER_BUILDKIT=1 docker build -t $(DOCKER_TAG) .
.PHONY: image

imagepush:
	docker buildx create --name httpbin
	docker buildx use httpbin
	docker buildx build --push --platform linux/amd64,linux/arm64 -t $(DOCKER_TAG) .
	docker buildx rm httpbin
.PHONY: imagepush

# =============================================================================
# release build
# =============================================================================
release:
	mkdir -p $(DIST_PATH)
	CGO_ENABLED=0 $(GOENVS) go build -trimpath -ldflags '-s -w -buildid=' -o $(DIST_PATH)/$(BINNAME) ./cmd/go-httpbin
.PHONY: release
