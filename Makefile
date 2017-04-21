.DEFAULT_GOAL := compile

define ASCISKMSGATE
 _______ _________ _______  ______          _______  _______  _______  _______  _______
(  ____  \\__   __/(  ____ \(  __  \\        (       )(  ____ \(  ____ \(  ___  )(  ____ \\
| (    \/   ) (   | (    \/| (  \  )       | () () || (    \/| (    \/| (   ) || (    \/
| (__       | |   | |      | |   ) | _____ | || || || (__    | (_____ | |   | || (_____
|  __)      | |   | |      | |   | |(_____)| |(_)| ||  __)   (_____  )| |   | |(_____  )
| (         | |   | |      | |   ) |       | |   | || (            ) || |   | |      ) |
| (____/\   | |   | (____/\| (__/  )       | )   ( || (____/\/\____) || (___) |/\____) |
(_______/   )_(   (_______/(______/        |/     \|(_______/\_______)(_______)\_______)

endef

export ASCISKMSGATE

# http://misc.flogisoft.com/bash/tip_colors_and_formatting

RED=\033[0;31m
GREEN=\033[0;32m
ORNG=\033[38;5;214m
BLUE=\033[38;5;81m
NC=\033[0m

export RED
export GREEN
export NC
export ORNG
export BLUE

DOCKER_HOST?=docker-ethos-core-univ-release.dr-uw2.adobeitc.com/ethos

help:
	@printf "\033[1m$$ASCISKMSGATE $$NC\n"
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//' | sort | xargs -n 1 -IXXX printf "\033[1mXXX $$NC\n"



SOURCES:=$(shell find . \( -name vendor \) -prune -o  -name '*.go')
.PHONY: ci test build


default: compile
install-deps:  ##  install dependencies.  Not usually needed outside of a container
install-deps:
# 	docker sometimes has trouble re-arranging ./vendor.  Better to just blow it away.  glide caches previous runs
	@test -d vendor || glide --no-color install

install-tools:  ##  installs glide, golint, ginkgo, gomock, gomegs
install-tools:
	@which golint || go get -u github.com/golang/lint/golint
	@which cover || go get golang.org/x/tools/cmd/cover
	@test -d $$GOPATH/github.com/go-ini/ini || go get github.com/go-ini/ini
	@test -d $$GOPATH/github.com/jmespath/go-jmespath ||  go get github.com/jmespath/go-jmespath
	@which ginkgo || go get github.com/onsi/ginkgo/ginkgo
	@which gomega || go get github.com/onsi/gomega
	@which gomock || go get github.com/golang/mock/gomock
	@which mockgen || go get github.com/golang/mock/mockgen
	@which glide || go get github.com/Masterminds/glide
	@which go-bindata || go get -u github.com/jteeuwen/go-bindata/...

bin/etcd: bin
	cd vendor/github.com/coreos/etcd && ./build; mv bin/* ../../../../bin/

bin/etcd-mesos-scheduler: bin
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64  go build -o bin/etcd-mesos-scheduler cmd/etcd-mesos-scheduler/app.go

bin/etcd-mesos-executor: bin
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64  go build -o bin/etcd-mesos-executor cmd/etcd-mesos-executor/app.go

bin/etcd-mesos-proxy: bin
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64  go build -o bin/etcd-mesos-proxy cmd/etcd-mesos-proxy/app.go

run-scheduler:
	go run -race cmd/etcd-mesos-scheduler/app.go -logtostderr=true

run-scheduler-with-zk:
	go run -race cmd/etcd-mesos-scheduler/app.go -logtostderr=true \
		-master="zk://localhost:2181/mesos" \
		-framework-name="etcd-t1" \
		-cluster-size=5 \
		-zk-framework-persist="zk://localhost:2181/etcd-mesos"

run-proxy:
	go run -race cmd/etcd-mesos-proxy/app.go \
		-master="zk://localhost:2181/mesos" \
		-framework-name="etcd-t1"



docker_compile:  install-deps bin/etcd-mesos-scheduler bin/etcd-mesos-executor bin/etcd-mesos-proxy bin/etcd

docker_build: install-deps docker_compile

build: test container
	if [ "x$$sha" = "x" ] ; then sha=`git rev-parse HEAD`; fi ;\
	docker push adobeplatform/etcd-mesos:$$sha ;\
	docker push adobeplatform/etcd-mesos:latest

docker_lint: install-deps
	go tool vet -all server shared skms
	@DIRS="server/... shared/... skms/..." && FAILED="false" && \
	echo "gofmt -l *.go server shared skms" && \
	GOFMT=$$(gofmt -l *.go server shared skms) && \
	if [ ! -z "$$GOFMT" ]; then echo -e "\nThe following files did not pass a 'go fmt' check:\n$$GOFMT\n" && FAILED="true"; fi; \
	for codeDir in $$DIRS; do \
		LINT="$$(golint $$codeDir)" && \
		if [ ! -z "$$LINT" ]; then echo "$$LINT" && FAILED="true"; fi; \
	done && \
	if [ "$$FAILED" = "true" ]; then exit 1; else echo "ok" ;fi


docker_test: install-deps docker_lint docker_compile
	go test -v --cover  $$(go list ./... | grep -v /vendor/)

docker_test_ci: install-deps docker_lint docker_compile
	go test -v --cover --timeout 60s $$(go list ./... | grep -v /vendor/)

docker_ci: docker_test_ci docker_compile
compile:  ##  compiles your project.  uses the dev-container
lint:  ##  lints the project.  Inside a container
ci:  ##  target for jenkins.  Inside a container 
test:  ##  tests the project.  Inside a container
compile lint test ci : dev-container
#   either ssh key or agent is needed to pull adobe-platform sources from git
#   this supplies to methods
#
	@SSH1="" ; SSH2="" ;\
	if [ "x$$sha" = "x" ] ; then sha=`git rev-parse HEAD`; fi ;\
        if [ ! -z "$$SSH_AUTH_SOCK" ] ; then SSH1="-e SSH_AUTH_SOCK=/root/.foo -v $$SSH_AUTH_SOCK:/root/.foo" ; fi ; \
        if [ -e ~/.ssh/id_rsa ]; then SSH2="-v ~/.ssh/id_rsa:/root/.ssh/id_rsa" ; fi ; \
	if [ ! -e /.dockerenv -o ! -z "$JENKINS_URL" ];  then \
	AWS=$$(env | grep AWS | xargs -n 1 -IXX echo -n ' -e XX') ;\
	echo ; \
	echo ; \
	echo "------------------------------------------------" ; \
	echo "Running target \"$@\" inside Docker container..." ; \
	echo "------------------------------------------------" ; \
	echo ; \
	docker run -i --rm $$SSH1 $$SSH2 $$AWS\
		--name=etcd_mesos_make_docker_$@ \
		-e sha=$$sha \
        -v $$(pwd):/go/src/git.corp.adobe.com/adobe-platform/etcd-mesos \
        -w /go/src/git.corp.adobe.com/adobe-platform/etcd-mesos \
		adobe-platform/etcd-mesos:dev \
		make docker_$@ ;\
	else \
		make docker_$@ ;\
	fi

upload-container: ## uploads to adobeplatform.  You need to have credentials.  Make sure you set DOCKER_CONFIG=`cd ~/.docker-hub-f4tq/;pwd`
upload-container: container
	docker push $(DOCKER_HOST)/etcd-mesos:`cat VERSION` 


# build: calls test (which takes forever).  compile doesn't rebuild unless something changed
container: ## builds adobeplatform/etcd-mesos:<current sha> AND tags it latest
container: compile
	@if [ "x$$sha" = "x" ] ; then sha=`git rev-parse HEAD`; fi ;\
	strip bin/etcd bin/etcdctl bin/etcd-mesos-scheduler bin/etcd-mesos-executor bin/etcd-mesos-proxy ;\
	docker build --tag adobeplatform/etcd-mesos:$$sha . ; \
	docker tag adobeplatform/etcd-mesos:$$sha adobeplatform/etcd-mesos:latest ;\
	docker tag adobeplatform/etcd-mesos:$$sha $(DOCKER_HOST)/etcd-mesos:`cat VERSION`

dev-container:  ##  makes dev-container.  runs make install-tools in dev-container.  Builds adobe-platform/etcd-mesos:dev
dev-container:
	@printf "\033[1m$$ASCISKMSGATE $$NC\n"

	@set -x; if [ ! -e /.dockerenv -o ! -z "$JENKINS_URL" ]; then \
		echo ; \
		echo ; \
		echo "------------------------------------------------" ; \
		echo "$@: Building dev container image..." ; \
		echo "------------------------------------------------" ; \
		echo ; \
		docker images | grep 'adobe-platform/etcd-mesos' | awk '{print $$2}' | grep -q -E '^dev$$' ; \
		if [ $$? -ne 0 ]; then  \
			docker build -f Dockerfile-dev -t adobe-platform/etcd-mesos:dev . ; \
		fi ; \
	else \
		echo ; \
		echo "------------------------------------------------" ; \
		echo "$@: Running in Docker so skipping..." ; \
		echo "------------------------------------------------" ; \
		echo ; \
		env ; \
		echo ; \
	fi

clean-dev:  ##  Remove the adobe-platform/etcd-mesos:dev
clean-dev:
	@if [ ! -e /.dockerenv -o ! -z "$JENKINS_URL" ]; then \
		if $$(docker ps | grep -q "adobe-platform/etcd-mesos:dev"); then \
			echo "You have a running dev container.  Stop it first before using clean-dev" ;\
			exit 10; \
		fi ; \
		docker images | grep 'adobe-platform/etcd-mesos' | awk '{print $$2}' | grep -q -E '^dev$$' ; \
		if [ $$? -eq 0 ]; then  \
			docker rmi adobe-platform/etcd-mesos:dev  ; \
		else \
			echo "No dev image" ;\
		fi ; \
	else \
		echo ; \
		echo "------------------------------------------------" ; \
		echo "$@: Running in Docker so skipping..." ; \
		echo "------------------------------------------------" ; \
		echo ; \
		env ; \
		echo ; \
	fi

run-dev:  ##  Runs the adobe-platform/etcd-mesos:dev container mounting the current directly.  Gives full dev environment.  Maps in your ssh-agent and keeps a bash-history outside the container so you have history between invocations.
run-dev: dev-container
#       save bash history in-between runs...
	@if [ ! -f ~/.bash_history-etcd-mesos-dev ]; then touch ~/.bash_history-etcd-mesos-dev; fi
#       mount the current directory into the dev build
#       map ssh-agent's auth-sock into the container instance.  the pipe needs to be on non-external volume hence /root/.foo
	@SSH1="" ; SSH2="" ;\
        if [ ! -z "$$SSH_AUTH_SOCK" ] ; then SSH1="-e SSH_AUTH_SOCK=/root/.foo -v $$SSH_AUTH_SOCK:/root/.foo" ; fi ; \
        if [ -e ~/.ssh/id_rsa ]; then SSH2="-v ~/.ssh/id_rsa:/root/.ssh/id_rsa" ; fi ; \
        AWS=$$(env | grep AWS | xargs -n 1 -IXX echo -n ' -e XX'); \
	docker run -i --rm --net host  $$SSH1 $$SSH2 $$AWS -e HISTSIZE=100000  -v $$HOME/.bash_history-etcd-mesos-dev:/root/.bash_history -v `pwd`:/go/src/git.corp.adobe.com/adobe-platform/etcd-mesos -w /go/src/git.corp.adobe.com/adobe-platform/etcd-mesos -t adobe-platform/etcd-mesos:dev bash ; \
	if [ $$? -ne 0 ]; then echo wow ; fi



