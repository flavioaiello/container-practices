

# Container Image Best Practices

A comprehensive guide to building secure, efficient, and production-ready container images using current state-of-the-art techniques. This guide focuses on OCI-compliant practices that work across container runtimes including **Docker**, **Podman**, and **Buildah**. Container technology evolves rapidly - always verify recommendations against the latest documentation and security advisories.

Support for this repository is available through [GitHub Sponsors](https://github.com/sponsors/flavioaiello).

## Table of Contents
1. [Core Principles](#core-principles)
2. [Security Best Practices](#security-best-practices)
3. [Build Optimization](#build-optimization)
4. [Configuration Management](#configuration-management)
5. [Integration](#integration)
6. [Runtime Management](#runtime-management)
7. [Cloud-Native Patterns](#cloud-native-patterns)
8. [Modern Tooling](#modern-tooling)
9. [Container Runtimes](#container-runtimes)
10. [Operational Excellence](#operational-excellence)
11. [Compliance and Governance](#compliance-and-governance)

---

## Core Principles

> **Note:** Examples use `Dockerfile` syntax which is compatible with Docker, Podman, and Buildah.
> Podman/Buildah also support `Containerfile` as the preferred filename.

### Minimal Base Images
```dockerfile
# Use minimal, updated base images with digest pinning for reproducibility
FROM alpine:3.21
# Or distroless for even smaller attack surface
# FROM gcr.io/distroless/static-debian12

# For maximum security, pin by digest:
# FROM alpine@sha256:<digest>
```

### Multi-Stage Builds
```dockerfile
# Build stage
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o app .

# Runtime stage
FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata
COPY --from=builder --chmod=0755 --chown=1000:1000 /app/app /app
USER 1000:1000
ENTRYPOINT ["/app"]
```

### Immutable Infrastructure
- Never modify running containers
- Rebuild and redeploy for changes
- Use read-only filesystems where possible

---

## Security Best Practices

### Non-Root Execution
```dockerfile
# Create dedicated user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

# Or use numeric UID/GID
USER 1000:1000
```

### Read-Only Filesystem
```yaml
# docker-compose.yml
services:
  app:
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=100m
      - /run:rw,size=1m
```

### Capability Management
```yaml
# docker-compose.yml
services:
  app:
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - NET_BIND_SERVICE
```

### Security Profiles
```yaml
# docker-compose.yml
services:
  app:
    security_opt:
      - no-new-privileges:true
      - apparmor:docker-default
      - seccomp:seccomp-profile.json
```

### Network Security
```yaml
# docker-compose.yml - Use custom networks, never host network
networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true  # No external access

services:
  web:
    networks:
      - frontend
      - backend
    # Only expose necessary ports
    ports:
      - "127.0.0.1:8080:8080"  # Bind to localhost only
  
  database:
    networks:
      - backend  # Internal only, no frontend exposure
    # No ports exposed to host
```

```yaml
# Kubernetes NetworkPolicy - Deny all by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

### Vulnerability Scanning
```bash
# Scan images during CI (use pinned tags, not :latest)
trivy image --severity CRITICAL,HIGH myimage:v1.0.0
grype myimage:v1.0.0

# Docker Scout (replaced deprecated 'docker scan')
docker scout cves myimage:v1.0.0
docker scout quickview myimage:v1.0.0
```

### Secrets Management
```dockerfile
# Use build-time secrets (never stored in image layers)
RUN --mount=type=secret,id=github_token \
    GITHUB_TOKEN=$(cat /run/secrets/github_token) && \
    git clone https://${GITHUB_TOKEN}@github.com/myorg/myrepo.git && \
    unset GITHUB_TOKEN
```

```yaml
# docker-compose.yml
secrets:
  db_password:
    file: ./secrets/db_password.txt

services:
  app:
    secrets:
      - db_password
    environment:
      DB_PASSWORD_FILE: /run/secrets/db_password
```

---

## Build Optimization

### Build Context Security (.dockerignore / .containerignore)
```text
# .dockerignore (or .containerignore for Podman/Buildah)
# CRITICAL for security and performance
# Exclude version control
.git
.gitignore
.svn

# Exclude secrets and credentials
.env
.env.*
*.pem
*.key
*.crt
secrets/
credentials/
.aws/
.ssh/

# Exclude development files
node_modules/
__pycache__/
*.pyc
.pytest_cache/
.coverage
.tox/
.venv/
venv/

# Exclude IDE and editor files
.vscode/
.idea/
*.swp
*.swo

# Exclude documentation (usually not needed in image)
README.md
CHANGELOG.md
LICENSE
docs/

# Exclude CI/CD configs
.github/
.gitlab-ci.yml
Jenkinsfile
Dockerfile*
Containerfile*
docker-compose*.yml
podman-compose*.yml

# Exclude test files
tests/
test/
*_test.go
*.test.js
```

### Layer Caching Strategy
```dockerfile
# Order instructions from least to most frequently changed
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o app .
```

### BuildKit Features
```bash
# Enable BuildKit (default in Docker 23.0+)
export DOCKER_BUILDKIT=1

# Build with secrets (never stored in layers)
docker build --secret id=mytoken,src=/local/secret .

# Multi-platform builds with proper versioning
VERSION=$(git describe --tags --always)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg VERSION=${VERSION} \
  -t myapp:${VERSION} \
  -t myapp:latest \
  --push .
```

### Image Analysis
```bash
# Use docker-slim for optimization (analyze before slimming)
docker-slim build --http-probe myimage:v1.0.0

# Use dive to analyze layer efficiency
dive myimage:v1.0.0
```

### SBOM Generation
```bash
# Generate Software Bill of Materials
VERSION=v1.0.0
syft myimage:${VERSION} -o cyclonedx-json > sbom-${VERSION}.json
syft myimage:${VERSION} -o spdx-json > sbom-${VERSION}.spdx.json
```

---

## Configuration Management

### Environment Variables
```dockerfile
# Use env files for configuration
ENV APP_ENV=production
ENV APP_PORT=8080
```

### Configuration Injection
```bash
#!/bin/sh
# entrypoint.sh
envsubst < /app/config.template > /app/config.ini
exec "$@"
```

### ConfigMaps and Secrets (Kubernetes)
```yaml
# k8s-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  config.ini: |
    [database]
    host = ${DB_HOST}
    port = ${DB_PORT}
```

---

## Integration

### GitHub Actions Example
```yaml
name: Build and Push
on:
  push:
    branches: [ main ]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3
    - name: Log in to Container Registry
      uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    - name: Extract metadata (tags, labels)
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ghcr.io/${{ github.repository }}
        tags: |
          type=sha,prefix=
          type=semver,pattern={{version}}
          type=semver,pattern={{major}}.{{minor}}
    - name: Build and push
      uses: docker/build-push-action@v6
      with:
        context: .
        platforms: linux/amd64,linux/arm64
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
        sbom: true
        provenance: mode=max
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@0.28.0
      with:
        image-ref: 'ghcr.io/${{ github.repository }}:${{ github.sha }}'
        format: 'sarif'
        output: 'trivy-results.sarif'
        severity: 'CRITICAL,HIGH'
    - name: Upload Trivy scan results
      uses: github/codeql-action/upload-sarif@v3
      with:
        sarif_file: 'trivy-results.sarif'
```

### GitLab CI Example
```yaml
variables:
  DOCKER_TLS_CERTDIR: "/certs"

build:
  stage: build
  image: docker:27.4
  services:
    - docker:27.4-dind
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - |
      docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --build-arg VERSION=${CI_COMMIT_TAG:-$CI_COMMIT_SHORT_SHA} \
        --build-arg COMMIT_SHA=$CI_COMMIT_SHA \
        --build-arg BUILD_DATE=$(date -Iseconds) \
        -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA \
        -t $CI_REGISTRY_IMAGE:${CI_COMMIT_TAG:-latest} \
        --push .
  rules:
    - if: $CI_COMMIT_TAG
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

scan:
  stage: test
  image:
    name: aquasec/trivy:0.58.0
    entrypoint: [""]
  script:
    - trivy image --exit-code 1 --severity CRITICAL,HIGH $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  needs: [build]
```

---

## Runtime Management

### Health Checks
```dockerfile
# Option 1: Using curl (if available in image)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Option 2: Using wget (Alpine - smaller than curl)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Option 3: Native binary health check (recommended for distroless)
# Build a tiny health check binary into your app
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ["/healthcheck"]
```

### Resource Constraints
```yaml
# docker-compose.yml
services:
  app:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 512M
```

### Graceful Shutdown
```bash
#!/bin/sh
# entrypoint.sh
trap 'echo "Shutting down..."; kill -TERM $PID; wait $PID' TERM INT
"$@" &
PID=$!
wait $PID
```

### Service Dependencies
```bash
#!/bin/sh
# Wait for services with improved reliability
wait-for-it.sh db:5432 --timeout=60 --strict
wait-for-it.sh redis:6379 --timeout=30 --strict
```

---

## Cloud-Native Patterns

### Kubernetes Readiness and Liveness
```yaml
# k8s-deployment.yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 20
```

### Service Mesh Integration
```yaml
# Istio sidecar injection
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  annotations:
    sidecar.istio.io/inject: "true"
```

### Horizontal Pod Autoscaling
```yaml
# k8s-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

---

## Modern Tooling

### Container Signing
```bash
# Sign images with cosign (use versioned tags)
VERSION=v1.0.0
cosign sign --key cosign.key myimage:${VERSION}

# Keyless signing with Sigstore (recommended for CI/CD)
cosign sign myimage:${VERSION}

# Verify signatures
cosign verify --key cosign.pub myimage:${VERSION}

# Attach SBOM to image
syft myimage:${VERSION} -o cyclonedx-json | \
  cosign attach sbom --sbom - myimage:${VERSION}
```

### Multi-Architecture Builds
```bash
# Build for multiple architectures with proper versioning
docker buildx create --name multiarch --use
VERSION=$(git describe --tags --always)

docker buildx build \
  --platform linux/amd64,linux/arm64,linux/arm/v7 \
  --build-arg VERSION=${VERSION} \
  --build-arg BUILD_DATE=$(date -Iseconds) \
  --sbom=true \
  --provenance=mode=max \
  -t myapp:${VERSION} \
  --push .
```

### Container Runtime Security
```bash
# Use Falco for runtime security
falco -r /etc/falco/rules.yaml

# Runtime image scanning
trivy image --scanners vuln,secret,misconfig myimage:v1.0.0
```

---

## Container Runtimes

### Runtime Comparison

| Feature | Docker | Podman | Buildah |
|---------|--------|--------|---------|
| Daemon | Required | Daemonless | Daemonless |
| Rootless | Optional | Default | Default |
| OCI Compliant | Yes | Yes | Yes |
| Compose Support | Native | podman-compose | N/A |
| Kubernetes YAML | docker stack | podman generate kube | N/A |
| Build Images | Yes | Yes | Yes (specialized) |
| Systemd Integration | Limited | Native | N/A |

### Podman (Docker Alternative)
```bash
# Podman is a drop-in replacement for Docker CLI
# Most docker commands work by replacing 'docker' with 'podman'

# Build image (identical syntax)
podman build -t myapp:v1.0.0 .

# Run container (rootless by default)
podman run --rm -it myapp:v1.0.0

# Generate Kubernetes YAML from running container
podman generate kube mycontainer > pod.yaml

# Run pods from Kubernetes YAML
podman play kube pod.yaml

# Rootless containers with user namespaces
podman run --userns=auto myapp:v1.0.0
```

```yaml
# podman-compose.yml (compatible with docker-compose)
version: "3"
services:
  app:
    image: myapp:v1.0.0
    read_only: true
    user: "1000:1000"
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
```

### Buildah (OCI Image Builder)
```bash
# Buildah specializes in building OCI images without a daemon
# Ideal for CI/CD environments and air-gapped builds

# Build from Dockerfile/Containerfile
buildah build -t myapp:v1.0.0 .

# Build from Containerfile (preferred naming)
buildah build -f Containerfile -t myapp:v1.0.0 .

# Scripted builds (no Dockerfile needed)
container=$(buildah from alpine:3.21)
buildah run $container -- apk add --no-cache ca-certificates
buildah copy $container ./app /app
buildah config --user 1000:1000 $container
buildah config --entrypoint '["/app"]' $container
buildah commit $container myapp:v1.0.0

# Push to registry
buildah push myapp:v1.0.0 docker://registry.example.com/myapp:v1.0.0
```

### Skopeo (Image Operations)
```bash
# Copy images between registries without pulling locally
skopeo copy docker://docker.io/library/alpine:3.21 \
  docker://registry.example.com/alpine:3.21

# Inspect remote image without pulling
skopeo inspect docker://myapp:v1.0.0

# Copy with signature verification
skopeo copy --sign-by keyid docker://source/image:tag \
  docker://dest/image:tag

# Sync entire repository
skopeo sync --src docker --dest docker \
  registry.source.com/repo registry.dest.com/
```

### CI/CD with Podman/Buildah
```yaml
# GitHub Actions with Podman
name: Build with Podman
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Build image
      run: |
        podman build \
          --format oci \
          --label org.opencontainers.image.revision=${{ github.sha }} \
          -t ghcr.io/${{ github.repository }}:${{ github.sha }} .
    - name: Push to GHCR
      run: |
        echo ${{ secrets.GITHUB_TOKEN }} | podman login ghcr.io -u ${{ github.actor }} --password-stdin
        podman push ghcr.io/${{ github.repository }}:${{ github.sha }}
```

```yaml
# GitLab CI with Buildah (no DinD needed)
build:
  stage: build
  image: quay.io/buildah/stable:v1.38
  variables:
    STORAGE_DRIVER: vfs
    BUILDAH_FORMAT: oci
  script:
    - buildah build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - buildah login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
    - buildah push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
```

---

## Operational Excellence

### Structured Logging
```bash
# Log in JSON format for better parsing
echo '{"timestamp":"'"$(date -Iseconds)"'","level":"info","message":"Application started"}'
```

### Metrics Exposure
```dockerfile
# Expose metrics endpoint
EXPOSE 8080
```

### Distributed Tracing
```yaml
# Jaeger integration
environment:
  JAEGER_AGENT_HOST: jaeger
  JAEGER_AGENT_PORT: 6831
```

### Container Monitoring
```yaml
# Prometheus monitoring
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

---

## Compliance and Governance

### OCI Compliance
```dockerfile
# OCI-compliant labels - Use build args for dynamic values
ARG VERSION=dev
ARG COMMIT_SHA=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="My Application"
LABEL org.opencontainers.image.description="My production application"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.revision="${COMMIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.authors="team@example.com"
LABEL org.opencontainers.image.url="https://github.com/myorg/myapp"
LABEL org.opencontainers.image.source="https://github.com/myorg/myapp"
LABEL org.opencontainers.image.documentation="https://github.com/myorg/myapp#readme"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.vendor="My Organization"
LABEL org.opencontainers.image.base.name="alpine:3.21"
```

### Policy Enforcement
```opa
# Open Policy Agent example
package docker.authz

allow {
  input.request.method == "GET"
  input.request.path == "/health"
}
```

### Container Image Verification
```bash
# Verify image integrity (use versioned tags, not :latest)
cosign verify myimage:v1.0.0 --key cosign.pub

# Keyless verification with Sigstore (recommended)
cosign verify myimage:v1.0.0 \
  --certificate-identity=user@example.com \
  --certificate-oidc-issuer=https://accounts.google.com

# Check for vulnerabilities
grype myimage:v1.0.0
```

---

## Validation Checklist

### Security
- [ ] Container runs as non-root user (UID >= 1000)
- [ ] Base image is minimal, up-to-date, and pinned (digest or version)
- [ ] No `latest` tags in production
- [ ] Read-only filesystem is used where possible
- [ ] Capabilities are minimized (`cap_drop: ALL`)
- [ ] `no-new-privileges` security option is set
- [ ] Secrets are properly managed (not in environment variables or layers)
- [ ] `.dockerignore` excludes sensitive files
- [ ] Image is signed with cosign/notation
- [ ] Vulnerability scanning passes (CRITICAL/HIGH = 0)
- [ ] SBOM is generated and stored

### Build
- [ ] Multi-stage build is implemented
- [ ] Build context is minimal
- [ ] Layer caching is optimized
- [ ] OCI labels are complete
- [ ] Build is reproducible

### Runtime
- [ ] Health checks are configured
- [ ] Resource limits are set (CPU, memory, pids)
- [ ] Graceful shutdown is implemented
- [ ] Network isolation is configured
- [ ] Volume mounts use noexec where appropriate

### Observability
- [ ] Structured logging (JSON) is implemented
- [ ] Metrics are exposed (Prometheus format)
- [ ] Distributed tracing is configured

---

## Resources

### Documentation
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Podman Documentation](https://docs.podman.io/)
- [Buildah Documentation](https://buildah.io/)
- [Kubernetes Security Guidelines](https://kubernetes.io/docs/concepts/security/)
- [Open Container Initiative](https://opencontainers.org/)
- [CNCF Cloud Native Landscape](https://landscape.cncf.io/)

### Tools
- [BuildKit](https://github.com/moby/buildkit)
- [Docker Buildx](https://docs.docker.com/buildx/working-with-buildx/)
- [Podman](https://podman.io/)
- [Buildah](https://buildah.io/)
- [Skopeo](https://github.com/containers/skopeo)
- [Cosign](https://github.com/sigstore/cosign)
- [Trivy](https://github.com/aquasecurity/trivy)
- [Syft](https://github.com/anchore/syft)
- [Grype](https://github.com/anchore/grype)

### Communities
- [CNCF](https://www.cncf.io/)
- [Containers GitHub Org](https://github.com/containers) (Podman, Buildah, Skopeo)
- [Docker Community](https://www.docker.com/community)
- [Kubernetes Community](https://kubernetes.io/community/)
