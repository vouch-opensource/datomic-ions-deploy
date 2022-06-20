FROM alpine:3.11 as download-aws

RUN apk add --update curl unzip

WORKDIR /aws

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN unzip -q awscliv2.zip

FROM vouchio/clj-jdk8-alpine:1.10.1

RUN apk add --update --no-cache openssh git curl
RUN curl -s https://raw.githubusercontent.com/borkdude/jet/master/install -o install_jet && \
    chmod +x ./install_jet && \
    ./install_jet

COPY --from=download-aws /aws /aws
WORKDIR /aws
RUN ./aws/install
RUN rm -rf /aws

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
