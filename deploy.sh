#!/bin/sh

if [ "`git status -s`" ]
then
    echo "The working directory is dirty. Please commit any pending changes."
    exit 1;
fi

echo "Deleting old docsation"
rm -rf docs
mkdir docs
git worktree prune
rm -rf .git/worktrees/docs/

echo "Checking out gh-pages branch into docs"
git worktree add -B gh-pages docs origin/gh-pages

echo "Removing existing files"
rm -rf docs/*

echo "Generating site"
env HUGO_ENV="production" hugo -t github-style -d docs

echo "Updating gh-pages branch"
cd docs && git add --all && git commit -m "Publishing to gh-pages (publish.sh)"

#echo "Pushing to github"
#git push --all