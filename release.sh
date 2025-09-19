#!/usr/bin/env bash

TARGETS="${TARGETS// /, }"

tag="bookml-$GITHUB_RUN_NUMBER-$GITHUB_RUN_ATTEMPT"
downUrl="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/releases/download/$tag"

# Downloads section
downloads=$'\n'"### Downloads"
for output in $OUTPUTS ; do
  downloads+=$'\n'"- [$output]($downUrl/$output)"
done

auxzip="$(ls AUX.*.zip 2>/dev/null || : | head -n 1)"
downloads+=$'\n'"- [$auxzip]($downUrl/$auxzip)"

# Header
case $OUTCOME in
  cancelled)
    header=$'\n'"Compiling outputs $TARGETS has been cancelled."
    if [[ -n $OUTPUTS ]] ; then
      header+=$'\n'"Only ${OUTPUTS// /, } have been compiled."
    else
      header+=$'\nNo outputs have been compiled.'
    fi
    header+=$'\nIncrease `timeout-minutes` to allow more time.'
    title='cancelled' ;;
  success)
    if [[ -z $TARGETS ]] ; then
      header=$'\nNo outputs have been built.'
      header+=$'\nPlease check that that .tex files containing `\documentclass` exist in the top folder and that their filenames have no spaces.'
      header+=$'\n'"Consult the [AUX file]($downUrl/$auxzip) for more information."
    else
      header=$'\n'"All outputs $TARGETS have been compiled successfully."
    fi
    title='successful' ;;
  *)
    if [[ -n $OUTPUTS ]] ; then
      header=$'\n'"Only ${OUTPUTS// /, } have been compiled successfully, out of intended targets $TARGETS."
    else
      header=$'\n'"No outputs have been compiled, out of intended targets $TARGETS."
    fi
    header+=$'\n'"Consult the [AUX file]($downUrl/$auxzip) for more information."
    title='failed' ;;
esac

# Error messages
ERRORS="$(grep -E '^([^:]*):([0-9]+):\s*(.*)$|^(Error|Fatal):([^:]+:.*) at ([^;]+);( from)?( line ([0-9]+))?( col ([0-9]+))?( to line [0-9]+( col [0-9]+)?)?$' < .git/bookml-report || :)"

if [[ -n $ERRORS ]] ; then
  errorMessages=$'\n\n### Error messages\n'
  while IFS= read -r error ; do
   errorMessages+=$'\n- '"$error"
  done <<< "$ERRORS"
fi

# Release title
title="$title compiling: $MESSAGE"

# Messages
# note: the body of a GitHub release cannot exceed 125000 bytes
SIZE="$(wc -c < .git/bookml-report)"
MAX=$((124000 - ${#header} - ${#downloads} - ${#errorMessages}))
if [[ $SIZE -gt $MAX ]] ; then
  read -r -d '' messages<<EOF
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
  read -r -d '' messages<<EOF
### Full output messages
<pre><code>
$(cat .git/bookml-report)
</code></pre>
EOF

else
  read -r -d '' messages<<EOF
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

# Release notes
read -r -d '' notes <<EOF
$header
$downloads
$errorMessages

Full [workflow report]($GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/$GITHUB_RUN_ATTEMPT).
$messages
EOF

output="$(gh release create "$tag" --target="$GITHUB_REF_NAME" --repo="$GITHUB_REPOSITORY" --title="$title" --notes="$notes" $OUTPUTS "$auxzip" 2>&1)"
ret="$?"
if [[ $ret != 0 ]] ; then
  echo "::error title=GitHub release failed::${output//$'\n'/%0A}"
  echo "$header"$'\n'"$errorMessages" >> "$GITHUB_STEP_SUMMARY"
  exit "$ret"
else
  echo "$output"
  echo "$header"$'\n'"$downloads"$'\n\n'"[Release page]($output)."$'\n'"$errorMessages" >> "$GITHUB_STEP_SUMMARY"
fi
