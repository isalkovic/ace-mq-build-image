ARG BASE_IMAGE=cp.icr.io/cp/ibm-mqadvanced-server:9.2.0.0-r3

FROM golang:1.14.2 as builder

WORKDIR /go/src/github.com/ot4i/ace-docker/
ARG IMAGE_REVISION="Not specified"
ARG IMAGE_SOURCE="Not specified"

COPY go.mod .
COPY go.sum .
RUN go mod download

COPY cmd/ ./cmd
COPY internal/ ./internal
RUN go version
RUN go build -ldflags "-X \"main.ImageCreated=$(date --iso-8601=seconds)\" -X \"main.ImageRevision=$IMAGE_REVISION\" -X \"main.ImageSource=$IMAGE_SOURCE\"" ./cmd/runaceserver/
RUN go build ./cmd/chkaceready/
RUN go build ./cmd/chkacehealthy/

# Run all unit tests
RUN go test -v ./cmd/runaceserver/
RUN go test -v ./internal/...
RUN go vet ./cmd/... ./internal/...

ARG ACE_INSTALL=ace-12.0.0.13.tar.gz
ARG IFIX_LIST=""

WORKDIR /opt/ibm

COPY deps/$ACE_INSTALL .
COPY ./ApplyIFixes.sh /opt/ibm

RUN mkdir ace-12
RUN tar -xzf $ACE_INSTALL --absolute-names --exclude ace-12.\*/tools --exclude ace-12.\*/server/bin/TADataCollector.sh --exclude ace-12.\*/server/transformationAdvisor/ta-plugin-ace.jar --strip-components 1 --directory /opt/ibm/ace-12 \
  && ./ApplyIFixes.sh $IFIX_LIST \
  && rm ./ApplyIFixes.sh

FROM $BASE_IMAGE

ENV SUMMARY="Integration Server for App Connect Enterprise" \
    DESCRIPTION="Integration Server for App Connect Enterprise" \
    PRODNAME="AppConnectEnterprise" \
    COMPNAME="IntegrationServer"

LABEL summary="$SUMMARY" \
      description="$DESCRIPTION" \
      io.k8s.description="$DESCRIPTION" \
      io.k8s.display-name="Integration Server for App Connect Enterprise" \
      io.openshift.tags="$PRODNAME,$COMPNAME" \
      com.redhat.component="$PRODNAME-$COMPNAME" \
      name="$PRODNAME/$COMPNAME" \
      vendor="IBM" \
      version="11.0.0.13" \
      release="1" \
      license="IBM" \
      maintainer="Hybrid Integration Platform Cloud" \
      io.openshift.expose-services="" \
      usage=""

USER root

# Add required license as text file in Liceses directory (GPL, MIT, APACHE, Partner End User Agreement, etc)
COPY /licenses/ /licenses/
COPY LICENSE /licenses/licensing.txt

# Create OpenTracing directories, update permissions and copy in any library or configuration files needed
RUN mkdir /etc/ACEOpenTracing /opt/ACEOpenTracing /var/log/ACEOpenTracing && chmod 777 /var/log/ACEOpenTracing /etc/ACEOpenTracing
COPY deps/OpenTracing/library/* ./opt/ACEOpenTracing/
COPY deps/OpenTracing/config/* ./etc/ACEOpenTracing/

WORKDIR /opt/ibm

RUN microdnf install findutils util-linux unzip python3 tar procps
RUN microdnf update
RUN microdnf clean all

RUN ln -s /usr/bin/python3 /usr/local/bin/python
COPY --from=builder /opt/ibm/ace-12 /opt/ibm/ace-12

RUN /opt/ibm/ace-12/ace make registry global accept license silently

# Copy in PID1 process
COPY --from=builder /go/src/github.com/ot4i/ace-docker/runaceserver /usr/local/bin/
COPY --from=builder /go/src/github.com/ot4i/ace-docker/chkace* /usr/local/bin/

# Copy in script files
COPY *.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin

# Install kubernetes cli
COPY ubi/install-kubectl.sh /usr/local/bin/
RUN chmod u+x /usr/local/bin/install-kubectl.sh \
  && install-kubectl.sh

# Create a user to run as, create the ace workdir, and chmod script files
RUN /opt/ibm/ace-12/ace make registry global accept license silently \
  && useradd -u 1001 -d /home/aceuser -G mqbrkrs,wheel,root aceuser \
  && mkdir -p /var/mqsi \
  && mkdir -p /home/aceuser/initial-config \
  && su - -c '. /opt/ibm/ace-12/server/bin/mqsiprofile && mqsicreateworkdir /home/aceuser/ace-server' \
  && chmod -R 777 /home/aceuser \
  && chmod -R 777 /var/mqsi \
  && su - -c '. /opt/ibm/ace-12/server/bin/mqsiprofile && echo $MQSI_JREPATH && chmod g+w $MQSI_JREPATH/lib/security/cacerts' \
  && chgrp -R 0 /run/runmqserver \
  && chmod -R g=u /run/runmqserver \
  && chgrp -R 0 /run/mqm \
  && chmod -R g=u /run/mqm \
  && chgrp -R 0 /etc/mqm \
  && chmod -R g=u /etc/mqm

# Set BASH_ENV to source mqsiprofile when using docker exec bash -c
ENV BASH_ENV=/usr/local/bin/ace_env.sh
ENV LOG_FORMAT=basic
ENV USE_QMGR=true

WORKDIR /home/aceuser

USER 1001

COPY sample/mqsc/* /etc/mqm/.
COPY sample/bars_aceonly /home/aceuser/bars
COPY sample/bars_mq /home/aceuser/bars

USER root
RUN chmod -R ugo+rwx /home/aceuser

RUN ace_compile_bars.sh

# Set entrypoint to run management script
ENTRYPOINT ["runaceserver"]