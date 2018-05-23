ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
SHELL := /bin/bash
TOX_DIR := .tox
VIRTUALENV_DIR ?= virtualenv
PYTHON_VERSION = python2.7

BINARIES := bin

# All components are prefixed by st2
COMPONENTS := $(wildcard st2*)
COMPONENTS_RUNNERS := $(wildcard contrib/runners/*)

COMPONENTS_WITH_RUNNERS := $(wildcard st2*)
COMPONENTS_WITH_RUNNERS += $(wildcard contrib/runners/*)

# Components that implement a component-controlled test-runner. These components provide an
# in-component Makefile. (Temporary fix until I can generalize the pecan unittest setup. -mar)
# Note: We also want to ignore egg-info dir created during build
COMPONENT_SPECIFIC_TESTS := st2tests st2client.egg-info

# nasty hack to get a space into a variable
space_char :=
space_char +=
comma := ,
COMPONENT_PYTHONPATH = $(subst $(space_char),:,$(realpath $(COMPONENTS_WITH_RUNNERS)))
COMPONENTS_TEST := $(foreach component,$(filter-out $(COMPONENT_SPECIFIC_TESTS),$(COMPONENTS_WITH_RUNNERS)),$(component))
COMPONENTS_TEST_COMMA := $(subst $(space_char),$(comma),$(COMPONENTS_TEST))

PYTHON_TARGET := 2.7

REQUIREMENTS := test-requirements.txt requirements.txt
PIP_OPTIONS := $(ST2_PIP_OPTIONS)

NOSE_OPTS := --rednose --immediate --with-parallel
NOSE_TIME := $(NOSE_TIME)

ifdef NOSE_TIME
	NOSE_OPTS := --rednose --immediate --with-parallel --with-timer
endif

ifndef PIP_OPTIONS
	PIP_OPTIONS :=
endif

.PHONY: all
all: requirements configgen check tests

# Target for debugging Makefile variable assembly
.PHONY: play
play:
	@echo COMPONENTS=$(COMPONENTS)
	@echo COMPONENTS_WITH_RUNNERS=$(COMPONENTS_WITH_RUNNERS)
	@echo COMPONENTS_TEST=$(COMPONENTS_TEST)
	@echo COMPONENTS_TEST_COMMA=$(COMPONENTS_TEST_COMMA)
	@echo COMPONENT_PYTHONPATH=$(COMPONENT_PYTHONPATH)


.PHONY: check
check: requirements flake8 checklogs

.PHONY: checklogs
checklogs:
	@echo
	@echo "================== LOG WATCHER ===================="
	@echo
	. $(VIRTUALENV_DIR)/bin/activate; ./tools/log_watcher.py 10

.PHONY: pylint
pylint: requirements .pylint

.PHONY: configgen
configgen: requirements .configgen

.PHONY: .configgen
.configgen:
	@echo
	@echo "================== config gen ===================="
	@echo
	echo "# Sample config which contains all the available options which the corresponding descriptions" > conf/st2.conf.sample;
	echo "# Note: This file is automatically generated using tools/config_gen.py - DO NOT UPDATE MANUALLY" >> conf/st2.conf.sample
	echo "" >> conf/st2.conf.sample
	. $(VIRTUALENV_DIR)/bin/activate; python ./tools/config_gen.py >> conf/st2.conf.sample;

.PHONY: .pylint
.pylint:
	@echo
	@echo "================== pylint ===================="
	@echo
	# Lint st2 components
	@for component in $(COMPONENTS); do\
		echo "==========================================================="; \
		echo "Running pylint on" $$component; \
		echo "==========================================================="; \
		. $(VIRTUALENV_DIR)/bin/activate; pylint -E --rcfile=./lint-configs/python/.pylintrc --load-plugins=pylint_plugins.api_models --load-plugins=pylint_plugins.db_models $$component/$$component || exit 1; \
	done
	# Lint runner modules and packages
	@for component in $(COMPONENTS_RUNNERS); do\
		echo "==========================================================="; \
		echo "Running pylint on" $$component; \
		echo "==========================================================="; \
		. $(VIRTUALENV_DIR)/bin/activate; pylint -E --rcfile=./lint-configs/python/.pylintrc --load-plugins=pylint_plugins.api_models --load-plugins=pylint_plugins.db_models $$component/*.py || exit 1; \
	done
	# Lint Python pack management actions
	. $(VIRTUALENV_DIR)/bin/activate; pylint -E --rcfile=./lint-configs/python/.pylintrc --load-plugins=pylint_plugins.api_models contrib/packs/actions/*.py || exit 1;
	. $(VIRTUALENV_DIR)/bin/activate; pylint -E --rcfile=./lint-configs/python/.pylintrc --load-plugins=pylint_plugins.api_models contrib/packs/actions/*/*.py || exit 1;
	# Lint other packs
	. $(VIRTUALENV_DIR)/bin/activate; pylint -E --rcfile=./lint-configs/python/.pylintrc --load-plugins=pylint_plugins.api_models contrib/linux/*/*.py || exit 1;
	. $(VIRTUALENV_DIR)/bin/activate; pylint -E --rcfile=./lint-configs/python/.pylintrc --load-plugins=pylint_plugins.api_models contrib/chatops/*/*.py || exit 1;
	# Lint Python scripts
	. $(VIRTUALENV_DIR)/bin/activate; pylint -E --rcfile=./lint-configs/python/.pylintrc --load-plugins=pylint_plugins.api_models scripts/*.py || exit 1;
	. $(VIRTUALENV_DIR)/bin/activate; pylint -E --rcfile=./lint-configs/python/.pylintrc --load-plugins=pylint_plugins.api_models tools/*.py || exit 1;
	. $(VIRTUALENV_DIR)/bin/activate; pylint -E --rcfile=./lint-configs/python/.pylintrc pylint_plugins/*.py || exit 1;

.PHONY: lint-api-spec
lint-api-spec: requirements .lint-api-spec

.PHONY: .lint-api-spec
.lint-api-spec:
	@echo
	@echo "================== Lint API spec ===================="
	@echo
	. $(VIRTUALENV_DIR)/bin/activate; st2common/bin/st2-validate-api-spec

.PHONY: generate-api-spec
generate-api-spec: requirements .generate-api-spec

.PHONY: .generate-api-spec
.generate-api-spec:
	@echo
	@echo "================== Generate openapi.yaml file ===================="
	@echo
	echo "# NOTE: This file is auto-generated - DO NOT EDIT MANUALLY" > st2common/st2common/openapi.yaml
	echo "# Edit st2common/st2common/openapi.yaml.j2 and then run" >> st2common/st2common/openapi.yaml
	echo "# make .generate-api-spec" >> st2common/st2common/openapi.yaml
	echo "# to generate the final spec file" >> st2common/st2common/openapi.yaml
	. virtualenv/bin/activate; st2common/bin/st2-generate-api-spec --config-file conf/st2.dev.conf >> st2common/st2common/openapi.yaml

.PHONY: circle-lint-api-spec
circle-lint-api-spec:
	@echo
	@echo "================== Lint API spec ===================="
	@echo
	. $(VIRTUALENV_DIR)/bin/activate; st2common/bin/st2-validate-api-spec --config-file conf/st2.dev.conf || echo "Open API spec lint failed."

.PHONY: flake8
flake8: requirements .flake8

.PHONY: .flake8
.flake8:
	@echo
	@echo "==================== flake ===================="
	@echo
	. $(VIRTUALENV_DIR)/bin/activate; flake8 --config ./lint-configs/python/.flake8 $(COMPONENTS)
	. $(VIRTUALENV_DIR)/bin/activate; flake8 --config ./lint-configs/python/.flake8 $(COMPONENTS_RUNNERS)
	. $(VIRTUALENV_DIR)/bin/activate; flake8 --config ./lint-configs/python/.flake8 contrib/packs/actions/
	. $(VIRTUALENV_DIR)/bin/activate; flake8 --config ./lint-configs/python/.flake8 contrib/linux
	. $(VIRTUALENV_DIR)/bin/activate; flake8 --config ./lint-configs/python/.flake8 contrib/chatops/
	. $(VIRTUALENV_DIR)/bin/activate; flake8 --config ./lint-configs/python/.flake8 scripts/
	. $(VIRTUALENV_DIR)/bin/activate; flake8 --config ./lint-configs/python/.flake8 tools/
	. $(VIRTUALENV_DIR)/bin/activate; flake8 --config ./lint-configs/python/.flake8 pylint_plugins/

.PHONY: bandit
bandit: requirements .bandit

.PHONY: .bandit
.bandit:
	@echo
	@echo "==================== bandit ===================="
	@echo
	. $(VIRTUALENV_DIR)/bin/activate; bandit -r $(COMPONENTS_WITH_RUNNERS) -lll

.PHONY: lint
lint: requirements .lint

.PHONY: .lint
.lint: .generate-api-spec .flake8 .pylint .bandit .st2client-dependencies-check .st2common-circular-dependencies-check .rst-check

.PHONY: clean
clean: .cleanpycs

.PHONY: compile
compile:
	@echo "======================= compile ========================"
	@echo "------- Compile all .py files (syntax check test - Python 2) ------"
	@if python -c 'import compileall,re; compileall.compile_dir(".", rx=re.compile(r"/virtualenv|.tox"), quiet=True)' | grep .; then exit 1; else exit 0; fi

.PHONY: compilepy3
compilepy3:
	@echo "======================= compile ========================"
	@echo "------- Compile all .py files (syntax check test - Python 3) ------"
	@if python3 -c 'import compileall,re; compileall.compile_dir(".", rx=re.compile(r"/virtualenv|.tox|./st2tests/st2tests/fixtures/packs/test"), quiet=True)' | grep .; then exit 1; else exit 0; fi

.PHONY: .cleanpycs
.cleanpycs:
	@echo "Removing all .pyc files"
	find $(COMPONENTS_WITH_RUNNERS)  -name \*.pyc -type f -print0 | xargs -0 -I {} rm {}

.PHONY: .st2client-dependencies-check
.st2client-dependencies-check:
	@echo "Checking for st2common imports inside st2client"
	find ${ROOT_DIR}/st2client/st2client/ -name \*.py -type f -print0 | xargs -0 cat | grep st2common ; test $$? -eq 1

.PHONY: .st2common-circular-dependencies-check
.st2common-circular-dependencies-check:
	@echo "Checking st2common for circular dependencies"
	find ${ROOT_DIR}/st2common/st2common/ -name \*.py -type f -print0 | xargs -0 cat | grep st2reactor ; test $$? -eq 1
	find ${ROOT_DIR}/st2common/st2common/ \( -name \*.py ! -name runnersregistrar\.py -name \*.py ! -name compat\.py \) -type f -print0 | xargs -0 cat | grep st2actions ; test $$? -eq 1
	find ${ROOT_DIR}/st2common/st2common/ -name \*.py -type f -print0 | xargs -0 cat | grep st2api ; test $$? -eq 1
	find ${ROOT_DIR}/st2common/st2common/ -name \*.py -type f -print0 | xargs -0 cat | grep st2auth ; test $$? -eq 1
	find ${ROOT_DIR}/st2common/st2common/ -name \*.py -type f -print0 | xargs -0 cat | grep st2debug; test $$? -eq 1
	find ${ROOT_DIR}/st2common/st2common/ -name \*.py -type f -print0 | xargs -0 cat | grep st2stream; test $$? -eq 1
	find ${ROOT_DIR}/st2common/st2common/ -name \*.py -type f -print0 | xargs -0 cat | grep st2exporter; test $$? -eq 1

.PHONY: .cleanmongodb
.cleanmongodb:
	@echo "==================== cleanmongodb ===================="
	@echo "----- Dropping all MongoDB databases -----"
	@sudo pkill -9 mongod
	@sudo rm -rf /var/lib/mongodb/*
	@sudo chown -R mongodb:mongodb /var/lib/mongodb/
	@sudo service mongodb start
	@sleep 15
	@mongo --eval "rs.initiate()"
	@sleep 15

.PHONY: .cleanmysql
.cleanmysql:
	@echo "==================== cleanmysql ===================="
	@echo "----- Dropping all Mistral MYSQL databases -----"
	@mysql -uroot -pStackStorm -e "DROP DATABASE IF EXISTS mistral"
	@mysql -uroot -pStackStorm -e "CREATE DATABASE mistral"
	@mysql -uroot -pStackStorm -e "GRANT ALL PRIVILEGES ON mistral.* TO 'mistral'@'127.0.0.1' IDENTIFIED BY 'StackStorm'"
	@mysql -uroot -pStackStorm -e "FLUSH PRIVILEGES"
	@/opt/openstack/mistral/.venv/bin/python /opt/openstack/mistral/tools/sync_db.py --config-file /etc/mistral/mistral.conf

.PHONY: .cleanrabbitmq
.cleanrabbitmq:
	@echo "==================== cleanrabbitmq ===================="
	@echo "Deleting all RabbitMQ queue and exchanges"
	@sudo rabbitmqctl stop_app
	@sudo rabbitmqctl reset
	@sudo rabbitmqctl start_app

.PHONY: distclean
distclean: clean
	@echo
	@echo "==================== distclean ===================="
	@echo
	rm -rf $(VIRTUALENV_DIR)

.PHONY: requirements
requirements: virtualenv .sdist-requirements
	@echo
	@echo "==================== requirements ===================="
	@echo
	# Make sure we use latest version of pip which is < 10.0.0
	$(VIRTUALENV_DIR)/bin/pip install --upgrade "pip>=9.0,<9.1"
	$(VIRTUALENV_DIR)/bin/pip install --upgrade "virtualenv==15.1.0" # Required for packs.install in dev envs.

	# Generate all requirements to support current CI pipeline.
	$(VIRTUALENV_DIR)/bin/python scripts/fixate-requirements.py --skip=virtualenv -s st2*/in-requirements.txt -f fixed-requirements.txt -o requirements.txt

	# Fix for Travis CI race
	$(VIRTUALENV_DIR)/bin/pip install "six==1.11.0"

	# Install requirements
	#
	for req in $(REQUIREMENTS); do \
			echo "Installing $$req..." ; \
			$(VIRTUALENV_DIR)/bin/pip install $(PIP_OPTIONS) -r $$req ; \
	done

	# Install st2common package to load drivers defined in st2common setup.py
	(cd st2common; ${ROOT_DIR}/$(VIRTUALENV_DIR)/bin/python setup.py develop)


	# Note: We install prance here and not as part of any component
	# requirements.txt because it has a conflict with our dependency (requires
	# new version of requests) which we cant resolve at this moment
	$(VIRTUALENV_DIR)/bin/pip install "prance==0.6.1"

	# Install st2common to register metrics drivers
	(cd ${ROOT_DIR}/st2common; ${ROOT_DIR}/$(VIRTUALENV_DIR)/bin/python setup.py develop)

	# Some of the tests rely on submodule so we need to make sure submodules are check out
	git submodule update --init --recursive

.PHONY: virtualenv
	# Note: We always want to update virtualenv/bin/activate file to make sure
	# PYTHONPATH is up to date and to avoid caching issues on Travis
virtualenv:
	@echo
	@echo "==================== virtualenv ===================="
	@echo
	# Note: We pass --no-download flag to make sure version of pip which we install (9.0.1) is used
	# instead of latest version being downloaded from PyPi
	test -f $(VIRTUALENV_DIR)/bin/activate || virtualenv --python=$(PYTHON_VERSION) --no-site-packages $(VIRTUALENV_DIR) --no-download

	# Setup PYTHONPATH in bash activate script...
	# Delete existing entries (if any)
	sed -i '/_OLD_PYTHONPATHp/d' $(VIRTUALENV_DIR)/bin/activate
	sed -i '/PYTHONPATH=/d' $(VIRTUALENV_DIR)/bin/activate
	sed -i '/export PYTHONPATH/d' $(VIRTUALENV_DIR)/bin/activate

	echo '_OLD_PYTHONPATH=$$PYTHONPATH' >> $(VIRTUALENV_DIR)/bin/activate
	#echo 'PYTHONPATH=$$_OLD_PYTHONPATH:$(COMPONENT_PYTHONPATH)' >> $(VIRTUALENV_DIR)/bin/activate
	echo 'PYTHONPATH=${ROOT_DIR}:$(COMPONENT_PYTHONPATH)' >> $(VIRTUALENV_DIR)/bin/activate
	echo 'export PYTHONPATH' >> $(VIRTUALENV_DIR)/bin/activate
	touch $(VIRTUALENV_DIR)/bin/activate

	# Setup PYTHONPATH in fish activate script...
	#echo '' >> $(VIRTUALENV_DIR)/bin/activate.fish
	#echo 'set -gx _OLD_PYTHONPATH $$PYTHONPATH' >> $(VIRTUALENV_DIR)/bin/activate.fish
	#echo 'set -gx PYTHONPATH $$_OLD_PYTHONPATH $(COMPONENT_PYTHONPATH)' >> $(VIRTUALENV_DIR)/bin/activate.fish
	#echo 'functions -c deactivate old_deactivate' >> $(VIRTUALENV_DIR)/bin/activate.fish
	#echo 'function deactivate' >> $(VIRTUALENV_DIR)/bin/activate.fish
	#echo '  if test -n $$_OLD_PYTHONPATH' >> $(VIRTUALENV_DIR)/bin/activate.fish
	#echo '    set -gx PYTHONPATH $$_OLD_PYTHONPATH' >> $(VIRTUALENV_DIR)/bin/activate.fish
	#echo '    set -e _OLD_PYTHONPATH' >> $(VIRTUALENV_DIR)/bin/activate.fish
	#echo '  end' >> $(VIRTUALENV_DIR)/bin/activate.fish
	#echo '  old_deactivate' >> $(VIRTUALENV_DIR)/bin/activate.fish
	#echo '  functions -e old_deactivate' >> $(VIRTUALENV_DIR)/bin/activate.fish
	#echo 'end' >> $(VIRTUALENV_DIR)/bin/activate.fish
	#touch $(VIRTUALENV_DIR)/bin/activate.fish

.PHONY: tests
tests: pytests

.PHONY: pytests
pytests: compile requirements .flake8 .pylint .pytests-coverage

.PHONY: .pytests
.pytests: compile .configgen .generate-api-spec .unit-tests .itests clean

.PHONY: .pytests-coverage
.pytests-coverage: .unit-tests-coverage-html .itests-coverage-html clean

.PHONY: unit-tests
unit-tests: requirements .unit-tests

.PHONY: .unit-tests
.unit-tests:
	@echo
	@echo "==================== tests ===================="
	@echo
	@echo "----- Dropping st2-test db -----"
	@mongo st2-test --eval "db.dropDatabase();"
	@for component in $(COMPONENTS_TEST); do\
		echo "==========================================================="; \
		echo "Running tests in" $$component; \
		echo "==========================================================="; \
		. $(VIRTUALENV_DIR)/bin/activate; nosetests $(NOSE_OPTS) -s -v $$component/tests/unit || exit 1; \
	done

.PHONY: .unit-tests-coverage-html
.unit-tests-coverage-html:
	@echo
	@echo "==================== unit tests with coverage (HTML reports) ===================="
	@echo
	@echo "----- Dropping st2-test db -----"
	@mongo st2-test --eval "db.dropDatabase();"
	@for component in $(COMPONENTS_TEST); do\
		echo "==========================================================="; \
		echo "Running tests in" $$component; \
		echo "==========================================================="; \
		. $(VIRTUALENV_DIR)/bin/activate; nosetests $(NOSE_OPTS) -s -v --with-coverage \
			--cover-inclusive --cover-html \
			--cover-package=$(COMPONENTS_TEST_COMMA) $$component/tests/unit || exit 1; \
	done

.PHONY: itests
itests: requirements .itests

.PHONY: .itests
.itests:
	@echo
	@echo "==================== integration tests ===================="
	@echo
	@echo "----- Dropping st2-test db -----"
	@mongo st2-test --eval "db.dropDatabase();"
	@for component in $(COMPONENTS_TEST); do\
		echo "==========================================================="; \
		echo "Running tests in" $$component; \
		echo "==========================================================="; \
		. $(VIRTUALENV_DIR)/bin/activate; nosetests $(NOSE_OPTS) -s -v $$component/tests/integration || exit 1; \
	done

.PHONY: .itests-coverage-html
.itests-coverage-html:
	@echo
	@echo "================ integration tests with coverage (HTML reports) ================"
	@echo
	@echo "----- Dropping st2-test db -----"
	@mongo st2-test --eval "db.dropDatabase();"
	@for component in $(COMPONENTS_TEST); do\
		echo "==========================================================="; \
		echo "Running tests in" $$component; \
		echo "==========================================================="; \
		. $(VIRTUALENV_DIR)/bin/activate; nosetests $(NOSE_OPTS) -s -v --with-coverage \
			--cover-inclusive --cover-html \
			--cover-package=$(COMPONENTS_TEST_COMMA) $$component/tests/integration || exit 1; \
	done

.PHONY: mistral-itests
mistral-itests: requirements .mistral-itests

.PHONY: .mistral-itests
.mistral-itests:
	@echo
	@echo "==================== MISTRAL integration tests ===================="
	@echo "The tests assume both st2 and mistral are running on 127.0.0.1."
	@echo
	. $(VIRTUALENV_DIR)/bin/activate; nosetests $(NOSE_OPTS) -s -v st2tests/integration/mistral || exit 1;

.PHONY: .mistral-itests-coverage-html
.mistral-itests-coverage-html:
	@echo
	@echo "==================== MISTRAL integration tests with coverage (HTML reports) ===================="
	@echo "The tests assume both st2 and mistral are running on 127.0.0.1."
	@echo
	. $(VIRTUALENV_DIR)/bin/activate; nosetests $(NOSE_OPTS) -s -v --with-coverage \
		--cover-inclusive --cover-html st2tests/integration/mistral || exit 1;

.PHONY: packs-tests
packs-tests: requirements .packs-tests

.PHONY: .packs-tests
.packs-tests:
	@echo
	@echo "==================== packs-tests ===================="
	@echo
	. $(VIRTUALENV_DIR)/bin/activate; find ${ROOT_DIR}/contrib/* -maxdepth 0 -type d -print0 | xargs -0 -I FILENAME ./st2common/bin/st2-run-pack-tests -c -t -x -p FILENAME


.PHONY: runners-tests
packs-tests: requirements .runners-tests

.PHONY: .runners-tests
.runners-tests:
	@echo
	@echo "==================== runners-tests ===================="
	@echo
	@echo "----- Dropping st2-test db -----"
	@mongo st2-test --eval "db.dropDatabase();"
	@for component in $(COMPONENTS_RUNNERS); do\
		echo "==========================================================="; \
		echo "Running tests in" $$component; \
		echo "==========================================================="; \
		. $(VIRTUALENV_DIR)/bin/activate; nosetests $(NOSE_OPTS) -s -v $$component/tests/unit || exit 1; \
	done


.PHONY: cli
cli:
	@echo
	@echo "=================== Building st2 client ==================="
	@echo
	pushd $(CURDIR) && cd st2client && ((python setup.py develop || printf "\n\n!!! ERROR: BUILD FAILED !!!\n") || popd)

.PHONY: rpms
rpms:
	@echo
	@echo "==================== rpm ===================="
	@echo
	rm -Rf ~/rpmbuild
	$(foreach COM,$(COMPONENTS), pushd $(COM); make rpm; popd;)
	pushd st2client && make rpm && popd

rhel-rpms:
	@echo
	@echo "==================== rpm ===================="
	@echo
	rm -Rf ~/rpmbuild
	$(foreach COM,$(COMPONENTS), pushd $(COM); make rhel-rpm; popd;)
	pushd st2client && make rhel-rpm && popd

.PHONY: debs
debs:
	@echo
	@echo "==================== deb ===================="
	@echo
	rm -Rf ~/debbuild
	$(foreach COM,$(COMPONENTS), pushd $(COM); make deb; popd;)
	pushd st2client && make deb && popd

# >>>>
.PHONY: .sdist-requirements
.sdist-requirements:
	# Copy over shared dist utils module which is needed by setup.py
	@for component in $(COMPONENTS_WITH_RUNNERS); do\
		cp -f ./scripts/dist_utils.py $$component/dist_utils.py;\
	done

	# Copy over CHANGELOG.RST, CONTRIBUTING.RST and LICENSE file to each component directory
	#@for component in $(COMPONENTS_TEST); do\
	#	test -s $$component/README.rst || cp -f README.rst $$component/; \
	#	cp -f CONTRIBUTING.rst $$component/; \
	#	cp -f LICENSE $$component/; \
	#done


.PHONY: ci
ci: ci-checks ci-unit ci-integration ci-mistral ci-packs-tests

.PHONY: ci-checks
ci-checks: compile .generated-files-check .pylint .flake8 .bandit .st2client-dependencies-check .st2common-circular-dependencies-check circle-lint-api-spec .rst-check

.PHONY: ci-py3-unit
ci-py3-unit:
	@echo
	@echo "==================== ci-py3-unit ===================="
	@echo
	tox -e py36 -vv

.PHONY: .rst-check
.rst-check:
	@echo
	@echo "==================== rst-check ===================="
	@echo
	. $(VIRTUALENV_DIR)/bin/activate; rstcheck --report warning CHANGELOG.rst

.PHONY: .generated-files-check
.generated-files-check:
	# Verify that all the files which are automatically generated have indeed been re-generated and
	# committed
	@echo "==================== generated-files-check ===================="

	# 1. Sample config - conf/st2.conf.sample
	cp conf/st2.conf.sample /tmp/st2.conf.sample.upstream
	make .configgen
	diff conf/st2.conf.sample /tmp/st2.conf.sample.upstream || (echo "conf/st2.conf.sample hasn't been re-generated and committed. Please run \"make configgen\" and include and commit the generated file." && exit 1)
	# 2. OpenAPI definition file - st2common/st2common/openapi.yaml (generated from
	# st2common/st2common/openapi.yaml.j2)
	cp st2common/st2common/openapi.yaml /tmp/openapi.yaml.upstream
	make .generate-api-spec
	diff st2common/st2common/openapi.yaml  /tmp/openapi.yaml.upstream || (echo "st2common/st2common/openapi.yaml hasn't been re-generated and committed. Please run \"make generate-api-spec\" and include and commit the generated file." && exit 1)

	@echo "All automatically generated files are up to date."

.PHONY: ci-unit
ci-unit: .unit-tests-coverage-html

.PHONY: .ci-prepare-integration
.ci-prepare-integration:
	sudo -E ./scripts/travis/prepare-integration.sh

.PHONY: ci-integration
ci-integration: .ci-prepare-integration .itests-coverage-html

.PHONY: .ci-prepare-mistral
.ci-prepare-mistral:
	sudo -E ./scripts/travis/setup-mistral.sh

.PHONY: ci-mistral
ci-mistral: .ci-prepare-integration .ci-prepare-mistral .mistral-itests-coverage-html

.PHONY: ci-packs-tests
ci-packs-tests: .packs-tests
