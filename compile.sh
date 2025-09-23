#!/usr/bin/env bash

# input validation
if ! [[ $TIMEOUT_MINUTES =~ ^[0-9]+$ ]] ; then
  workflow="${GITHUB_WORKFLOW_REF%@*}"
  workflow=".github/workflows/${workflow#*/.github/workflows/}"
  workflow_lineno="$(sed -n '/timeout-minutes:/{=;q;}' < "$workflow")"
  echo "::error file=$workflow,line=${workflow_lineno:-1},title=Invalid timeout-minutes value::The value '$TIMEOUT_MINUTES' of timeout-minutes is not a positive integer."
  echo 'outcome=invalid' >> "$GITHUB_OUTPUT"
  exit 1
fi

### Download BookML image
case $SCHEME in
  full) scheme= ;;
  *) scheme="-$SCHEME" ;;
esac
IMAGE="ghcr.io/vlmantova/bookml$scheme:$VERSION"

echo "::group::Downloading BookML image \`$IMAGE\`"
docker pull "$IMAGE"
ret="$?"
if [[ $ret != 0 ]] ; then
  workflow="${GITHUB_WORKFLOW_REF%@*}"
  workflow=".github/workflows/${workflow#*/.github/workflows/}"
  workflow_lineno="$(sed -n '/scheme:/{=;q;}' < "$workflow")"
  workflow_lineno="${workflow_lineno:-$(sed -n '/version:/{=;q;}' < "$workflow")}"
  echo "::error file=$workflow,line=${workflow_lineno:-1},title=Could not download Docker image::Could not download Docker image $IMAGE. Check if version '$VERSION' and scheme '$SCHEME' are valid."
  echo 'outcome=invalid' >> "$GITHUB_OUTPUT"
  exit "$ret"
fi
echo "::endgroup::"
### end Download BookML image

### Compile with BookML image
echo "::add-matcher::$GITHUB_ACTION_PATH/bookml.json"
restartToken="restart-commands-$RANDOM$RANDOM"
echo "::stop-commands::$restartToken"

# TODO: parallel build
docker run --rm --interactive=true --volume="$GITHUB_WORKSPACE":/source \
  --volume="$RUNNER_TEMP/auxdir":/auxdir --volume="$GITHUB_OUTPUT":/github-output\
  --env=REPLACE_BOOKML="$REPLACE_BOOKML" --env=TIMEOUT_MINUTES="$TIMEOUT_MINUTES" \
  --entrypoint /bin/bash "$IMAGE" -s <<'EOF'
if [[ $REPLACE_BOOKML == true ]] ; then
  /run-bookml update || echo '::error title=Could not replace the bookml/ folder::Could not replace the bookml/ folder.'
fi

export max_print_line=10000

timeout "$TIMEOUT_MINUTES"m /run-bookml -k all AUX_DIR=/auxdir 2>&1 | tee /auxdir/bookml-report

case "${PIPESTATUS[0]}" in
  124|137) outcome=timeout
    echo "::error title=Compiling timed out::Increase \`timeout-minutes\` to allow more time." ;;
  0) outcome=success ;;
  *) outcome=failure ;;
esac

targets="$(grep '^ Targets: ' < /auxdir/bookml-report | head -n 1 | sed -E -e 's/^.*:\s*|(\s| )*$//g')"
outputs="$(ls -C --width=0 $targets 2>/dev/null || :)"

echo "outcome=$outcome" >> /github-output
echo "targets=$targets" >> /github-output
echo "outputs=$outputs" >> /github-output
EOF

echo "::$restartToken::"
echo "::remove-matcher owner=bookml-latex-errors::"
echo "::remove-matcher owner=bookml-latexml-errors::"
echo "::remove-matcher owner=bookml-latexml-warnings::"

grep -q '^outcome=success$' "$GITHUB_OUTPUT"

### end Compile with BookML image
