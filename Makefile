VERSION ?= `cat VERSION | grep erlang | cut -d' ' -f2`
ALPINE_VERSION ?= `cat VERSION | grep alpine | cut -d' ' -f2`
ALPINE_MIN_VERSION := $(shell echo $(ALPINE_VERSION) | sed 's/\([0-9][0-9]*\)\.\([0-9][0-9]*\)\(\.[0-9][0-9]*\)*/\1.\2/')
MAJ_VERSION := $(shell echo $(VERSION) | sed 's/\([0-9][0-9]*\)\.\([0-9][0-9]*\)\(\.[0-9][0-9]*\)*/\1/')
MIN_VERSION := $(shell echo $(VERSION) | sed 's/\([0-9][0-9]*\)\.\([0-9][0-9]*\)\(\.[0-9][0-9]*\)*/\1.\2/')
IMAGE_NAME ?= blockscout/alpine-erlang
XDG_CACHE_HOME ?= /tmp
BUILDX_CACHE_DIR ?= $(XDG_CACHE_HOME)/buildx
IS_LATEST ?= false
ifeq ($(IS_LATEST),true)
EXTRA_TAGS := -t $(IMAGE_NAME):latest
else
EXTRA_TAGS :=
endif

.PHONY: help
help:
	@echo "$(IMAGE_NAME):$(VERSION) (alpine $(ALPINE_VERSION))"
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: test
test: ## Test the Docker image
	docker run --rm $(IMAGE_NAME):$(VERSION) erl -noshell -noinput -version

.PHONY: shell
shell: ## Run an Erlang shell in the image
	docker run --rm -it $(IMAGE_NAME):$(VERSION) erl

.PHONY: sh
sh: ## Boot to a shell prompt
	docker run --rm -it $(IMAGE_NAME):$(VERSION) /bin/bash

.PHONY: sh-build
sh-build: ## Boot to a shell prompt in the build image
	docker run --rm -it $(IMAGE_NAME)-build:$(VERSION) /bin/bash

.PHONY: setup-buildx
setup-buildx: ## Setup a Buildx builder
	@mkdir -p "$(BUILDX_CACHE_DIR)"
	@if ! docker buildx ls | grep buildx-builder >/dev/null; then \
		docker buildx create \
			--buildkitd-flags '--allow-insecure-entitlement security.insecure' \
			--append \
			--name buildx-builder \
			--driver docker-container \
			--use && \
		docker buildx inspect --bootstrap --builder buildx-builder; \
	fi

.PHONY: build
build: setup-buildx ## Build the Docker image
	docker buildx build --output "type=image,push=false" \
		--build-arg ERLANG_VERSION=$(VERSION) \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--build-arg ALPINE_MIN_VERSION=$(ALPINE_MIN_VERSION) \
		--cache-from "type=local,src=$(BUILDX_CACHE_DIR)" \
		--cache-to "type=local,dest=$(BUILDX_CACHE_DIR)" \
		--platform linux/amd64 \
		-t $(IMAGE_NAME):$(VERSION) \
		-t $(IMAGE_NAME):$(MIN_VERSION) \
		-t $(IMAGE_NAME):$(MAJ_VERSION) $(EXTRA_TAGS) .

.PHONY: build-local
build-local: setup-buildx
	docker buildx build --load \
		--build-arg ERLANG_VERSION=$(VERSION) \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--build-arg ALPINE_MIN_VERSION=$(ALPINE_MIN_VERSION) \
		--cache-from "type=local,src=$(BUILDX_CACHE_DIR)" \
		--cache-to "type=local,dest=$(BUILDX_CACHE_DIR)" \
		--platform linux/amd64 \
		-t $(IMAGE_NAME):$(VERSION) \
		-t $(IMAGE_NAME):$(MIN_VERSION) \
		-t $(IMAGE_NAME):$(MAJ_VERSION) $(EXTRA_TAGS) .

.PHONY: stage-build
stage-build: setup-buildx ## Build the build image and stop there for debugging
	docker buildx build --load \
		--build-arg ERLANG_VERSION=$(VERSION) \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--build-arg ALPINE_MIN_VERSION=$(ALPINE_MIN_VERSION) \
		--target=build \
		--platform linux/amd64 \
		-t $(IMAGE_NAME):$(VERSION) \
		-t $(IMAGE_NAME):$(MIN_VERSION) \
		-t $(IMAGE_NAME):$(MAJ_VERSION) $(EXTRA_TAGS) .

.PHONY: clean
clean: ## Clean up generated images
	@docker rmi --force $(IMAGE_NAME):$(VERSION) $(IMAGE_NAME):$(MIN_VERSION) $(IMAGE_NAME):$(MAJ_VERSION) $(IMAGE_NAME):latest

.PHONY: rebuild
rebuild: clean build ## Rebuild the Docker image

.PHONY: validate
validate: build-local ## Build and validate the amd64 image
	docker run --rm $(IMAGE_NAME):$(VERSION) erl -noshell -noinput -version

.PHONY: release
release: setup-buildx ## Build and release the Docker image to Docker Hub
	docker buildx build --push \
		--build-arg ERLANG_VERSION=$(VERSION) \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--build-arg ALPINE_MIN_VERSION=$(ALPINE_MIN_VERSION) \
		--platform linux/amd64 \
		--cache-from "type=local,src=$(BUILDX_CACHE_DIR)" \
		--cache-to "type=local,dest=$(BUILDX_CACHE_DIR)" \
		-t $(IMAGE_NAME):$(VERSION) \
		-t $(IMAGE_NAME):$(MIN_VERSION) \
		-t $(IMAGE_NAME):$(MAJ_VERSION) $(EXTRA_TAGS) .
