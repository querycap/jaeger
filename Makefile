VERSION = $(shell git config -f .gitmodules submodule.jaeger.tag)

info:
	@echo jaeger:$(VERSION)

COMPONENT = query
HUB = docker.io/querycapjaegertracing
TARGETARCHS = amd64 arm64

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

buildx-bin:
	cd jaeger && sh -c "$(foreach arch,$(TARGETARCHS),make build-$(COMPONENT) GOOS=linux GOARCH=$(arch);)"

buildx: buildx-bin
	sed -i -e 's/ARG TARGETARCH=amd64/ARG TARGETARCH/g' $(COMPONENTWORKSPACE)/Dockerfile
	cat $(COMPONENTWORKSPACE)/Dockerfile
	docker buildx build --push \
		--file $(COMPONENTWORKSPACE)/Dockerfile \
		--target=release \
		$(foreach arg,$(BUILDARGS),--build-arg=$(arg)) \
		$(foreach h,$(HUB),--tag=$(h)/$(IMAGENAME):$(VERSION)) \
        $(foreach p,$(TARGETARCHS),--platform=linux/$(p)) \
 		$(COMPONENTWORKSPACE)

cleanup:
	git submodule foreach 'git add . && git reset --hard'

dep:
	git submodule foreach 'tag="$$(git config -f $$toplevel/.gitmodules submodule.$$name.tag)"; [[ -n $$tag ]] && git reset --hard && git checkout $$tag && git submodule update --init || echo "this module has no tag"'

DEBUG ?= 1

HELM ?= helm upgrade --install --create-namespace
ifeq ($(DEBUG),1)
	HELM = helm template --dependency-update
endif

apply:
	$(HELM) --namespace=jaeger-system jaeger ./charts/jaeger


