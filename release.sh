#!/usr/bin/env bash

case $OUTCOME in
  cancelled)
    HEADER="**Compiling outputs $TARGETS has been cancelled.** Some outputs may be missing. Increase \`timeout-minutes\` to allow more time."
    TITLE='cancelled' ;;
  success)
    if [[ -n $TARGETS ]] ; then
      HEADER="**Outputs $TARGETS have been compiled.**"
    else
      HEADER='**No outputs have been built.** Please check that that .tex files containing `\documentclass` exist in the top folder and that their filenames have no spaces.'
    fi
    TITLE='successful' ;;
  *)
    HEADER="**Some of the outputs $TARGETS have failed to compile.** Consult the AUX file for more information."
    TITLE='failed' ;;
esac

TITLE="$TITLE compiling: $MESSAGE"

# the body of a GitHub release cannot exceed 125000 bytes
MESSAGES=""
SIZE="$(wc -c < .git/bookml-report)"
MAX=120000
if [[ $SIZE -gt $MAX ]] ; then
  read -r -d '' MESSAGES<<EOF
### Summarised output messages
<pre><code>
$(head -n 5 .git/bookml-report)

[...]

$(tail -n 5 .git/bookml-report)
</code></pre>

### Truncated output messages
<details><summary><b>Click to show the last $MAX characters of the output messages</b></summary>
<pre><code>
[TRUNCATED] $(tail -c $MAX .git/bookml-report)
</code></pre></details>
EOF

elif [[ $(wc -l < .git/bookml-report) -lt 20 ]] ; then
  read -r -d '' MESSAGES<<EOF
### Full output messages
<pre><code>
$(cat .git/bookml-report)
</code></pre>
EOF

else
  read -r -d '' MESSAGES<<EOF
### Summarised output messages
<pre><code>
$(head -n 5 .git/bookml-report)

[...]

$(tail -n 5 .git/bookml-report)
</code></pre>

### Full output messages
<details><summary><b>Click to show the full output messages</b></summary>
<pre><code>
$(cat .git/bookml-report)
</code></pre></details>
EOF
fi

read -r -d '' NOTES <<EOF
$HEADER

*Commit message:* $MESSAGE

$MESSAGES
EOF

output="$(gh release create "build-$RUN" --target="$REF" --repo="$GITHUB_REPOSITORY" --title="$TITLE" --notes="$NOTES" ./*.zip 2>&1)"
ret="$?"
if [[ $ret != 0 ]] ; then
  echo "::error title=GitHub release failed::${output//$'\n'/%0A}"
  exit "$ret"
else
  echo "$output"
fi
