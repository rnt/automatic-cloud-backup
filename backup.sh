#!/usr/bin/env bash

CONFIG="${CONFIG:-${HOME}/.backup.sh.vars}"

USERNAME=${USERNAME:-youruser}
PASSWORD=${PASSWORD:-yourpassword}
INSTANCE=${INSTANCE:-example.atlassian.net}
LOCATION=${LOCATION:-/tmp}

TIMESTAMP=${TIMESTAMP:-true}
TIMEZONE=${TIMEZONE:-America/Los_Angeles}
SLEEP_SECONDS=${SLEEP_SECONDS:-60}
PROGRESS_CHECKS=${PROGRESS_CHECKS:-100}

ATTACHMENTS=${ATTACHMENTS:-true}
SOURCE=${SOURCE:-jira}

VERBOSE=${VERBOSE:-0}

if [ -r "$CONFIG" ]; then
    . $CONFIG
fi

DOWNLOAD_URL="https://${INSTANCE}"
INSTANCE_PATH=$INSTANCE

if [[  $2 == "wiki" ]] || [[ $2 == "confluence" ]]; then
    INSTANCE_PATH=$INSTANCE/wiki
    DOWNLOAD_URL="https://${INSTANCE_PATH}/download"
    FILEPREFIX="CONFLUENCE"
else
    FILEPREFIX="JIRA"
fi

function show_help(){
    cat - << _EOF
Usage:
    $0 [--source SOURCE] [--attachments BOOL] [--timestamp BOOL] [--verbose]
    $0 --help

Arguments:
  -a, --attachments
    Set if attachments should be in the backup.
    Values are "true" (default) or "false".
    Default: "$ATTACHMENTS"
  -s, --source
    Set what backup should be created.
    Set the argument to "wiki" or "confluence" to backup Confluence.
    Default source is "jira".
  -t, --timestamp
    Set if we should overwrite the previous backup or append a timestamp
    (default) to prevent just that. The former is useful when an external
    backup program handles backup rotation.
    Set the argument to "false" if there should be no timestamp in the
    filename.
  -v, --verbose
    Enable verbose output.
  -h, --help
    Show this help.

_EOF
}

function show_log(){
    if [ $VERBOSE -gt 0 ]; then
        echo "$(date "+[%Y-%m-%d %H:%M:%S]") $@"
    fi
}

function show_error(){
    echo "$(date "+[%Y-%m-%d %H:%M:%S]") ERROR: $@" >&2
}

while [[ $# -gt 1 ]]
do
    key="$1"

    case $key in
        -s|--source)
            if [[  $2 == "wiki" ]] || [[ $2 == "confluence" ]]; then
                INSTANCE_PATH=$INSTANCE/wiki
                DOWNLOAD_URL="https://${INSTANCE_PATH}/download"
                FILEPREFIX="CONFLUENCE"
            fi
            shift # past argument
            ;;
        -a|--attachments)
            if [[  $2 == "false" ]]; then
                ATTACHMENTS="false"
            fi
            shift # past argument
            ;;
        -t|--timestamp)
            if [[  $2 == "false" ]]; then
                TIMESTAMP=false
            fi
            shift # past argument
            ;;
        -v|--verbose)
            VERBOSE=$((VERBOSE+1))
            shift # past argument
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
    esac
    shift # past argument or value
done

BASENAME=$1
RUNBACKUP_URL="https://${INSTANCE_PATH}/rest/obm/1.0/runbackup"
PROGRESS_URL="https://${INSTANCE_PATH}/rest/obm/1.0/getprogress.json"

# Grabs cookies and generates the backup on the UI.
TODAY=$(TZ=$TIMEZONE date +%Y%m%d)

# Check if we should overwrite the previous backup or append a timestamp to
# prevent just that. The former is useful when an external backup program
# handles backup rotation.
if [ $TIMESTAMP = "true" ]; then
    OUTFILE="${LOCATION}/${FILEPREFIX}-${INSTANCE}-backup-${TODAY}.zip"
