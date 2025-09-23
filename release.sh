#!/usr/bin/env bash

bookml_report="$RUNNER_TEMP"/auxdir/bookml-report
workflow_report="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/$GITHUB_RUN_ATTEMPT"
consult="Consult the [workflow report]($workflow_report)${AUX_URL:+ and the logs in the [aux directory]($AUX_URL)} for more information."

# Header
case $OUTCOME in
  invalid)
    header="**The configuration of your GitHub workflow seems invalid.**"
    header+=$'\nCheck that the values of `timeout-minutes`, `scheme`, `version` are valid.'
    outcome=invalid ;;
  success)
    outcome=successful ;;
  timeout)
    header="**Compiling outputs $TARGETS has timed out.**"
    header+=$'\nIncrease `timeout-minutes` to allow more time.'
    header+=$'\n'"$consult"
    outcome='timed out' ;;
  cancelled)
    header="**The workflow was cancelled while compiling $TARGETS.**"
    header+=$'\n'"This may happen, for instance, if the workflow runs for more than 360 minutes. $consult"
    outcome=cancelled ;;
  *)
    header="**An error has occurred.**"
    header+=$'\n'"$consult"
    outcome=failed ;;
esac

if [[ ! -f "$bookml_report" ]] ; then
  header+=$'\n'"**BookML did not run.**"
elif [[ -z $TARGETS ]] ; then
  header+=$'\n**BookML did not try to compile any file.**'
  header+=$'\nPlease check that .tex files containing `\documentclass` exist in the top folder and that their filenames have no spaces.'
elif [[ -z $OUTPUTS ]] ; then
  header+=$'\n'"**No outputs have been compiled, out of intended targets ${TARGETS// /, }.**"
else
  read -r -a outputs <<< "$OUTPUTS"
  read -r -a targets <<< "$TARGETS"
  if [[ ${#outputs[@]} < ${#targets[@]} ]] ; then
    header+=$'\n'"**Only ${OUTPUTS// /, } have been compiled, out of intended targets ${TARGETS// /, }.**"
  else
    header+=$'\n'"**All outputs ${TARGETS// /, } have been compiled.**"
  fi
fi

echo "$header" >> "$GITHUB_STEP_SUMMARY"

# Error messages
if [[ -e "$bookml_report" ]] ; then
  errors="$(grep -E '^([^:]*):([0-9]+):\s*(.*)$|^(Error|Fatal):([^:]+:.*) at ([^;]+);( from)?( line ([0-9]+))?( col ([0-9]+))?( to line [0-9]+( col [0-9]+)?)?$' < "$bookml_report" || :)"
  errors="${errors%$'\n'}"
  if [[ -n $errors ]] ; then
    errorMessages=$'### Error messages\n\n- '"${errors//$'\n'/$'\n'- }"
  fi
fi


if [[ -n $AUX_URL ]] ; then
  aux_download=$'\n'"- [aux directory]($AUX_URL) including all outputs and other compilation products (this link will expire after the number of retention days specified in your repository settings)"
fi

if [[ $RELEASE == true ]] ; then
  # Release title
  title="$outcome: $MESSAGE"

  tag="bookml-$GITHUB_RUN_NUMBER-$GITHUB_RUN_ATTEMPT"
  downUrl="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/releases/download/$tag"

  if [[ -e $bookml_report ]] ; then
    # Messages
    # note: the body of a GitHub release cannot exceed 125000 bytes
    if [[ $(wc -l < "$bookml_report") -lt 20 ]] ; then
      messages='### Full output messages'
      messages+=$'\n<pre><code>\n'
      messages+="$(cat "$bookml_report")"
      messages+=$'</code></pre>\n'
    else
      SIZE="$(wc -c < "$bookml_report")"
      MAX=$((124000 - ${#header} - ${#downloads} - ${#errorMessages}))
      messages='### Summarised output messages'
      messages+=$'\n<pre><code>\n'
      messages+="$(head -n 5 "$bookml_report")"
      messages+=$'\n[...]\n\n'
      messages+="$(tail -n 5 "$bookml_report")"
      messages+=$'</code></pre>\n'
      if [[ $SIZE -gt $MAX ]] ; then
        messages+=$'\n### Truncated output messages'
        messages+=$'\n'"<details><summary><b>Click to show the last $MAX characters of the output messages</b></summary>"
        messages+=$'\n<pre><code>\n'
        messages+="[TRUNCATED] $(tail -c $MAX "$bookml_report")"
        messages+=$'\n'"</code></pre></details>"
      else
        messages+=$'\n### Full output messages'
        messages+=$'\n'"<details><summary><b>Click to show the full output messages</b></summary>"
        messages+=$'\n<pre><code>\n'
        messages+="$(cat "$bookml_report")"
        messages+=$'\n'"</code></pre></details>"
      fi
    fi
  fi

  # Add links to each output in Downloads section
  for output in $OUTPUTS ; do
    downloads+=$'\n'"- [$output]($downUrl/$output)"
  done

  downloads+="$aux_download"

  # Release notes
  notes="$header"
  [[ -z $downloads ]] || notes+=$'\n\n### Downloads\n\n'"$downloads"
  [[ -z $errorMessages ]] || notes+=$'\n\n'"$errorMessages"
  notes+=$'\n\n'"Full [workflow report]($workflow_report)."
  notes+=$'\n\n'"$messages"

  release="$(gh release create "$tag" --target="$GITHUB_REF_NAME" --repo="$GITHUB_REPOSITORY" --title="$title" --notes="$notes" $OUTPUTS 2>&1)"
  ret="$?"

  if [[ $ret != 0 ]] ; then
    echo "::error title=GitHub release failed::${release//$'\n'/%0A}"
    [[ -z $aux_download ]] || echo $'\n### Downloads\n\n'"$aux_download" >> "$GITHUB_STEP_SUMMARY"
    [[ -z $errorMessages ]] || echo $'\n'"$errorMessages" >> "$GITHUB_STEP_SUMMARY"
    exit "$ret"
  else
    echo "$release"
    echo "release-url=$release" >> "$GITHUB_OUTPUT"
    [[ -z $downloads ]] || echo $'\n### Downloads\n'"$downloads" >> "$GITHUB_STEP_SUMMARY"
    echo $'\n'"[Release page]($release)." >> "$GITHUB_STEP_SUMMARY"
    [[ -z $errorMessages ]] || echo $'\n'"$errorMessages" >> "$GITHUB_STEP_SUMMARY"
  fi
else
  [[ -z $aux_download ]] || echo $'\n### Downloads\n'"$aux_download" >> "$GITHUB_STEP_SUMMARY"
  [[ -z $errorMessages ]] || echo $'\n'"$errorMessages" >> "$GITHUB_STEP_SUMMARY"
fi
