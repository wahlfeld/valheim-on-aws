.PHONY: .phony

all: .phony pre-commit test

build: .phony
	docker-compose build --build-arg TF_VERSION=1.4.5

pre-commit: .phony build
	CMD='pre-commit run --all-files' docker-compose run --rm pre-commit

test: .phony
	CMD='go test -v -timeout 30m' docker-compose run --rm test

clean: .phony
	docker-compose down -v --remove-orphans
