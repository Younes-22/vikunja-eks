# Stage 1: Build the frontend

# Use Node.js 24 to build Vikunja's frontend
FROM node:24-alpine AS frontend-build

# Set the working directory inside the container
WORKDIR /app

# Copy dependency manifests first so Docker can cache dependency installation
COPY frontend/package.json frontend/pnpm-lock.yaml frontend/pnpm-workspace.yaml ./

# Skip unnecessary browser downloads and enable pnpm through Corepack
ENV PUPPETEER_SKIP_DOWNLOAD=true
ENV CYPRESS_INSTALL_BINARY=0

RUN npm install -g corepack && \
    corepack enable && \
    pnpm install --frozen-lockfile

# Copy the remaining frontend source code
COPY frontend/ ./

# Compile the frontend into /app/dist
ARG RELEASE_VERSION=dev
RUN pnpm run build

# Stage 2: Build the backend

# Use Go 1.27 to compile Vikunja's backend
FROM golang:1.27-alpine AS backend-build

# Install the C compiler and development tools required by CGO
RUN apk add --no-cache build-base

# Enable CGO for packages that depend on C code
ENV CGO_ENABLED=1

WORKDIR /app

# Copy the Vikunja application source code
COPY . .

# Copy the compiled frontend into the directory embedded by Go
COPY --from=frontend-build /app/dist ./frontend/dist

# Pass the release version to Vikunja's build process
ARG RELEASE_VERSION=dev
ENV RELEASE_VERSION=${RELEASE_VERSION}

# Install Mage, Vikunja's build tool, and compile the backend
RUN go install github.com/magefile/mage@latest && \
    /go/bin/mage build


# Stage 3: Run the application

# Use a lightweight Alpine image for the runtime
FROM alpine:3.22

# Set the working directory for the application
WORKDIR /app

# Install CA certificates for trusted HTTPS connections
RUN apk add --no-cache ca-certificates

# Copy only the compiled executable from the backend stage
COPY --from=backend-build /app/vikunja ./vikunja

# Document the port Vikunja listens on
EXPOSE 3456

# Start Vikunja when the container launches
CMD ["./vikunja"]
