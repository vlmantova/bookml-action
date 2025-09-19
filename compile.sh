#!/usr/bin/env bash

restartToken="restart-commands-$RANDOM$RANDOM"

echo "::add-matcher::$GITHUB_ACTION_PATH/bookml.json"

# input validation
if ! [[ $TIMEOUT_MINUTES =~ ^[0-9]+$ ]] ; then
  workflow="${GITHUB_WORKFLOW_REF%@*}"
  workflow=".github/workflows/${workflow#*/.github/workflows/}"
  workflow_lineno="$(sed -n '/timeout-minutes:/{=;q;}' < "$workflow")"
  echo "::error file=$workflow,line=${workflow_lineno:-1},title=Invalid timeout-minutes value::The argument timeout-minutes must be a positive integer."
  exit 1
fi

case $SCHEME in
  full) SCHEME= ;;
  *) SCHEME="-$SCHEME" ;;
esac

IMAGE="ghcr.io/vlmantova/bookml$SCHEME:$VERSION"

echo "::group::Downloading BookML image \`$IMAGE\`"
docker pull "$IMAGE"
ret="$?"
if [[ $ret != 0 ]] ; then
  workflow="${GITHUB_WORKFLOW_REF%@*}"
  workflow=".github/workflows/${workflow#*/.github/workflows/}"
  workflow_lineno="$(sed -n '/scheme:/{=;q;}' < "$workflow")"
  workflow_lineno="${workflow_lineno:-$(sed -n '/version:/{=;q;}' < "$workflow")}"
  echo "::error file=$workflow,line=${workflow_lineno:-1},title=Could not download Docker image::Could not download Docker image $IMAGE. Check if version and scheme are valid."
  exit "$ret"
fi
echo "::endgroup::"

# TODO: parallel build
echo "::group::Compiling using BookML image \`$IMAGE\`"
echo "::stop-commands::$restartToken"

docker run --rm --interactive=true --volume="$GITHUB_WORKSPACE":/source \
  --env=REPLACE_BOOKML="$REPLACE_BOOKML" --env=TIMEOUT_MINUTES="$TIMEOUT_MINUTES" \
  --env=GITHUB_OUTPUT="$GITHUB_OUTPUT" --entrypoint /bin/bash "$IMAGE" -s <<'EOF'
if [[ $REPLACE_BOOKML == true ]] ; then
  /run-bookml update || echo '::error title=Could not replace the bookml/ folder::Could not replace the bookml/ folder.'
fi

export max_print_line=10000

timeout "$TIMEOUT_MINUTES"m /run-bookml -k all 2>&1 | tee .git/bookml-report

case "${PIPESTATUS[0]}" in
  124|137) outcome=cancelled
    echo "::error title=Compiling cancelled::Increase \`timeout-minutes\` to allow more time." ;;
  0) outcome=success ;;
  *) outcome=failed ;;
esac

/run-bookml aux-zip

targets="$(grep '^ Targets: ' < .git/bookml-report | head -n 1 | sed -E -e 's/^.*:\s*|(\s| )*$//g')"
outputs="$(ls -C --width=0 $targets 2>/dev/null || :)"

echo "outcome=$outcome" >> .git/github-output
echo "targets=$targets" >> .git/github-output
echo "outputs=$outputs" >> .git/github-output
EOF

echo "::$restartToken::"

echo "::endgroup::"
echo "::remove-matcher owner=bookml-latex-errors::"
echo "::remove-matcher owner=bookml-latexml-errors::"
echo "::remove-matcher owner=bookml-latexml-warnings::"

cat .git/github-output >> "$GITHUB_OUTPUT"
