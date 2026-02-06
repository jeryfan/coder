.PHONY: package image-build image-push image

SHELL := /bin/bash

ROOT := $(abspath .)
TEMPLATES_ROOT ?= docker/templates
PACKAGE_DIR ?= packages
SPIDER_IMAGE ?= ghcr.io/jeryfan/coder-spider:latest

package:
	@set -euo pipefail; \
	if [ ! -d "$(TEMPLATES_ROOT)" ]; then \
		echo "Templates root not found: $(TEMPLATES_ROOT)"; \
		exit 1; \
	fi; \
	mkdir -p "$(PACKAGE_DIR)"; \
	find "$(TEMPLATES_ROOT)" -name main.tf -print0 | \
	while IFS= read -r -d '' file; do \
		dir="$$(dirname "$$file")"; \
		name="$$(basename "$$dir")"; \
		out="$(ROOT)/$(PACKAGE_DIR)/$${name}.zip"; \
		rm -f "$$out"; \
		( cd "$$dir" && zip -r "$$out" . >/dev/null ); \
		echo "Packaged $$out"; \
	done

image-build:
	docker build -t $(SPIDER_IMAGE) docker/images/spider

image-push:
	docker push $(SPIDER_IMAGE)

image: image-build image-push
