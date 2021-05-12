SHELL := /bin/bash
ROOT=${PWD}

all: fmt validate check docs clean

ci: validate check test

install:
	brew bundle \
	&& go get golang.org/x/tools/cmd/goimports \
	&& go get golang.org/x/lint/golint \
	&& npm install -g markdown-link-check

fmt:
	terraform fmt --recursive

check:
	pre-commit run -a \
	&& checkov --directory ${ROOT}/module

validate: clean
	cd ${ROOT}/template \
		&& terraform init --backend=false && terraform validate

test: clean	
	cd ${ROOT}/test \
		&& rm -rf ${ROOT}/test/go.* \
		&& go mod init test \
		&& go mod tidy \
		&& go test -v -timeout 30m

docs:
	terraform-docs markdown ${ROOT}/template --output-file ../README.md --hide modules --hide resources --hide requirements --hide providers

clean:
	for i in $$(find . -iname '.terraform' -o -iname '*.lock.*' -o -iname '*.tfstate*' -o -iname '.test-data'); do rm -rf $$i; done

.PHONY: all ci install fmt check validate test docs clean
