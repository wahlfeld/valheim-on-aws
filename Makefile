# Variables for common commands
DOCKER_COMPOSE_RUN := docker-compose run --rm

.PHONY: .phony

all: .phony validate test

build:
	docker-compose build

validate: .phony clean build
	CMD='pre-commit run --all-files' $(DOCKER_COMPOSE_RUN) pre-commit

test: clean_docker build
	CMD='go test -v -timeout 60m' $(DOCKER_COMPOSE_RUN) test

clean: clean_docker clean_terraform

clean_docker:
	docker-compose down -v --remove-orphans

clean_terraform: .phony
	find . -type d -name '.terraform' -exec rm -rf {} +
	find . -type f -name '.terraform.lock.hcl' -delete
