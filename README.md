claude-podman
====

Claude for the security-conscious: run [claude-code, the claude cli tool](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview), in a rootless [podman](https://podman.io/) container.

Installation
----

First, install Podman and `uuidgen`. Then install the wrapper:

```sh
mkdir -p "$HOME/.local/bin"
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/sebastian-goeldi/claude-podman/refs/heads/main/bin/claude |
  tee "$HOME/.local/bin/claude-podman"
chmod a+x "$HOME/.local/bin/claude-podman"
```

Now you can just run `claude-podman`.

Benefits
----

This provides the following benefits:

* Claude only gets file access to
	* Files in the present working directory
	* `$HOME/.claude.json`
	* `$HOME/.claude`
* Claude can only execute the files that exist in the image.

This image runs in rootless podman, and even inside rootless podman it runs as
a non-root user inside the container. Telemetry and automatic updates are disabled
in the image. Rebuild or pull a new image to update Claude Code.

Claude's native installation stays in `/home/claude/.local/share/claude`, outside
the mounted settings directory. Mounting your host settings does not hide the
binary or require the nested package volumes used by Codex Podman.

Remote mode
----

Start an interactive terminal session that is also accessible from
[claude.ai/code](https://claude.ai/code) or the Claude mobile app:

```sh
claude-podman --remote
# Use a rebuilt local image:
./bin/claude --local --remote
# Continue the last conversation:
./bin/claude --local --remote --continue
```

The wrapper finishes package installation and initialization scripts before
launching `claude --remote-control`, using the project directory name as the
session title. Open the session from Claude's Remote Control indicator or your
session list. Exiting the terminal session stops and removes the container.
Keep the terminal and host running while using the session remotely.

Remote Control requires a supported Claude subscription and a claude.ai login;
API keys alone do not work. Run `claude-podman` and use `/login` first if needed,
and accept the project's workspace trust dialog. Settings and login state persist
in the mounted `~/.claude` and `~/.claude.json` paths, which the wrapper creates
if missing. Team and Enterprise accounts also need their administrator to enable
Remote Control. No inbound port or Podman port mapping is required.

With the image's `DISABLE_TELEMETRY=1`, Remote Control requires Claude Code
v2.1.283 or later and is unavailable when your organization requires Trusted
Devices. The wrapper keeps telemetry disabled; it does not override that setting
to enable Remote Control. See the current
[Remote Control requirements](https://code.claude.com/docs/en/remote-control#requirements).

Put wrapper options first. Use `--` to pass conflicting Claude options directly.
Claude's own `--remote` is an alias for cloud sessions, distinct from this
wrapper's `--remote`:

```sh
claude-podman -- --remote "Fix the login bug"
# Native server mode, without an interactive local conversation:
claude-podman remote-control --name "My Project"
# Native interactive mode with a custom title:
claude-podman -- --remote-control "My Project"
```

Building locally
----

With Buildah and Podman installed:

```sh
sh devops/build-image.sh
sh devops/check-image.sh
./bin/claude --local --remote
```

The image includes Node.js 22/npm, Rust/Cargo, uv, GitHub CLI, ripgrep, jq,
procps, and bubblewrap. The build installs the latest Claude release and verifies
the Node.js archive checksum. The image check verifies the native installation,
Remote Control flag, and toolchains with host settings mounted; an authenticated
remote connection still needs to be checked with your account.

Run the wrapper checks without a container runtime or login:

```sh
node --test devops/check-wrapper.cjs
```

Customizing the runtime
----

Need to add packages to the container, or run an init script? no problem

```
--apk-packages foo,bar,baz # legacy option name; installs Debian packages with apt-get
--init-script  ./foobar.sh # copies foobar.sh into the container and executes it as root
--init-script-claude ./setup.sh # executes setup.sh as the claude user
```


For example, let's say you're using kubernetes and you do want claude to be able to troubleshoot it.

```sh
claude-podman \
	--apk-packages kubectl \
	--podman-arg "-v $HOME/.kube/config:/home/claude/.kube/config"
```
