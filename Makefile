BINARY ?= spilo_timeline

DOCKERDIR = postgres-appliance

IMAGE ?= stackitpg/$(BINARY)
TAG ?= $(VERSION)
VERSION ?= $(shell git describe --tags --always --dirty)
DOCKERFILE = Dockerfile


default: local

build: 
	echo "Tag ${TAG}"
	echo "Version ${VERSION}"
	echo "git describe $(shell git describe --tags --always --dirty)"
	cd "${DOCKERDIR}" && docker build --rm -t "$(IMAGE):$(TAG)" -f "${DOCKERFILE}" .
	cd "${DOCKERDIR}" && docker build --rm -t "$(IMAGE):latest" -f "${DOCKERFILE}" .
push:
	docker push "$(IMAGE):$(TAG)"
	docker push "$(IMAGE):latest"