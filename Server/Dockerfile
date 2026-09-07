# syntax=docker/dockerfile:1
FROM docker.io/library/golang:1.26.5-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/vr-platform-server .

FROM gcr.io/distroless/static-debian13:nonroot

LABEL org.opencontainers.image.source="https://forgejo.maio-tech.com/Sammy/Generic-Vr-Platform"
COPY --from=build /out/vr-platform-server /vr-platform-server
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/vr-platform-server"]
