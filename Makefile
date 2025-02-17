#!/usr/bin/make -f

MAKE:=make
SHELL:=bash
GOVERSION:=$(shell \
    go version | \
    awk -F'go| ' '{ split($$5, a, /\./); printf ("%04d%04d", a[1], a[2]); exit; }' \
)
MINGOVERSION:=00010009
MINGOVERSIONSTR:=1.9

EXTERNAL_DEPS = \
	github.com/appscode/g2 \
	github.com/appscode/g2/worker \
	github.com/appscode/g2/client \
	github.com/appscode/g2/pkg/runtime \
	github.com/kdar/factorlog \
	github.com/sevlyar/go-daemon \
	github.com/prometheus/client_golang/prometheus \
	github.com/prometheus/client_golang/prometheus/promhttp \
	github.com/davecgh/go-spew/spew \
	golang.org/x/tools/cmd/goimports \
	github.com/jmhodges/copyfighter \
	github.com/golangci/golangci-lint/cmd/golangci-lint \

CMDS = $(shell cd ./cmd && ls -1)
BINPATH = $(shell if test -d "$$GOPATH"; then echo "$$GOPATH/bin"; else echo "~/go/bin"; fi)

all: deps fmt build

deps: versioncheck dump
	set -e; for DEP in $(EXTERNAL_DEPS); do \
		go get $$DEP; \
	done

updatedeps: versioncheck
	set -e; for DEP in $(EXTERNAL_DEPS); do \
		go get -u $$DEP; \
	done

