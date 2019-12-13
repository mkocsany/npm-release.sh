#!/bin/bash

function die_with() {
	echo "$*" >&2
	exit 1
}

function rollback_and_die_with() {
	echo "$*" >&2

	echo "Resetting release commit to return you to the same working state as before attempting a deploy"
	echo "> git reset --hard HEAD^1"
	git reset --hard HEAD^1 || echo "Git reset command failed!"

	exit 1
}

CURRENT_VERSION=$(grep 'version' package.json | cut -d '"' -f4)

echo "Current pom.xml version2: $CURRENT_VERSION"
echo ""

# Prompt for release version (or compute it automatically if requested)
RELEASE_VERSION_DEFAULT=$(echo "$CURRENT_VERSION" | perl -pe 's/-SNAPSHOT//')
if [ -z "$RELEASE_VERSION" ] ; then
	read -p "Version to release [${RELEASE_VERSION_DEFAULT}]:" RELEASE_VERSION

	if [ -z "$RELEASE_VERSION" ] ; then
		RELEASE_VERSION=$RELEASE_VERSION_DEFAULT
	fi
elif [ "$RELEASE_VERSION" = "auto" ] ; then
	RELEASE_VERSION=$RELEASE_VERSION_DEFAULT
fi

if [ "$RELEASE_VERSION" = "$CURRENT_VERSION" ] ; then
	die_with "Release version requested is exactly the same as the current pom.xml version (${CURRENT_VERSION})! Is the version in pom.xml definitely a -SNAPSHOT version?"
fi


# Prompt for next version (or compute it automatically if requested)
NEXT_VERSION_DEFAULT=$(echo "$RELEASE_VERSION" | perl -pe 's{^(([0-9]\.)+)?([0-9]+)$}{$1 . ($3 + 1)}e')
if [ -z "$NEXT_VERSION" ] ; then
	read -p "Next snapshot version [${NEXT_VERSION_DEFAULT}]:" NEXT_VERSION

	if [ -z "$NEXT_VERSION" ] ; then
		NEXT_VERSION=$NEXT_VERSION_DEFAULT
	fi
elif [ "$NEXT_VERSION" = "auto" ] ; then
	NEXT_VERSION=$NEXT_VERSION_DEFAULT
fi

# Add -SNAPSHOT to the end (and make sure we don't accidentally have it twice)
NEXT_VERSION="$(echo "$NEXT_VERSION" | perl -pe 's/-SNAPSHOT//gi')-SNAPSHOT"

if [ "$NEXT_VERSION" = "${RELEASE_VERSION}-SNAPSHOT" ] ; then
	die_with "Release version and next version are the same version!"
fi


echo ""
echo "Using $RELEASE_VERSION for release"
echo "Using $NEXT_VERSION for next development version"


#############################
# START THE RELEASE PROCESS #
#############################

VCS_RELEASE_TAG="v${RELEASE_VERSION}"

# if a release tag of this version already exists then abort immediately
if [ $(git tag -l "${VCS_RELEASE_TAG}" | wc -l) != "0" ] ; then
	die_with "A tag already exists ${VCS_RELEASE_TAG} for the release version ${RELEASE_VERSION}"
fi

echo "-------------------------------"
echo "------Push release branch -----"
echo "-------------------------------"

git checkout -b release/${VCS_RELEASE_TAG}
git merge develop
# Update the package.json versions
npm version ${RELEASE_VERSION} -m "Release version ${RELEASE_VERSION}"
git commit -a -m "Release version ${RELEASE_VERSION}" || die_with "Failed to commit updated package.json versions for release!"
git push origin release/${VCS_RELEASE_TAG} || rollback_and_die_with "Build/Deploy failure. Release failed."


echo "-------------------------------"
echo "------Push Master branch-------"
echo "-------------------------------"

git checkout master
git merge release/${VCS_RELEASE_TAG}
git push origin master || rollback_and_die_with "Build/Deploy failure. Release failed."

# tag the release (N.B. should this be before perform the release?)
git tag "v${RELEASE_VERSION}" || die_with "Failed to create tag ${RELEASE_VERSION}! Release has been deployed, however"
git push --tags || die_with "Failed to push tags. Please do this manually"


######################################
# START THE NEXT DEVELOPMENT PROCESS #
######################################

echo "--------------------------------"
echo "---Set new version to develop---"
echo "--------------------------------"

git checkout develop
git merge master

npm version ${NEXT_VERSION} -m "Start next development version ${RELEASE_VERSION}"
git commit -a -m "Start next development version ${NEXT_VERSION}" || die_with "Failed to commit updated package.json versions for next dev version! Please do this manually"

git push origin develop || die_with "Failed to push commits. Please do this manually"

read -p 'Ready ....'