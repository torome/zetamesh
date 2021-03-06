GOVER := $(shell go version)

GOOS    := $(if $(GOOS),$(GOOS),$(shell go env GOOS))
GOARCH  := $(if $(GOARCH),$(GOARCH),amd64)
GOENV   := GO111MODULE=on CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH)
GO      := $(GOENV) go
GOBUILD := $(GO) build $(BUILD_FLAG)
GOTEST  := GO111MODULE=on CGO_ENABLED=1 $(GO) test -p 3
SHELL   := /usr/bin/env bash

COMMIT    := $(shell git describe --no-match --always --dirty)
BRANCH    := $(shell git rev-parse --abbrev-ref HEAD)
BUILDTIME := $(shell date '+%Y-%m-%d %T %z')

REPO := github.com/lonng/zetamesh
LDFLAGS := -w -s
LDFLAGS += -X "$(REPO)/version.GitHash=$(COMMIT)"
LDFLAGS += -X "$(REPO)/version.GitBranch=$(BRANCH)"
LDFLAGS += $(EXTRA_LDFLAGS)

FILES     := $$(find . -name "*.go")

FAILPOINT_ENABLE  := $$(find $$PWD/ -type d | grep -vE "(\.git|tools)" | xargs tools/bin/failpoint-ctl enable)
FAILPOINT_DISABLE := $$(find $$PWD/ -type d | grep -vE "(\.git|tools)" | xargs tools/bin/failpoint-ctl disable)

default: fmt proto zetamesh

zetamesh:
	$(GOBUILD) -ldflags '$(LDFLAGS)' -o bin/zetamesh .

fmt:
	@echo "gofmt (simplify)"
	@gofmt -s -l -w $(FILES) 2>&1

proto:
	@cd protos && protoc --go_out=plugins=grpc:../ ./*.proto

# Deploy to remote server
deploy:
	./deploy.sh

# Lint tools
check: lint vet fmt check-static

lint:tools/bin/revive
	@tools/bin/revive -formatter friendly -config tools/check/revive.toml $(FILES)

vet:
	$(GO) vet ./...

clean:
	@rm -rf bin

cover-dir:
	rm -rf cover
	mkdir -p cover

# Run tests
unit-test: cover-dir
	$(GOTEST) ./... -covermode=count -coverprofile cover/cov.unit-test.out

test: failpoint-enable unit-test
	@$(FAILPOINT_DISABLE)

check-static: tools/bin/golangci-lint
	tools/bin/golangci-lint run --timeout 5m ./...

coverage:
	GO111MODULE=off go get github.com/wadey/gocovmerge
	gocovmerge cover/* | grep -vE ".*.pb.go|.*__failpoint_binding__.go" > "cover/all_cov.out"
ifeq ("$(JenkinsCI)", "1")
	@bash <(curl -s https://codecov.io/bash) -f cover/all_cov.out -t $(CODECOV_TOKEN)
else
	go tool cover -html "cover/all_cov.out" -o "cover/all_cov.html"
endif

failpoint-enable: tools/bin/failpoint-ctl
	@$(FAILPOINT_ENABLE)

failpoint-disable: tools/bin/failpoint-ctl
	@$(FAILPOINT_DISABLE)

tools/bin/failpoint-ctl: go.mod
	$(GO) build -o $@ github.com/pingcap/failpoint/failpoint-ctl

tools/bin/revive: tools/check/go.mod
	cd tools/check; \
	$(GO) build -o ../bin/revive github.com/mgechev/revive

tools/bin/golangci-lint: tools/check/go.mod
	cd tools/check; \
	$(GO) build -o ../bin/golangci-lint github.com/golangci/golangci-lint/cmd/golangci-lint

.PHONY: build package
