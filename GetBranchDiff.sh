#!/usr/bin/env bash

set -x
SourceBranch=$1
TargetBranch=$2
OutputFilename=$3
TEMP_BRANCH="$4"

git fetch
git branch -d develop
echo "checkout develop"
git checkout origin/develop
# and do a pull
#git pull origin develop
echo "Check out the target branch"
git branch -d $TargetBranch

git checkout $TargetBranch
# and pull
#git pull origin $TargetBranch

echo "now create a branch from target"
git checkout -b $TEMP_BRANCH
git merge origin/$SourceBranch

CONFLICTS=$(git ls-files -u | wc -l)
if [ "$CONFLICTS" -gt 0 ]; then
	echo "There is a merge conflict. Aborting"
	git merge --abort
	exit 1
else

	git diff --name-status origin/${TargetBranch}..$TEMP_BRANCH -- >$OutputFilename
fi
