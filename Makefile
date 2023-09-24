.PHONY: .phony

all: .phony validate test

build: .phony
	docker-compose build

validate: .phony clean build
	CMD='pre-commit run --all-files' docker-compose run --rm pre-commit

test: .phony clean_docker build
	CMD='go test -v -timeout 30m' docker-compose run --rm test

clean: clean_docker clean_terraform

clean_docker: .phony
	docker-compose down -v --remove-orphans

clean_terraform: .phony
	find . -type d -name '.terraform' -exec rm -rf {} +
	find . -type f -name '.terraform.lock.hcl' -delete
