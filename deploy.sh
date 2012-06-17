git diff-index --quiet HEAD -- || {
  echo >&2 "Repo has local changes! Please commit them before deploying."
  exit 1
}
git pull || {
  echo >&2 "Pull failed, aborting."
  exit 1
}
npm test || {
  echo >&2 "Test failed, aborting."
  exit 1
}
jitsu deploy || {
  echo >&2 "Deployment failed, aborting."
  exit 1
}
VERSION=`cat package.json | json -a -C "version"`
git add package.json
git commit -m $VERSION
git push
