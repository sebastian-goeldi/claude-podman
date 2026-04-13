#!/bin/sh

CONTAINER=$(buildah from docker.io/node:current-alpine)
CLAUDE_VERSION=1.0
IMAGE=claude-code

#apk add --no-cache dash
buildah run "$CONTAINER" sh <<EOT
	apk add --no-cache bash coreutils git sudo curl
	apk cache clean
	find . -type f -name '*.md' -delete 2> /dev/null
	adduser -D claude
	curl -fsSL https://claude.ai/install.sh | sudo -u claude bash
	curl -LsSf https://astral.sh/uv/install.sh | sudo -u claude sh
EOT

buildah config \
	--author "Sebastian Goeldi" \
	--env "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
	--env "SHELL=/bin/zsh" \
	--env "DISABLE_TELEMETRY=1" \
	--env "DISABLE_AUTOUPDATER=1" \
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
