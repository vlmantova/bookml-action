#!/usr/bin/env bash

# input validation
if ! [[ $TIMEOUT_MINUTES =~ ^[0-9]+$ ]] ; then
  echo "▶▶▶ BookML action ERROR: timeout-minutes must be a positive integer."
  exit 1
fi

case $SCHEME in
  full) SCHEME= ;;
  *) SCHEME="-$SCHEME" ;;
esac

IMAGE="ghcr.io/vlmantova/bookml$SCHEME:$VERSION"

echo "▸▸▸ BookML action: downloading \`$IMAGE\`"
docker pull "$IMAGE"
ret="$?"
if [[ $ret != 0 ]] ; then
  echo "▸▸▸ BookML action FATAL: could not download Docker image \`$IMAGE\`. Check if version and scheme are valid."
  exit "$ret"
fi

# TODO: parallel build
echo "▸▸▸ BookML action: running \`$IMAGE\`"
docker run --rm --interactive=true --volume="$GITHUB_WORKSPACE":/source \
  --env=REPLACE_BOOKML="$REPLACE_BOOKML" --env=TIMEOUT_MINUTES="$TIMEOUT_MINUTES" \
  --env=GITHUB_OUTPUT="$GITHUB_OUTPUT" --entrypoint /bin/bash "$IMAGE" -s <<'EOF'
if [[ $REPLACE_BOOKML == true ]] ; then
  /run-bookml update || echo '▸▸▸ BookML action ERROR: could not replace the `bookml/` folder.'
fi

timeout "$TIMEOUT_MINUTES"m /run-bookml -k all 2>&1 | tee .git/bookml-report

case "${PIPESTATUS[0]}" in
  124|137) outcome=cancelled ;;
  0) outcome=success ;;
  *) outcome=failed ;;
esac

/run-bookml aux-zip

targets="$(grep '^ Targets: ' < .git/bookml-report | head -n 1 | sed -E -e 's/^.*:\s*|(\s| )*$//g' -e 's/\s+/, /g')"

echo "outcome=$outcome" >> .git/github-output
echo "targets=$targets" >> .git/github-output
EOF

cat .git/github-output >> "$GITHUB_OUTPUT"
