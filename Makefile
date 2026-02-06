.PHONY: help package image-build image-push image clean lint

SHELL := /bin/bash

ROOT := $(abspath .)
TEMPLATES_ROOT ?= templates
PACKAGE_DIR ?= packages
SPIDER_IMAGE ?= ghcr.io/jeryfan/coder-spider:latest

help: ## 显示帮助信息
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

package: ## 打包所有模板为 zip
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

image-build: ## 构建 Spider 镜像
	docker build -t $(SPIDER_IMAGE) images/spider

image-push: ## 推送 Spider 镜像到 Registry
	docker push $(SPIDER_IMAGE)

image: image-build image-push ## 构建并推送 Spider 镜像

clean: ## 清理构建产物
	rm -rf "$(PACKAGE_DIR)"

lint: ## 代码格式检查
	@echo "Checking Terraform format..."
	@terraform fmt -check -recursive $(TEMPLATES_ROOT) || \
		{ echo "Run 'terraform fmt -recursive $(TEMPLATES_ROOT)' to fix"; exit 1; }
	@echo "Checking shell scripts..."
	@find $(TEMPLATES_ROOT) -name '*.sh' -exec shellcheck {} + || \
		{ echo "Fix shellcheck warnings above"; exit 1; }
	@echo "All checks passed."
