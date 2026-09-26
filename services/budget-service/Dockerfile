FROM swift:6.2-noble AS build
WORKDIR /build

COPY Package.swift ./
RUN swift package resolve

# Tests are copied because the manifest declares a test target; only the App product is built.
COPY Sources ./Sources
COPY Tests ./Tests
RUN swift build -c release --static-swift-stdlib --product App

FROM ubuntu:noble
RUN apt-get update && apt-get install -y ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /build/.build/release/App ./App

EXPOSE 8082
ENTRYPOINT ["./App"]
