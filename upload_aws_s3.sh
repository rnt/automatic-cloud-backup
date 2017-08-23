#!/bin/bash

CONFIG="${CONFIG:-${HOME}/.backup.sh.vars}"

AWS_S3_BUCKET=${AWS_S3_BUCKET:-bucket}
AWS_S3_BUCKET_ZONE=${AWS_S3_BUCKET_ZONE:-s3}
AWS_S3_KEY=${AWS_S3_KEY:-key}
AWS_S3_SECRET=${AWS_S3_SECRET:-secret}

VERBOSE=${VERBOSE:-0}

if [ -r "$CONFIG" ]; then
    . $CONFIG
fi

function show_help(){
    cat - << _EOF
Usage:
    $0 --file FILE [--verbose]
    $0 --help

Arguments:
  -f, --f
    Set file to upload to AWS S3.
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

while [[ $# -ge 1 ]]; do
    key="$1"

    case $key in
        -f|--file)
            FILE=$2
            shift
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

resource="/${AWS_S3_BUCKET}/${FILE}"
contentType=$(file -b --mime-type $FILE)
dateValue=`date -R`
stringToSign="PUT\n\n${contentType}\n${dateValue}\n${resource}"

signature=`echo -en ${stringToSign} | openssl sha1 -hmac ${AWS_S3_SECRET} -binary | base64`

show_log "Uploading $FILE to $AWS_S3_BUCKET"

curl -X PUT -T "${FILE}" \
    -H "Host: ${AWS_S3_BUCKET}.${AWS_S3_BUCKET_ZONE}.amazonaws.com" \
    -H "Date: ${dateValue}" \
    -H "Content-Type: ${contentType}" \
    -H "Authorization: AWS ${AWS_S3_KEY}:${signature}" \
    https://${AWS_S3_BUCKET}.${AWS_S3_BUCKET_ZONE}.amazonaws.com/${FILE}

curl_rc=$?
if [ $curl_rc -eq 0 ]; then
    show_log "File uploaded successfully"
else
    show_error "Problems uploading the file, curl end with return code 0."
fi
