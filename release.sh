#!/usr/bin/env bash

bookml_report="$RUNNER_TEMP"/auxdir/bookml-report.log
workflow_report="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/$GITHUB_RUN_ATTEMPT"
output_messages="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/job/$JOB_CHECK_RUN_ID"

blobUrl="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/blob/$GITHUB_SHA/"
workflowUrl="${GITHUB_WORKFLOW_REF%@*}"
workflowUrl=".github/workflows/${workflowUrl#*/.github/workflows/}"
workflowUrl="$blobUrl$workflowUrl"

# Header
case $OUTCOME in
  invalid)
    header="**The configuration of [your GitHub workflow]($workflowUrl) seems invalid.**  "$'\n'
    header+=$'Check that the values of `timeout-minutes`, `scheme`, `version` are valid.\n'
    outcome=invalid ;;
  success)
    outcome=successful ;;
  timeout)
    header=$'**Compiling has timed out.**  \n'
    header+="Increase \`timeout-minutes\` in [your GitHub workflow]($workflowUrl) to allow more time."$'\n'
    outcome='timed out' ;;
  cancelled)
    header=$'**The workflow was cancelled while compiling.**  \n'
    header+=$'This may happen, for instance, if the workflow runs for more than 360 minutes.\n'
    outcome=cancelled ;;
  *)
    header=$'**An error has occurred.**\n'
    outcome=failed ;;
esac

[[ -z $header ]] || header+=$'\n'

if [[ ! -e "$bookml_report" ]] ; then
  header+=$'**BookML did not run.**\n'
elif [[ -z $TARGETS ]] ; then
  header+=$'**BookML did not try to compile any file.**  \n'
  header+=$'Please check that .tex files containing `\documentclass` exist in the top folder and that their filenames have no spaces.\n'
