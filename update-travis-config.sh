#!/bin/bash
set -eo pipefail

. update-functions.sh

file=.travis.yml

# Print static part of Travis configuration
print_static_configuration() {
	cat > $1 <<-'EOI'
	#
	# ------------------------------------------------------------------------------
	#          NOTE: THIS TRAVIS CONFIGURATION IS GENERATED VIA "update.sh"
	#
	#                       PLEASE DO NOT EDIT IT DIRECTLY.
	# ------------------------------------------------------------------------------
	#
	os: linux
	dist: focal
	language: shell
	branches:
	  only:
	    - master
	before_install:
	  - set -e
	  # Configure environment so changes are picked up when the Docker daemon is restarted after upgrading
	  - echo '{"experimental":true}' | sudo tee /etc/docker/daemon.json
	  - export DOCKER_CLI_EXPERIMENTAL=enabled
	  - docker run --rm --privileged docker/binfmt:a7996909642ee92942dcd6cff44b9b95f08dad64
	  # Upgrade to Docker CE 19.03 for BuildKit support
	  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	  - sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
	  - sudo apt-get update
	  - sudo apt-get -y -o Dpkg::Options::="--force-confnew" install docker-ce=5:19.03.12~3-0~ubuntu-focal # pin version for reproducibility
	  # Show info to simplify debugging and create a builder
	  - docker info
	  - docker buildx create --name builder --use
	  - docker buildx ls
	  # Prepare openHAB container build
	  - ./update-docker-files.sh
	  - source ./update-functions.sh
	  - validate_readme_constraints
	install:
	  - build_arg_options="--build-arg BUILD_DATE=$(date +"%Y-%m-%dT%H:%M:%SZ") --build-arg VCS_REF=$TRAVIS_COMMIT --build-arg VERSION=$VERSION"
	  - tags=$(tags $VERSION $DIST)
	  - tag_options=${tags//$(docker_repo)/--tag $(docker_repo)}
	  - build_options="$build_arg_options --platform $(platforms $VERSION $DIST) $tag_options --progress plain"
	  - path="$VERSION/$DIST"
	  - if [ "$TRAVIS_BRANCH" == "master" ] && [ "$TRAVIS_PULL_REQUEST" == "false" ]; then
	        echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin;
	        docker buildx build $build_options --push $path;
	        if [ "${SYNC_README:=false}" == "true" ] && [ "$VERSION" == "$(last_stable_version)" ] && [ "$DIST" == "debian" ]; then
	            ./sync-docker-hub-readme.sh;
	        fi
	    else
	        docker buildx build $build_options $path;
	    fi
	jobs:
	  fast_finish: true
	env:
	  jobs:
EOI
}

# Print Travis matrix environment variables
print_matrix() {
	cat >> $1 <<-EOI
	    - VERSION=$version DIST=$base
EOI
}

echo -n "Writing $file... "

# Generate the static part of the Travis configuration
print_static_configuration $file;

# Generate the matrix for building Dockerfiles
for version in $(build_versions)
do
	for base in $(bases)
	do
		print_matrix $file;
	done
done

echo "done"
