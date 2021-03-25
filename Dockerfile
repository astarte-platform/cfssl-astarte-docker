FROM golang:1.14-buster as builder

WORKDIR /build

# Install deps
RUN go get github.com/GeertJohan/go.rice/rice

# Install goose
RUN go get bitbucket.org/liamstask/goose/cmd/goose

# Build CFSSL 1.5.0 (static binary)
RUN git clone https://github.com/cloudflare/cfssl && cd cfssl && git checkout v1.5.0 && \
  cd cli/serve && rice embed-go && cd - && \
  make

FROM debian:buster-slim

# Install jq
RUN apt-get update && apt-get -qq install curl jq netcat && apt-get clean && rm -rf /var/lib/apt/lists/* && \
  mkdir /data && mkdir /config

# Get what we built.
COPY --from=builder /build/cfssl/bin/* /usr/local/bin/
COPY --from=builder /go/bin/* /usr/local/bin/
# And the goose migrations
COPY --from=builder /build/cfssl/certdb/sqlite /usr/local/share/cfssl/certdb/sqlite3
COPY --from=builder /build/cfssl/certdb/pg /usr/local/share/cfssl/certdb/postgres
COPY --from=builder /build/cfssl/certdb/mysql /usr/local/share/cfssl/certdb/mysql
# And the default configuration
COPY etc/* /etc/cfssl/
# And the startup script
COPY bin/start-cfssl.sh /usr/local/bin/

# Add the wait-for utility
RUN cd /usr/local/bin && \
  curl -X GET -O https://raw.githubusercontent.com/eficode/wait-for/master/wait-for && chmod +x wait-for && cd -

RUN chmod +x /usr/local/bin/start-cfssl.sh

VOLUME ["/data", "/config"]
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/start-cfssl.sh"]

CMD ["cfssl", \
     "serve", \
     "-address=0.0.0.0", \
     "-port=8080"]
