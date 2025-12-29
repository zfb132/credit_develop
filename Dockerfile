FROM golang:latest AS builder

WORKDIR /app

COPY cmd.go go.mod .

RUN go mod tidy && \
    go build -o dev_tool cmd.go

FROM python:3-slim

WORKDIR /app

COPY run_server.py .

ARG TZ=Asia/Shanghai
RUN apt-get update && apt-get install -y tzdata && \
    cp /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo "${TZ}" > /etc/timezone && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir flask cryptography

COPY --from=builder /app/dev_tool /usr/local/bin/dev_tool

CMD ["python3", "run_server.py"]
