VERSION = $(shell git config -f .gitmodules submodule.jaeger.tag)

info:
	@echo jaeger:$(VERSION)

COMPONENT = query
HUB = docker.io/querycapjaegertracing
TARGETARCHS = amd64 arm64

DOCKERX = docker buildx build --push

ifneq (tracegen,$(COMPONENT))
	DOCKERX := $(DOCKERX) --target=release
endif

COMPONENTWORKSPACE=./jaeger/cmd/$(COMPONENT)

IMAGENAME = jaeger-$(COMPONENT)

ifeq (all-in-one,$(COMPONENT))
	IMAGENAME = $(COMPONENT)
endif

ROOT_IMAGE ?= alpine:3.12
CERT_IMAGE := alpine:3.12
GOLANG_IMAGE := golang:1.15-alpine

BASE_IMAGE := $(HUB)/baseimg:1.0.0-$(shell echo $(ROOT_IMAGE) | tr : -)
DEBUG_IMAGE := $(HUB)/debugimg:1.0.0-$(shell echo $(GOLANG_IMAGE) | tr : -)

BUILDARGS = base_image=$(BASE_IMAGE) debug_image=$(DEBUG_IMAGE)

buildx-base-img:
	docker buildx build --push -t $(BASE_IMAGE) \
		--build-arg root_image=$(ROOT_IMAGE) \
		--build-arg cert_image=$(CERT_IMAGE) \
		jaeger/docker/base

buildx-debug-img:
	docker buildx build --push -t $(DEBUG_IMAGE) \
		--build-arg golang_image=$(GOLANG_IMAGE) \
		jaeger/docker/debug

install-esc:
	cd jaeger && go get -u github.com/mjibson/esc

buildx-bin: install-esc
	cd jaeger && sh -c "$(foreach arch,$(TARGETARCHS),make build-$(COMPONENT) GOOS=linux GOARCH=$(arch);)"

buildx: buildx-bin
	sed -i -e 's/ARG TARGETARCH=amd64/ARG TARGETARCH/g' $(COMPONENTWORKSPACE)/Dockerfile
	@echo "======Dockerfile======"
	@cat $(COMPONENTWORKSPACE)/Dockerfile
	@echo "===================="
	$(DOCKERX) \
		--file $(COMPONENTWORKSPACE)/Dockerfile \
		$(foreach arg,$(BUILDARGS),--build-arg=$(arg)) \
		$(foreach h,$(HUB),--tag=$(h)/$(IMAGENAME):$(VERSION)) \
        $(foreach p,$(TARGETARCHS),--platform=linux/$(p)) \
 		$(COMPONENTWORKSPACE)

cleanup:
	git submodule foreach 'git add . && git reset --hard'

dep:
	git submodule foreach 'tag="$$(git config -f $$toplevel/.gitmodules submodule.$$name.tag)"; if [ -n $$tag ]; then git fetch --tags && git checkout $$tag && git submodule update --init; fi'
