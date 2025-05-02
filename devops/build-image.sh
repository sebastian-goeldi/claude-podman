#!/bin/sh

CONTAINER=$(buildah from docker.io/node:current-alpine)
CLAUDE_VERSION=$(npm info @anthropic-ai/claude-code --json | jq .version -r)
IMAGE=claude-code

#apk add --no-cache dash
buildah run "$CONTAINER" sh <<EOT
	npm config set os linux
	apk add --no-cache zsh
	npm --os=linux install --omit=dev --no-audit --no-fund -g @anthropic-ai/claude-code
	apk cache clean
	rm -rf /usr/local/lib/node_modules/npm/man/
	find . -type f -name '*.md' -delete 2> /dev/null
	adduser -D claude
EOT

buildah config \
	--author "Evan Carroll" \
	--env "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
	--env "SHELL=/usr/bin/zsh" \
	--cmd "" \
	--entrypoint '[ "/usr/local/bin/node", "--no-warnings", "--enable-source-maps", "/usr/local/bin/claude" ]' \
	--annotation "org.anthropic.claudecode.version=$CLAUDE_VERSION" \
	--annotation "org.opencontainers.image.title=claude-code" \
	--annotation "org.opencontainers.image.description=Claude Code on Alpine ready for rootless podman" \
	--annotation "org.opencontainers.image.url=https://github.com/EvanCarroll/claude-podman" \
	--annotation "org.opencontainers.image.source=https://github.com/EvanCarroll/claude-podman" \
	--annotation "org.opencontainers.image.documentation=https://github.com/EvanCarroll/claude-podman/blob/main/README.md" \
	--annotation "org.opencontainers.image.license=AGPL-3.0-or-later" \
	--annotation "org.opencontainers.image.created=$(date --iso-8601=seconds)" \
	"$CONTAINER"

buildah commit \
	--rm \
	"$CONTAINER" "$IMAGE"

buildah tag "$IMAGE" "$CLAUDE_VERSION"

echo Done!
echo ${IMAGE}:${CLAUDE_VERSION}
echo To use this image run /bin/claude
