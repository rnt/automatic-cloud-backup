FROM centos:centos7
LABEL maintainer="Renato Covarrubias <rnt@rnt.cl>"

RUN yum -y update &&\
    yum clean all &&\
    yum -y -q install https://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-10.noarch.rpm &&\
    yum -y -q install curl jq

COPY backup.sh /backup.sh

CMD ["/bin/bash", "/backup.sh"]
