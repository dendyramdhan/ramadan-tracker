IMAGE_NAME   ?= ramadan-tracker
IMAGE_TAG    ?= latest
TAG          ?= $(IMAGE_TAG)
REGISTRY     ?= 
PLATFORMS    ?= linux/amd64,linux/arm64
BUILDER_NAME ?= multiplatform-builder
PORT         ?= 8080

FULL_IMAGE = $(if $(REGISTRY),$(REGISTRY)/$(IMAGE_NAME):$(TAG),$(IMAGE_NAME):$(TAG))

.PHONY: help setup build build-multi push build-push run stop clean

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Create and bootstrap buildx builder for multiplatform
	@if ! docker buildx inspect $(BUILDER_NAME) > /dev/null 2>&1; then \
		docker buildx create --name $(BUILDER_NAME) --driver docker-container --bootstrap; \
	fi
	docker buildx use $(BUILDER_NAME)
	@echo "Builder '$(BUILDER_NAME)' is ready."

build: setup ## Build image for local platform and load into Docker
	docker buildx build \
		--tag $(FULL_IMAGE) \
		--file Dockerfile.multi \
		--load \
		.

build-multi: setup ## Build multiplatform image and push to registry
	docker buildx build \
		--platform $(PLATFORMS) \
		--tag $(FULL_IMAGE) \
		--file Dockerfile.multi \
		--push \
		.

push: setup ## Push multiplatform image to registry
	docker buildx build \
		--platform $(PLATFORMS) \
		--tag $(FULL_IMAGE) \
		--file Dockerfile.multi \
		--push \
		.

build-push: build-multi ## Alias for build-multi (build multiplatform and push)

run: build ## Build locally and run container
	docker run --rm -p $(PORT):8080 --name $(IMAGE_NAME) $(FULL_IMAGE)

stop: ## Stop the locally running container
	docker stop $(IMAGE_NAME) || true

clean: ## Remove the buildx builder
	docker buildx rm $(BUILDER_NAME) || true
