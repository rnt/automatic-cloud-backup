FROM bash:latest
LABEL maintainer="Renato Covarrubias <rnt@rnt.cl>"

RUN apk add --no-cache jq curl openssl file

COPY backup.sh /backup.sh
COPY upload_aws_s3.sh /upload_aws_s3.sh

CMD ["/backup.sh"]