elif [ $TIMESTAMP = "false" ]; then
    OUTFILE="${LOCATION}/${FILEPREFIX}-${INSTANCE}-backup.zip"
else
    show_error "Invalid value for TIMESTAMP: should be either \"true\" or \"false\""
    exit 1
fi

COOKIE_FILE_LOCATION="$HOME/.backup.sh-$INSTANCE-cookie"

# Only generate a new cookie if one does not exist, or if it is more than 24
# hours old. This is to allow reuse of the same cookie until a new backup can
# be triggered.
find $COOKIE_FILE_LOCATION -mtime -1 2> /dev/null | grep $COOKIE_FILE_LOCATION 2>&1 > /dev/null
if [ $? -ne 0 ]; then
    show_log "Authenticate in $INSTANCE with username $USERNAME."
    curl --silent --cookie-jar $COOKIE_FILE_LOCATION -X POST "https://${INSTANCE}/rest/auth/1/session" -d "{\"username\": \"$USERNAME\", \"password\": \"$PASSWORD\"}" -H 'Content-Type: application/json' --output /dev/null
    chmod 600 $COOKIE_FILE_LOCATION
else
    show_log "Using previous authentication in $INSTANCE."
fi

# The $BKPMSG variable will print the error message, you can use it if you're planning on sending an email
BKPMSG=$(curl -s --cookie $COOKIE_FILE_LOCATION --header "X-Atlassian-Token: no-check" -H "X-Requested-With: XMLHttpRequest" -H "Content-Type: application/json" -X POST $RUNBACKUP_URL -d "{\"cbAttachments\":\"${ATTACHMENTS}\" }" )

# Checks if we were authorized to create a new backup
if [ "$(echo "$BKPMSG" | grep -c -e Unauthorized -e "dead link")" -ne 0 ]  || [ "$(echo "$BKPMSG" | grep -ic "<status-code>401</status-code>")" -ne 0 ]; then
    show_error "Authorization failure in $INSTANCE with username $USERNAME"
    exit 2
fi

#Checks if the backup exists every 10 seconds, 20 times. If you have a bigger instance with a larger backup file you'll probably want to increase that.
for (( c=1; c<=$PROGRESS_CHECKS; c++ )) do
    PROGRESS_JSON=$(curl -s --cookie $COOKIE_FILE_LOCATION $PROGRESS_URL)
    FILE_NAME=$(echo "$PROGRESS_JSON" | jq --raw-output ".fileName")
    FILE_SIZE=$(echo "$PROGRESS_JSON" | jq --raw-output ".size")
    currentStatus=$(echo "$PROGRESS_JSON" | jq --raw-output ".currentStatus")
    alternativePercentage=$(echo "$PROGRESS_JSON" | jq --raw-output ".alternativePercentage")

    echo $PROGRESS_JSON | grep error > /dev/null && break

    if [ -n "$FILE_NAME" ] && [ "$FILE_NAME" != "null" ]; then
        break
    fi
    if [ $c -lt $PROGRESS_CHECKS ]; then
        show_log "($c of $PROGRESS_CHECKS) $currentStatus. $alternativePercentage"
        sleep $SLEEP_SECONDS
    fi
done

# If after 20 attempts it still fails it ends the script.
if [ -z "$FILE_NAME" ] || [ "$FILE_NAME" == "null" ]; then
    show_error "After $PROGRESS_CHECKS checks, the backup isn't ready."
    exit 3
else
    # Download the new way, starting Nov 2016
    show_log "Downloading backup $FILE_SIZE Bytes from $FILE_NAME to $OUTFILE"
    curl -s -S -L --cookie $COOKIE_FILE_LOCATION "$DOWNLOAD_URL/$FILE_NAME" -o "$OUTFILE"
fi

if [[ -n "$UPLOAD_BACKUP" && -e "upload_${UPLOAD_BACKUP}.sh" ]]; then
    show_log "Executing upload_${UPLOAD_BACKUP}.sh"
    sh upload_$UPLOAD_BACKUP.sh --file "$OUTFILE"
fi

show_log "All done ;)"
