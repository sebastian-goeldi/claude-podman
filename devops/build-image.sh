#!/bin/sh
CONTAINER=$(buildah from docker.io/debian:stable-slim)
CLAUDE_VERSION=1.0
IMAGE=claude-code

buildah run "$CONTAINER" sh <<'EOT'
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get install -y bash coreutils curl sudo adduser net-tools
	apt-get clean
	find / -type f -name '*.md' -delete 2>/dev/null
	adduser --disabled-password --gecos "" claude
	mkdir -p /home/claude/.claude
	echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/claude/.bashrc
	chown -R claude:claude /home/claude
	sudo -u claude -i bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
	sudo -u claude -i bash -c 'curl -LsSf https://astral.sh/uv/install.sh | bash'
EOT

buildah config \
	--author "Sebastian Goeldi" \
	--env "PATH=/home/claude/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
	--env "SHELL=/bin/bash" \
	--env "DISABLE_TELEMETRY=1" \
	--env "DISABLE_AUTOUPDATER=1" \
	--cmd "[]" \
	--entrypoint '[ "claude" ]' \
	--annotation "org.anthropic.claudecode.version=$CLAUDE_VERSION" \
	--annotation "org.opencontainers.image.title=claude-code" \
	--annotation "org.opencontainers.image.description=Claude Code on Debian ready for rootless podman" \
	--annotation "org.opencontainers.image.url=https://github.com/sebastian-goeldi/claude-podman" \
	--annotation "org.opencontainers.image.source=https://github.com/sebastian-goeldi/claude-podman" \
	--annotation "org.opencontainers.image.documentation=https://github.com/sebastian-goeldi/claude-podman/blob/main/README.md" \
	--annotation "org.opencontainers.image.license=AGPL-3.0-or-later" \
	--annotation "org.opencontainers.image.created=$(date --iso-8601=seconds)" \
	"$CONTAINER"

buildah commit \
	--rm \
	"$CONTAINER" "$IMAGE"

buildah tag "$IMAGE" "${IMAGE}:${CLAUDE_VERSION}"

echo "Done!"
echo "${IMAGE}:${CLAUDE_VERSION}"
echo "To use this image run /bin/claude"