dump:
	if [ $(shell grep -rc Dump *.go ./cmd/*/*.go | grep -v :0 | grep -v dump.go | wc -l) -ne 0 ]; then \
		sed -i.bak 's/\/\/ +build.*/\/\/ build with debug functions/' dump.go; \
	else \
		sed -i.bak 's/\/\/ build.*/\/\/ +build ignore/' dump.go; \
	fi
	rm -f dump.go.bak

build: dump
	set -e; for CMD in $(CMDS); do \
		cd ./cmd/$$CMD && go build -ldflags "-s -w -X main.Build=$(shell git rev-parse --short HEAD)" -o ../../$$CMD; cd ../..; \
	done

build-linux-amd64: dump
	set -e; for CMD in $(CMDS); do \
		cd ./cmd/$$CMD && GOOS=linux GOARCH=amd64 go build -ldflags "-s -w -X main.Build=$(shell git rev-parse --short HEAD)" -o ../../$$CMD.linux.amd64; cd ../..; \
	done

build-windows-i386:
	set -e; for CMD in $(CMDS); do \
		cd ./cmd/$$CMD && GOOS=windows GOARCH=386 CGO_ENABLED=0 go build -ldflags "-s -w -X main.Build=$(shell git rev-parse --short HEAD)" -o ../../$$CMD.windows.i386.exe; cd ../..; \
	done

build-windows-amd64:
	set -e; for CMD in $(CMDS); do \
		cd ./cmd/$$CMD && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "-s -w -X main.Build=$(shell git rev-parse --short HEAD)" -o ../../$$CMD.windows.amd64.exe; cd ../..; \
	done

send_gearman: *.go cmd/send_gearman/*.go
	cd ./cmd/send_gearman && go build -ldflags "-s -w -X main.Build=$(shell git rev-parse --short HEAD)" -o ../../send_gearman

send_gearman.exe: *.go cmd/send_gearman/*.go
	cd ./cmd/send_gearman && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "-s -w -X main.Build=$(shell git rev-parse --short HEAD)" -o ../../send_gearman.exe

debugbuild: deps fmt
	go build -race -ldflags "-X main.Build=$(shell git rev-parse --short HEAD)"
	set -e; for CMD in $(CMDS); do \
		cd ./cmd/$$CMD && go build -race -ldflags "-X main.Build=$(shell git rev-parse --short HEAD)"; cd ../..; \
	done

test: fmt dump
	go test -short -v -timeout=1m
	if grep -rn TODO: *.go ./cmd/; then exit 1; fi
	if grep -rn Dump *.go ./cmd/*/*.go | grep -v dump.go; then exit 1; fi

longtest: fmt dump
	go test -v -timeout=1m

citest: deps
	#
	# Checking gofmt errors
	#
	if [ $$(gofmt -s -l . ./cmd/ | wc -l) -gt 0 ]; then \
		echo "found format errors in these files:"; \
		gofmt -s -l .; \
		exit 1; \
	fi
	#
	# Checking TODO items
	#
	if grep -rn TODO: *.go ./cmd/; then exit 1; fi
	#
	# Checking remaining debug calls
	#
	if grep -rn Dump *.go ./cmd/*/*.go | grep -v dump.go; then exit 1; fi
	#
	# Darwin and Linux should be handled equal
	#
	diff mod_gearman_worker_linux.go mod_gearman_worker_darwin.go
	#
	# Run other subtests
	#
	$(MAKE) copyfighter
	$(MAKE) golangci
	$(MAKE) fmt
	#
	# Normal test cases
	#
	go test -v -timeout=1m
	#
	# Benchmark tests
	#
	go test -v -timeout=1m -bench=B\* -run=^$$ . -benchmem
	#
	# Race rondition tests
	#
	$(MAKE) racetest
	#
	# Test cross compilation
	#
	$(MAKE) build-linux-amd64
	$(MAKE) build-windows-amd64
	$(MAKE) build-windows-i386
	#
	# All CI tests successful
	#

benchmark: fmt
	go test -timeout=1m -ldflags "-s -w -X main.Build=$(shell git rev-parse --short HEAD)" -v -bench=B\* -run=^$$ . -benchmem

racetest: fmt
	go test -race -v -timeout=3m -coverprofile=coverage.txt -covermode=atomic

covertest: fmt
	go test -v -coverprofile=cover.out -timeout=1m
	go tool cover -func=cover.out
	go tool cover -html=cover.out -o coverage.html

coverweb: fmt
	go test -v -coverprofile=cover.out -timeout=1m
	go tool cover -html=cover.out

clean:
	set -e; for CMD in $(CMDS); do \
		rm -f ./cmd/$$CMD/$$CMD; \
	done
	rm -f $(CMDS)
	rm -f *.windows.*.exe
	rm -f *.linux.*
	rm -f cover.out
	rm -f coverage.html
	rm -f coverage.txt
	rm -f mod-gearman*.html

fmt:
	$(BINPATH)/goimports -w .
	go vet -all -assign -atomic -bool -composites -copylocks -nilfunc -rangeloops -unsafeptr -unreachable .
	set -e; for CMD in $(CMDS); do \
		go vet -all -assign -atomic -bool -composites -copylocks -nilfunc -rangeloops -unsafeptr -unreachable ./cmd/$$CMD; \
	done
	gofmt -w -s .

versioncheck:
	@[ $$( printf '%s\n' $(GOVERSION) $(MINGOVERSION) | sort | head -n 1 ) = $(MINGOVERSION) ] || { \
		echo "**** ERROR:"; \
		echo "**** Mod-Gearman-Worker-Go requires at least golang version $(MINGOVERSIONSTR) or higher"; \
		echo "**** this is: $$(go version)"; \
		exit 1; \
	}

copyfighter:
	#
	# Check if there are values better passed as pointer
	# See https://github.com/jmhodges/copyfighter
	#
	mv mod_gearman_worker_windows.go mod_gearman_worker_windows.off; \
	mv mod_gearman_worker_darwin.go mod_gearman_worker_darwin.off; \
	$(BINPATH)/copyfighter .; rc=$$?; \
	mv mod_gearman_worker_windows.off mod_gearman_worker_windows.go; \
	mv mod_gearman_worker_darwin.off mod_gearman_worker_darwin.go; \
	exit $$rc

golangci:
	#
	# golangci combines a few static code analyzer
	# See https://github.com/golangci/golangci-lint
	#
	@if [ $$( printf '%s\n' $(GOVERSION) 00010010 | sort -n | head -n 1 ) != 00010010 ]; then \
		echo "golangci requires at least go 1.10"; \
	else \
		golangci-lint run ./...; \
	fi

version:
	OLDVERSION="$(shell grep "VERSION =" ./mod_gearman_worker.go | awk '{print $$3}' | tr -d '"')"; \
	NEWVERSION=$$(dialog --stdout --inputbox "New Version:" 0 0 "v$$OLDVERSION") && \
		NEWVERSION=$$(echo $$NEWVERSION | sed "s/^v//g"); \
		if [ "v$$OLDVERSION" = "v$$NEWVERSION" -o "x$$NEWVERSION" = "x" ]; then echo "no changes"; exit 1; fi; \
		sed -i -e 's/VERSION =.*/VERSION = "'$$NEWVERSION'"/g' *.go cmd/*/*.go
