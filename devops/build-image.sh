#!/bin/sh
set -eu

CONTAINER=$(buildah from docker.io/debian:stable-slim)
trap 'buildah rm "$CONTAINER" >/dev/null 2>&1 || true' EXIT
CLAUDE_VERSION=1.0
IMAGE=claude-code

buildah run "$CONTAINER" sh -eu <<'EOT'
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get install -y bash coreutils ca-certificates curl sudo adduser net-tools procps git build-essential graphviz graphviz-dev gcc g++ gh bubblewrap ripgrep jq xz-utils
	apt-get clean
	adduser --disabled-password --gecos "" claude
	mkdir -p /home/claude/.claude
	echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> /home/claude/.bashrc
	chown -R claude:claude /home/claude
	sudo -u claude -i bash -o pipefail -c 'curl -fsSL https://claude.ai/install.sh | bash -s -- latest'
	sudo -u claude -i bash -o pipefail -c 'curl -LsSf https://astral.sh/uv/install.sh | bash'
	sudo -u claude -i bash -o pipefail -c 'curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
	NODE_VERSION=22
	case "$(dpkg --print-architecture)" in
		amd64) NODE_ARCH=x64 ;;
		arm64) NODE_ARCH=arm64 ;;
		*) echo 'Unsupported Node.js architecture' >&2; exit 1 ;;
	esac
	curl -fsSL "https://nodejs.org/dist/latest-v${NODE_VERSION}.x/SHASUMS256.txt" -o /tmp/SHASUMS256.txt
	NODE_FILE=$(awk -v suffix="-linux-${NODE_ARCH}.tar.xz" 'substr($2, length($2)-length(suffix)+1) == suffix {print $2}' /tmp/SHASUMS256.txt)
	test -n "$NODE_FILE"
	curl -fsSL "https://nodejs.org/dist/latest-v${NODE_VERSION}.x/${NODE_FILE}" -o "/tmp/$NODE_FILE"
	(cd /tmp && grep " $NODE_FILE\$" SHASUMS256.txt | sha256sum -c -)
	tar -xJf "/tmp/$NODE_FILE" -C /usr/local --strip-components=1
	rm -f "/tmp/$NODE_FILE" /tmp/SHASUMS256.txt
EOT

buildah config \
	--author "Sebastian Goeldi" \
	--env "PATH=/home/claude/.local/bin:/home/claude/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
	--env "SHELL=/bin/bash" \
	--env "DISABLE_AUTOUPDATER=1" \
	--env "OPENBLAS_NUM_THREADS=1" \
	--env "OMP_NUM_THREADS=1" \
	--env "MKL_NUM_THREADS=1" \
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
