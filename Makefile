SHELL := /bin/bash
ROOT=${PWD}

all: install fmt check validate docs test clean

ci: check validate test

install:
	brew bundle \
	&& go get golang.org/x/tools/cmd/goimports \
	&& go get golang.org/x/lint/golint \
	&& npm install -g markdown-link-check

fmt:
	terraform fmt --recursive -no-color

check:
	pre-commit run -a

validate:
	cd ${ROOT}/template \
		&& terraform init --backend=false -no-color && terraform validate -no-color

test:
	cd ${ROOT}/test \
		&& rm -rf ${ROOT}/test/go.* \
		&& go mod init test \
		&& go mod tidy \
		&& go test -v -timeout 10m

docs:
	terraform-docs markdown ${ROOT}/module --output-file ../README.md --hide modules --hide resources --hide requirements --hide providers

clean:
	for i in $$(find . -iname '.terraform' -o -iname '*.lock.*'); do rm -rf $$i; done

.PHONY: all ci install fmt check validate test docs clean
