.PHONY: .phony

all: .phony pre-commit test

build: .phony
	docker-compose build --build-arg TF_VERSION=1.4.6

pre-commit: .phony build
	CMD='pre-commit run --all-files' docker-compose run --rm pre-commit

test: .phony
	CMD='go test -v -timeout 30m' docker-compose run --rm test

clean: clean_docker clean_terraform

clean_docker: .phony
	docker-compose down -v --remove-orphans

clean_terraform: .phony
	find . -type d -name '.terraform' -exec rm -rf {} +
	find . -type f -name '.terraform.lock.hcl' -delete