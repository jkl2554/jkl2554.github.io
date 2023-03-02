if($(git status -s)){
    Write-Output "The working directory is dirty. Please commit any pending changes."
    exit 1;
}

# Write-Output "Deleting old docsation"
Remove-Item -Recurse -Force public
mkdir public
git worktree prune
Remove-Item -Recurse -Force .git/worktrees/public/

# Write-Output "Checking out gh-pages branch into public"
git worktree add -B gh-pages public origin/gh-pages

Write-Output "Removing existing files"
Remove-Item -Recurse -Force public/* -Exclude "CNAME"

Write-Output "Generating site"
$env:HUGO_ENV="production" && hugo -t github-style

Write-Output "Updating gh-pages branch"
Set-Location public && git add --all && git commit -m "Publishing to gh-pages (publish.sh)"

Write-Output "Pushing to github"
git push --all

Set-Location ../