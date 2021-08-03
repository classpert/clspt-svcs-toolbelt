# Check if file .svcname exists, otherwise exit with error
ifeq (,$(wildcard .svcname))
$(error Missing file [.svcname]! Create a .svcname file with the name of your sevice in it)
endif

# Read file .svcname to get service name
APP_NAME := $(shell head -1 .svcname)

# Defaults ENV to dev
ENV ?= dev

# Get host info
UNAME := $(shell uname)

# Select a hashing function based on host
ifeq ($(UNAME), Darwin)
	# Macos
	SHA1SUM := gsha1sum
else
	# assume linux
	SHA1SUM := sha1sum
endif

# Check if a Dockerfile exists, otherwise assume a third-party image is being used
ifneq (,$(wildcard Dockerfile))
APP_IMAGE_NAME             := classpert/$(APP_NAME)
APP_IMAGE_DEPENDS_ON_FILES := $(shell head -1 .docker-image-depends-on-files)
	# Generate a SHA1 digest based on the contents of the files defined on APP_IMAGE_DEPENDS_ON_FILES
APP_IMAGE_TAG              := $(shell cat $(APP_IMAGE_DEPENDS_ON_FILES) | $(SHA1SUM) | sed -e 's/ .*//g')
APP_IMAGE                  := $(APP_IMAGE_NAME):$(APP_IMAGE_TAG)
endif

# Path to binary scripts used for service orchestration
BINARY_EXEC_PATH := $(CLSPT_SVCS_TOOLBELT_DIR)/bin

# Docker Variables
DOCKER         := docker
DOCKER_NETWORK := clspt.$(ENV)
DOCKER_COMPOSE_FILES := -f docker-compose.base.yml -f docker-compose.$(ENV).yml
DOCKER_COMPOSE_PROJECT_NAME := $(subst .,_,$(DOCKER_NETWORK))

# Include makefiles
-include makefiles/extends.mk
-include makefiles/test.mk
-include makefiles/local.mk

# Set docker compose call based on image information
ifneq ($(APP_IMAGE),)
	DOCKER_COMPOSE_ENVS := ENV=$(ENV) APP_NAME=$(APP_NAME) APP_IMAGE=$(APP_IMAGE)
endif

DOCKER_COMPOSE := $(DOCKER_COMPOSE_ENVS) docker-compose -p $(DOCKER_COMPOSE_PROJECT_NAME) $(DOCKER_COMPOSE_FILES)

define only_on_mac
	if [ "$$(UNAME)" = "Darwin" ]; then echo '$(1)' | sed 's/(\(.*\))/\1/' | sh -; fi;
endef

### Tasks ###

help: ## List all tasks
	@grep -E '^[%a-zA-Z_-]+:.*?## .*$$' $(lastword $(MAKEFILE_LIST)) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

setup: ## Make this project ready to use without running it
	@make -s env-setup

up:
	@make -s network-create
	@make -s depends_on-up
	@make -s self-up

down:
	@make -s depends_on-down
	@make -s self-down
	@echo -e "\033[36mIf you wish to remove the network $(DOCKER_NETWORK), run \033[33mmake rm-network"

network-create: ## Create network
	@$(BINARY_EXEC_PATH)/network-create $(DOCKER_NETWORK)

network-rm: ## Remove network
	@$(BINARY_EXEC_PATH)/network-rm $(DOCKER_NETWORK)

env-setup: ## Set local environment
	@$(BINARY_EXEC_PATH)/env-setup $(APP_NAME) $(ENV)

depends_on-up: env-setup
	@$(BINARY_EXEC_PATH)/deps-make-call self-up $(ENV)

depends_on-down: env-setup
	@$(BINARY_EXEC_PATH)/deps-make-call self-down $(ENV)

self-up: env-setup ## Run containers
	@DOCKER_COMPOSE_IGNORE_ORPHANS=true $(DOCKER_COMPOSE) up -d $(APP_NAME)

self-down: env-setup ## Removes all containers
	@DOCKER_COMPOSE_IGNORE_ORPHANS=true $(DOCKER_COMPOSE) down --rmi local

sh: env-setup ## Attach to sh
	@$(DOCKER_COMPOSE) run --entrypoint /bin/sh $(APP_NAME)

purge-all: env-setup ## Remove system-wide running containers all networks and unused images
	@$(DOCKER_COMPOSE) down --rmi local --remove-orphans
	@$(DOCKER) system prune -f

logs: ## Follow logs
	@$(DOCKER_COMPOSE) logs -f

logs-%: ## Follow logs for a given container
	@$(DOCKER_COMPOSE) logs -f $*

ifneq ($(APP_IMAGE),)
image-build: ## Build images
	@$(DOCKER_COMPOSE) build --build-arg "GITHUB_ACCESS_TOKEN=$(GITHUB_ACCESS_TOKEN)"
	
image-push: ## Push image
	@$(DOCKER) push $(APP_IMAGE)
endif

image-pull: ## Pull images
	@$(DOCKER_COMPOSE) pull

LESS_PRIORITY-%: # Just a gimmick to order tasks
	@:

.PHONY: network-create network-rm env-setup help sh up down depends_on-up depends_on-down purge-all logs logs-% image-build image-pull image-push LESS_PRIORITY-%
