DIRS = src
QDK_BUILDER_IMAGE ?= qdk-debuilder
ARCH ?= amd64

.PHONY: all clean

all:
	@for d in $(DIRS); do $(MAKE) -C $$d; done

clean:
	@for d in $(DIRS); do $(MAKE) -C $$d clean; done

debuilder:
	docker build -t $(QDK_BUILDER_IMAGE) -f Dockerfile.debuilder .

# Run the full debian packaging inside the Docker builder image
dpkg-build: debuilder
	docker run --rm -v ${PWD}:/qdk -w /qdk $(QDK_BUILDER_IMAGE) sh -c "make -f Makefile.debian ARCH=$(ARCH)"
