FROM icr.io/kubevirt/alpine:latest

RUN apk add git
WORKDIR /workdir
RUN git config --global --add safe.directory /workdir

COPY cli /cli

ENTRYPOINT ["/cli"]
