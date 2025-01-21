#!/usr/bin/env bash

case $OUTCOME in
  cancelled)
    HEADER="**The build of outputs $TARGETS has been cancelled.** Some outputs may be missing. Increase \`timeout-minutes\` to allow more time."
    TITLE='cancelled' ;;
  success)
    if [[ -n $TARGETS ]] ; then
      HEADER="**Outputs $TARGETS have been built.**"
    else
      HEADER='**No outputs have been built.** Please check that that .tex files containing `\documentclass` exist in the top folder and that their filenames have no spaces.'
    fi
    TITLE='successful' ;;
  *)
    HEADER="**Some of the outputs $TARGETS have failed to build.** Consult the AUX file for more information."
    TITLE='failed' ;;
esac

TITLE="$TITLE build: $MESSAGE"

read -r -d '' NOTES <<EOF
$HEADER

*Commit message:* $MESSAGE

### Summarised output messages
<pre><code>
$(head -n 5 .git/bookml-report)

[...]

$(tail -n 5 .git/bookml-report)
</code></pre>

### Full output messages
<details><summary><b>Click to show full output</b></summary>
<pre><code>
$(cat .git/bookml-report)
</code></pre></details>
EOF

exec gh release create "build-$RUN" --target="$REF" --repo="$GITHUB_REPOSITORY" --title="$TITLE" --notes="$NOTES" ./*.zip
