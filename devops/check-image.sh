#!/bin/sh
set -eu

# Check the native installation with the launcher's actual home bind mounts.
image="${1:-claude-code:latest}"
task_home=$(mktemp -d)
trap 'rm -rf "$task_home"' EXIT
mkdir -p "$task_home/.claude"
printf '{}\n' > "$task_home/.claude.json"
touch "$task_home/.claude/host-settings"

podman run --rm \
	--user claude \
	--userns=keep-id \
	-v "$task_home/.claude:/home/claude/.claude" \
	-v "$task_home/.claude.json:/home/claude/.claude.json" \
	--entrypoint /bin/sh \
	"$image" -eu -c '
	test "$(id -un)" = claude
	test "$DISABLE_AUTOUPDATER" = 1
	test -f /home/claude/.claude/host-settings
	test -w /home/claude/.claude.json
	test -L /home/claude/.local/bin/claude
	case "$(readlink -f /home/claude/.local/bin/claude)" in
		/home/claude/.local/share/claude/versions/*) ;;
		*) echo "Unexpected Claude installation path" >&2; exit 1 ;;
	esac
	claude --version
	claude --help > /tmp/claude-help
	grep -q -- --remote-control /tmp/claude-help
	node --version
	npm --version
	cargo --version
	rustc --version
	uv --version
	gh --version
	rg --version
	jq --version
	bwrap --version
	ps -p "$$" -o stat= -o lstart=
	'

printf '%s\n' 'Claude installation, Remote Control flag, and toolchains work with host settings mounted.'