else
  read -r -a outputs <<< "$OUTPUTS"
  read -r -a targets <<< "$TARGETS"
  if [[ ${#outputs[@]} -eq 0 ]] ; then
    header+=$'**No target has been compiled successfully.**  \n'
  elif [[ ${#outputs[@]} < ${#targets[@]} ]] ; then
    header+="**Only ${#outputs[@]} out of ${#targets[@]} targets "
    if [[ ${#outputs[@]} -eq 1 ]] ; then header+='has' ; else header+='have' ; fi
    header+=$' been compiled successfully.**  \n'
  else
    header+="**All targets have been compiled successfully.**"$'  \n'
  fi
  for target in "${targets[@]}" ; do
    if [[ " ${outputs[*]} " != *" $target "* ]] ; then
      failed+=("$target")
    fi
  done
  [[ ${#outputs[@]} -eq 0 ]] || header+="Successful targets: ${outputs[*]}"$'  \n'
  [[ ${#failed[@]} -eq 0 ]] || header+="Failed targets: ${failed[*]}"$'  \n'
fi

# Error messages
if [[ -e "$bookml_report" ]] ; then
  if [[ $VERSION == v0.* ]] ; then
    subver="${VERSION#v0.}"
    subver="${subver%%.*}"
    [[ $subver -lt 21 ]] || fullPaths=true
  else
    fullPaths=true
  fi
  if [[ $fullPaths == true ]] ; then
    fileLineFromTo='<a target="_blank" href="'"$blobUrl"'\3#L\4C\5-L\7C\9"><ins>\3</ins></a>'
    fileLine='<a target="_blank" href="'"$blobUrl"'\3#L\4C\6"><ins>\3</ins></a>'
  fi
  # the sed expressions include logic for generating links to line/columns
  # unfortunately, LaTeXML does not include the path to the file, so we cannot use it yet
  messages="$(sed -E -n -e 's!&!\&amp;!g ; s!\\!\&bsol;!g ; s!<!\&lt;!g ; s!>!\&gt;!g ; s!"!\&quot;!g' \
                -e 's!^([a-zA-Z]+:[^: ]+:[^ ]*)( .* at )(/[^; ]+|String|bookml/[^; ]+)(;.*)?$!<samp><b>\1</b>\2\3\4</samp>!' \
                -e 's!^([a-zA-Z]+:[^: ]+:[^ ]*)( .* at )([^; ]+); from line ([0-9]+)( col ([0-9]+))? to line ([0-9]+)( col ([0-9]+))?$!<samp><b>\1</b>\2'"${fileLineFromTo-'\3'}"'; from line \4\5 to line \7\8</samp>!' \
                -e 's!^([a-zA-Z]+:[^: ]+:[^ ]*)( .* at )([^; ]+); line ([0-9]+)( col ([0-9]+))?$!<samp><b>\1</b>\2'"${fileLine-'\3'}"'; line \4\5</samp>!' \
                -e 's!^((Warning|Error|Fatal):[^: ]+:[^ ]*)( .*)$!<samp><b>\1</b>\3</samp>!' \
                -e 's!C(-L[0-9]+C[0-9]*")!\1!' -e 's!C"!"!' \
                -e '/^!/{ : generic-error ; N ; s!^(.*\n)(\./([^: ]*))(:([0-9]+):)(.*)$!|💥|<samp>\1<b><a target="_blank" href="'"$blobUrl"'\3#L\5"><ins>\2</ins></a>\4</b>\6</samp>|! ; $s!(.*)!|💥|<samp>\1</samp>|! ; T generic-error ; s!\n+!<br/>!gp }' \
                -e '/^\.\/[^: ]*:[0-9]+:/{ s!^(\./([^: ]*))(:([0-9]+):)(.*)$!|💥|<samp><b><a target="_blank" href="'"$blobUrl"'\2#L\4"><ins>\1</ins></a>\3</b>\5</samp>! ; N ; s!</samp>\n(l\.[0-9]+\s.*)$!<br/>\1</samp>!p ; t line-done ; P ; D ; : line-done }' \
                -e 's!^((Conversion|Postprocessing) (complete|failed):?)(.* \(See )([^\)]+)(\).*)$!<samp><b>\1</b>\4'"${AUX_URL:+<a href=\"$AUX_URL\">}"'<ins>\5</ins>'"${AUX_URL:+</a>}"'\6</samp>!' \
                -e 's!^((Conversion|Postprocessing) failed)(.*)$!<samp><b>\1</b>\3</samp>!' \
                -e 's!^(<samp><b>Info:.*)$!|🔵|\1|!p' \
                -e 's!^(<samp><b>Warning:.*)$!|⚠️|\1|!p' \
                -e 's!^(<samp><b>Error:.*)$!|❌|\1|!p' \
                -e 's!^(<samp><b>Fatal:.*)$!|💥|\1|!p' \
                -e 's!^(<samp><b>(Conversion|Postprocessing) complete.*)$!|💬|\1|!p' \
                -e 's!^(<samp><b>(Conversion|Postprocessing) failed.*)$!|💥|\1|!p' \
              < "$bookml_report" || :)"
  [[ -z $messages ]] || messagesHeader=$'\n---\n\n||Warnings and errors|\n|-|-|\n'
fi

if [[ $RELEASE == true ]] ; then
  # Release title
  title="$outcome: $MESSAGE"

  tag="bookml-$GITHUB_RUN_NUMBER-$GITHUB_RUN_ATTEMPT"
  downUrl="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/releases/download/$tag"

  # Add links to each output in Downloads section
  for output in $OUTPUTS ; do
    downloads+="- [$output]($downUrl/$output)"$'\n'
  done

  # Release notes
  notes="$header"
  notes+=$'\n'"All details can be found in the [summary workflow report]($workflow_report)${AUX_URL:+, the logs in the [aux directory]($AUX_URL),} and the [output messages]($output_messages)."$'\n'
  [[ -z $downloads ]] || notes+=$'\n### Downloads\n'"$downloads"

  if [[ -n $messages ]] ; then
    notes+="$messagesHeader"

    # GitHub release notes limit is 125000 bytes
    LC_ALL=C # switch to C to count bytes rather than Unicode characters
    max=$((125000 - ${#notes}))
    if [[ $max -lt ${#messages} ]] ; then
      truncErrors=$'|🌊|Some messages have been removed to fit within the GitHub release notes size limits.|'
      trunc=$((${#messages} - max + ${#truncErrors}))
      truncatedMessages="${messages:$trunc:${#messages}}"
      [[ $truncatedMessages =~ ^'- '[^\`$'\n']*'```'[^\`$'\n']*'```' ]] || truncatedMessages="${truncatedMessages#*$'\n'}"
      notes+="$truncErrors$truncatedMessages"
    else
      notes+="$messages"
    fi
  fi

  release="$(gh release create "$tag" --target="$GITHUB_REF_NAME" --repo="$GITHUB_REPOSITORY" --title="$title" --notes="$notes" $OUTPUTS 2>&1)"
  ret="$?"

  if [[ $ret != 0 ]] ; then
    echo "::error title=GitHub release failed::${release//$'\n'/%0A}"
    escapedRelease="${release//&/'&amp;'}"
    escapedRelease="${escapedRelease//</'&lt;'}"
    escapedRelease="${escapedRelease//>/'&gt;'}"
    echo "$header"$'\n**Release failed with message:**\n\n'"<pre><samp>$escapedRelease</samp></pre>"$'\n\n'"${AUX_URL:+${OUTPUTS:+All outputs can still be downloaded from the [aux directory]($AUX_URL). }}Further details can be found in the ${AUX_URL:+logs in the [aux directory]($AUX_URL) and the }[output messages]($output_messages)." >> "$GITHUB_STEP_SUMMARY"
    [[ -z $messages ]] || echo -n "$messagesHeader$messages" >> "$GITHUB_STEP_SUMMARY"
    exit "$ret"
  else
    echo "$release"
    echo "release-url=$release" >> "$GITHUB_OUTPUT"
    echo "$header"$'\n'"[Release page]($release)."$'\n\n'"${AUX_URL:+${OUTPUTS:+All outputs can also be downloaded from the [aux directory]($AUX_URL). }}Further details can be found in the ${AUX_URL:+logs in the [aux directory]($AUX_URL) and the }[output messages]($output_messages)." >> "$GITHUB_STEP_SUMMARY"
    [[ -z $downloads ]] || echo -n $'\n### Downloads\n'"$downloads" >> "$GITHUB_STEP_SUMMARY"
    [[ -z $messages ]] || echo -n "$messagesHeader$messages" >> "$GITHUB_STEP_SUMMARY"
  fi
else
  echo "$header"$'\n'"${AUX_URL:+${OUTPUTS:+All outputs can be downloaded from the [aux directory]($AUX_URL). }}Further details can be found in the ${AUX_URL:+logs in the [aux directory]($AUX_URL) and the }[output messages]($output_messages)." >> "$GITHUB_STEP_SUMMARY"
  [[ -z $messages ]] || echo -n "$messagesHeader$messages" >> "$GITHUB_STEP_SUMMARY"
fi
