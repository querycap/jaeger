VERSION = $(shell git config -f .gitmodules submodule.jaeger.tag)

DOCKERX = docker buildx build --push

HUB = docker.io/querycapjaegertracing
TARGET_ARCHS = amd64 arm64

COMPONENT = query
IMAGE_NAME = jaeger-$(COMPONENT)


BASE_IMAGE_COMPONENT = baseimg debugimg

BACKEND_COMPONENT = \
	all-in-one \
	all-in-one-debug \
    agent \
    agent-debug \
    collector \
    collector-debug \
    query \
    query-debug \
    ingester \
    ingester-debug \

BIN_COMPONENT = $(BACKEND_COMPONENT) tracegen

IMAGE_WITHOUT_JAEGER_PREFIX = $(BASE_IMAGE_COMPONENT) all-in-one

ifneq (,$(findstring $(COMPONENT),$(IMAGE_WITHOUT_JAEGER_PREFIX)))
	IMAGE_NAME = $(COMPONENT)
endif

ifneq (,$(findstring $(COMPONENT),$(BACKEND_COMPONENT)))
	ifneq (,$(findstring -debug,$(COMPONENT)))
		DOCKERX := $(DOCKERX) --target=debug
	else
		DOCKERX := $(DOCKERX) --target=release
	endif
endif

ROOT_IMAGE = alpine:3.12
CERT_IMAGE = $(ROOT_IMAGE)
GOLANG_IMAGE = golang:1.15-alpine
BASE_IMG_TAG = 1.0.0-$(subst :,-,$(ROOT_IMAGE))
DEBUG_IMG_TAG = 1.0.0-$(subst :,-,$(GOLANG_IMAGE))

WORKSPACE = ./jaeger/cmd/$(subst -debug,,$(COMPONENT))
DOCKERFILE = $(WORKSPACE)/Dockerfile

BUILD_ARGS = base_image=$(HUB)/baseimg:$(BASE_IMG_TAG) debug_image=$(HUB)/debugimg:$(DEBUG_IMG_TAG)

# base image
ifneq (,$(findstring $(COMPONENT),$(BASE_IMAGE_COMPONENT)))
	WORKSPACE = ./jaeger/docker/$(subst img,,$(COMPONENT))

	BUILD_ARGS = root_image=$(ROOT_IMAGE) cert_image=$(CERT_IMAGE)
	VERSION = $(BASE_IMG_TAG)

	ifeq (debugimg,$(COMPONENT))
		BUILD_ARGS = golang_image=$(GOLANG_IMAGE)
		VERSION = $(DEBUG_IMG_TAG)
	endif
endif

ifeq (cassandra-schema,$(COMPONENT))
    WORKSPACE = ./jaeger/plugin/storage/cassandra
endif
ifeq (es-index-cleaner,$(COMPONENT))
    WORKSPACE = ./jaeger/plugin/storage/es
endif
ifeq (es-rollover,$(COMPONENT))
    WORKSPACE = ./jaeger/plugin/storage/es
    DOCKERFILE = $(WORKSPACE)/Dockerfile.rollover
endif

info:
	@echo "====="
	@echo "component: $(COMPONENT), workspace: $(WORKSPACE), img: $(foreach h,$(HUB),$(h)/$(IMAGE_NAME):$(VERSION))"
	@echo "====="

install-esc:
	@if ! esc > /dev/null 2>&1; then \
  		cd jaeger && go get -u github.com/mjibson/esc; \
  	fi

buildx-bin: install-esc
ifneq (,$(findstring $(COMPONENT),$(BIN_COMPONENT)))
	cd jaeger && sh -c "$(foreach arch,$(TARGET_ARCHS),make build-$(COMPONENT) GOOS=linux GOARCH=$(arch);)"
endif

patch-dockerfile:
	@sed -i -e 's/ARG TARGETARCH=amd64/ARG TARGETARCH/g' "$(DOCKERFILE)"
	@echo "======Dockerfile======"
	@cat "$(WORKSPACE)/Dockerfile"
	@echo "===================="

dockerx: info buildx-bin patch-dockerfile
	$(DOCKERX) \
		$(foreach arg,$(BUILD_ARGS),--build-arg=$(arg)) \
		$(foreach h,$(HUB),--tag=$(h)/$(IMAGE_NAME):$(VERSION)) \
		$(foreach p,$(TARGET_ARCHS),--platform=linux/$(p)) \
		--file=$(DOCKERFILE) $(WORKSPACE)

cleanup:
	git submodule foreach 'git add . && git reset --hard'

dep:
	git submodule foreach 'tag="$$(git config -f $$toplevel/.gitmodules submodule.$$name.tag)"; if [ -n $$tag ]; then git fetch --tags && git checkout $$tag && git submodule update --init; fi'


sync-crd:
	wget -O charts/jaeger-operator/crds/jaegertracing.io_jaegers_crd.yaml https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/crds/jaegertracing.io_jaegers_crd.yaml
