if($(git status -s)){
    Write-Output "The working directory is dirty. Please commit any pending changes."
    exit 1;
}

Write-Output "Deleting old docsation"
Remove-Item -Recurse -Force docs
mkdir docs
git worktree prune
Remove-Item -Recurse -Force .git/worktrees/docs/

Write-Output "Checking out gh-pages branch into docs"
git worktree add -B gh-pages docs origin/gh-pages

Write-Output "Removing existing files"
Remove-Item -Recurse -Force docs/*

Write-Output "Generating site"
$env:HUGO_ENV="production" && hugo -t github-style -d docs

Write-Output "Updating gh-pages branch"
Set-Location docs && git add --all && git commit -m "Publishing to gh-pages (publish.sh)"

#Write-Output "Pushing to github"
#git push --all