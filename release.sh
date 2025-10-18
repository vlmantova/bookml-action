#!/usr/bin/env bash

bookml_report="$RUNNER_TEMP"/auxdir/bookml-report.log
workflow_report="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/$GITHUB_RUN_ATTEMPT"
output_messages="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/job/$JOB_CHECK_RUN_ID"

# Header
case $OUTCOME in
  invalid)
    header=$'**The configuration of your GitHub workflow seems invalid.**\n'
    header+=$'Check that the values of `timeout-minutes`, `scheme`, `version` are valid.\n'
    outcome=invalid ;;
  success)
    outcome=successful ;;
  timeout)
    header="**Compiling outputs $TARGETS has timed out.**"$'\n'
    header+=$'Increase `timeout-minutes` to allow more time.\n'
    outcome='timed out' ;;
  cancelled)
    header="**The workflow was cancelled while compiling $TARGETS.**"$'\n'
    header+=$'This may happen, for instance, if the workflow runs for more than 360 minutes.\n'
    outcome=cancelled ;;
  *)
    header=$'**An error has occurred.**\n'
    outcome=failed ;;
esac

[[ -z $header ]] || header+=$'\n'

if [[ ! -f "$bookml_report" ]] ; then
  header+=$'**BookML did not run.**\n'
elif [[ -z $TARGETS ]] ; then
  header+=$'**BookML did not try to compile any file.**\n'
  header+=$'Please check that .tex files containing `\documentclass` exist in the top folder and that their filenames have no spaces.\n'
elif [[ -z $OUTPUTS ]] ; then
  header+="**No outputs have been compiled, out of intended targets ${TARGETS// /, }.**"$'\n'
else
  read -r -a outputs <<< "$OUTPUTS"
  read -r -a targets <<< "$TARGETS"
  if [[ ${#outputs[@]} < ${#targets[@]} ]] ; then
    header+="**Only ${OUTPUTS// /, } have been compiled, out of intended targets ${TARGETS// /, }.**"$'\n'
  else
    header+="**All outputs ${TARGETS// /, } have been compiled.**"$'\n'
  fi
fi

# Error messages
if [[ -e "$bookml_report" ]] ; then
  blobUrl="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/blob/$GITHUB_SHA/"
  if [[ $VERSION == v0.* ]] ; then
    subver="${VERSION#v0.}"
    subver="${subver%%.*}"
    [[ $subver -lt 21 ]] || fullPaths=true
  else
    fullPaths=true
  fi
  if [[ $fullPaths == true ]] ; then
    fileLineFromTo='<a href="'"$blobUrl"'\3#L\4C\5-L\7C\9">\3</a>'
    fileLine='<a href="'"$blobUrl"'\3#L\4C\6">\3</a>'
  fi
  # the sed expressions include logic for generating links to line/columns
  # unfortunately, LaTeXML does not include the path to the file, so we cannot use it yet
  messages="$(sed -E -n -e 's!&!\&amp;!g ; s!\\!\&bsol;!g ; s!<!\&lt;!g ; s!>!\&gt;!g ; s!"!\&quot;!g' \
                -e 's!^([a-zA-Z]+:[^: ]+:[^ ]*)( .* at )(/[^; ]+|String|bookml/[^; ]+)(;.*)?$!<samp><b>\1</b>\2<ins>\3</ins>\4</samp>!' \
                -e 's!^([a-zA-Z]+:[^: ]+:[^ ]*)( .* at )([^; ]+); from line ([0-9]+)( col ([0-9]+))? to line ([0-9]+)( col ([0-9]+))?$!<samp><b>\1</b>\2'"${fileLineFromTo-'\3'}"'; from line \4\5 to line \7\8</samp>!' \
                -e 's!^([a-zA-Z]+:[^: ]+:[^ ]*)( .* at )([^; ]+); line ([0-9]+)( col ([0-9]+))?$!<samp><b>\1</b>\2'"${fileLine-'\3'}"'; line \4\5</samp>!' \
                -e 's!^((Warning|Error|Fatal):[^: ]+:[^ ]*)( .*)$!<samp><b>\1</b>\3</samp>!' \
                -e 's!C(-L[0-9]+C[0-9]*")!\1!' -e 's!C"!"!' \
                -e 's!^(\./([^: ]*))(:([0-9]+):)(.*)$!|💥|<samp><b><a href="'"$blobUrl"'\2#L\4"><ins>\1</ins></a></ins>\3</b>\5</samp>|!p' \
                -e 's!^((Conversion|Postprocessing) (complete|failed):?)(.* \(See )([^\)]+)(\).*)$!<samp><b>\1</b>\4<ins>\5</ins>\6</samp>!' \
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
    echo "$header"$'\n**Release failed with message:**\n\n'"<pre><samp>$escapedRelease</samp></pre>"$'\n\n'"Consult the ${AUX_URL:+logs in the [aux directory]($AUX_URL) and the }[output messages]($output_messages) for more information." >> "$GITHUB_STEP_SUMMARY"
    [[ -z $messages ]] || echo -n "$messagesHeader$messages" >> "$GITHUB_STEP_SUMMARY"
    exit "$ret"
  else
    echo "$release"
    echo "release-url=$release" >> "$GITHUB_OUTPUT"
    echo "$header"$'\n'"All details can be found in the ${AUX_URL:+the logs in the [aux directory]($AUX_URL) and the }[output messages]($output_messages)."$'\n\n'"[Release page]($release)." >> "$GITHUB_STEP_SUMMARY"
    [[ -z $downloads ]] || echo -n $'\n### Downloads\n'"$downloads" >> "$GITHUB_STEP_SUMMARY"
    [[ -z $messages ]] || echo -n "$messagesHeader$messages" >> "$GITHUB_STEP_SUMMARY"
  fi
else
  echo "$header"$'\n'"All details can be found in the ${AUX_URL:+logs in the [aux directory]($AUX_URL) and the }[output messages]($output_messages)." >> "$GITHUB_STEP_SUMMARY"
  [[ -z $messages ]] || echo -n "$messagesHeader$messages" >> "$GITHUB_STEP_SUMMARY"
fi
