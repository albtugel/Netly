FROM swift:6.0-noble AS build
WORKDIR /build

COPY Package.swift ./
RUN swift package resolve

COPY Sources ./Sources
RUN swift build -c release --static-swift-stdlib

FROM ubuntu:noble
RUN apt-get update && apt-get install -y ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /build/.build/release/App ./App

EXPOSE 8081
ENTRYPOINT ["./App"]
