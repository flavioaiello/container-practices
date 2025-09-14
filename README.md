# Container Image Best Practices

A comprehensive guide to building secure, efficient, and production-ready container images using current state-of-the-art techniques. Container technology evolves rapidly - always verify recommendations against the latest documentation and security advisories.

## Table of Contents
1. [Core Principles](#core-principles)
2. [Security Best Practices](#security-best-practices)
3. [Build Optimization](#build-optimization)
4. [Configuration Management](#configuration-management)
5. [Integration](#integration)
6. [Runtime Management](#runtime-management)
7. [Cloud-Native Patterns](#cloud-native-patterns)
8. [Modern Tooling](#modern-tooling)
9. [Operational Excellence](#operational-excellence)
10. [Compliance and Governance](#compliance-and-governance)

---

## Core Principles

### Minimal Base Images
```dockerfile
# Use minimal, updated base images
FROM alpine:3.19
# Or distroless for even smaller attack surface
# FROM gcr.io/distroless/static-debian11
```

### Multi-Stage Builds
```dockerfile
# Build stage
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o app .

# Runtime stage
FROM alpine:3.19
RUN apk add --no-cache ca-certificates tzdata
COPY --from=builder /app/app .
USER 1000:1000
CMD ["./app"]
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

### Vulnerability Scanning
```bash
# Scan images during CI
docker scan --severity HIGH myimage:latest
trivy image --severity CRITICAL myimage:latest
grype myimage:latest
```

### Secrets Management
```dockerfile
# Use build-time secrets
RUN --mount=type=secret,id=github_token,target=/root/.ssh/id_rsa \
    git clone git@github.com:myorg/myrepo.git
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
# Enable BuildKit
export DOCKER_BUILDKIT=1

# Build with secrets
docker build --secret id=mytoken,src=/local/secret .

# Multi-platform builds
docker buildx build --platform linux/amd64,linux/arm64 -t myapp:latest .
```

### Image Compression
```bash
# Use docker-slim for extreme optimization
docker-slim build --http-probe myimage:latest

# Or use dive to analyze layers
dive myimage:latest
```

### SBOM Generation
```bash
# Generate Software Bill of Materials
syft myimage:latest -o cyclonedx-json > sbom.json
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
    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        platforms: linux/amd64,linux/arm64
        push: true
        tags: ghcr.io/${{ github.repository }}:latest
        cache-from: type=gha
        cache-to: type=gha,mode=max
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: 'ghcr.io/${{ github.repository }}:latest'
        format: 'sarif'
        output: 'trivy-results.sarif'
    - name: Upload Trivy scan results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'
```

### GitLab CI Example
```yaml
build:
  stage: build
  image: docker:24.0.5
  services:
    - docker:24.0.5-dind
  variables:
    DOCKER_TLS_CERTDIR: "/certs"
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - docker buildx build --platform linux/amd64,linux/arm64 -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA --push .
    - docker buildx build --platform linux/amd64,linux/arm64 -t $CI_REGISTRY_IMAGE:latest --push .
```

---

## Runtime Management

### Health Checks
```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1
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
# Sign images with cosign
cosign sign --key cosign.key myimage:latest

# Verify signatures
cosign verify --key cosign.pub myimage:latest
```

### Multi-Architecture Builds
```bash
# Build for multiple architectures
docker buildx create --use
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t myapp:latest --push .
```

### Container Runtime Security
```bash
# Use Falco for runtime security
falco -r /etc/falco/rules.yaml

# Or use Aqua Security
aqua trace --container mycontainer
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
# OCI-compliant labels
LABEL org.opencontainers.image.authors="team@example.com"
LABEL org.opencontainers.image.description="My production application"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.source="https://github.com/myorg/myapp"
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
# Verify image integrity
cosign verify myimage:latest --key cosign.pub

# Check for vulnerabilities
grype myimage:latest
```

---

## Validation Checklist
- [ ] Container runs as non-root user
- [ ] Base image is minimal and up-to-date
- [ ] Multi-stage build is implemented
- [ ] Health checks are configured
- [ ] Resource limits are set
- [ ] Secrets are properly managed
- [ ] Image is signed
- [ ] SBOM is generated
- [ ] Vulnerability scanning passes
- [ ] Read-only filesystem is used where possible
- [ ] Capabilities are minimized
- [ ] Structured logging is implemented
- [ ] Metrics are exposed

---

## Resources

### Documentation
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Kubernetes Security Guidelines](https://kubernetes.io/docs/concepts/security/)
- [Open Container Initiative](https://opencontainers.org/)
- [CNCF Cloud Native Landscape](https://landscape.cncf.io/)

### Tools
- [BuildKit](https://docs.docker.com/develop/develop-images/build_enhancements/)
- [Docker Buildx](https://docs.docker.com/buildx/working-with-buildx/)
- [Cosign](https://github.com/sigstore/cosign)
- [Trivy](https://github.com/aquasecurity/trivy)
- [Syft](https://github.com/anchore/syft)
- [Grype](https://github.com/anchore/grype)

### Communities
- [CNCF](https://www.cncf.io/)
- [Docker Community](https://www.docker.com/community)
- [Kubernetes Community](https://kubernetes.io/community/)