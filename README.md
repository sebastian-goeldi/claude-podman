claude-podman
====

Claude for the security-conscious: run [claude-code, the claude cli tool](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview), in a rootless [podman](https://podman.io/) container.

Installation
----

First, download and install podman. Installation is easy and secure with curl

```sh
curl --proto '=https' --tlsv1.2 -sSf \
  https://raw.githubusercontent.com/EvanCarroll/claude-podman/refs/heads/main/bin/claude |
  sudo tee /usr/local/bin/claude-podman
sudo chmod a+x /usr/local/bin/claude-podman
```

Now you can just run `claude-podman`.

Benefit
----

This provides the following benefits:

* Claude only gets file access to
	* Files in the present working directory
	* `$HOME/.claude.json`
	* `$HOME/.claude`
* Claude can only execute the files that exist in the image.

This image runs in rootless podman, and even inside rootless podman it runs as
a non-root user inside the container. Claude code is maximally locked down and
can't even update itself!
