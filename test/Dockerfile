FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Core tools + build deps for bash 3.2
RUN apt-get update && apt-get install -y \
    tmux \
    jq \
    bash \
    zsh \
    curl \
    git \
    procps \
    nodejs \
    npm \
    python3 \
&& rm -rf /var/lib/apt/lists/*


# Install real Claude Code CLI (no API key needed — just needs to exist as a process)
RUN npm install -g "@anthropic-ai/claude-code@^2"
RUN which claude

# Install Codex CLI
RUN npm install -g "@openai/codex"
RUN which codex

# Create a test user (tmux behaves differently as root)
RUN useradd -m -s /bin/bash testuser
USER testuser
WORKDIR /home/testuser

# Ensure zsh panes have full PATH (for finding claude and other tools)
RUN echo 'export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"' > /home/testuser/.zshrc

# Copy the repo
COPY --chown=testuser:testuser . /home/testuser/tmux-resurrect-agents

# TEST_SHELL: bash (default, system bash 5), bash3.2, or zsh
ENV TEST_SHELL="bash"
ENTRYPOINT ["/bin/bash", "/home/testuser/tmux-resurrect-agents/test/run-tests.sh"]
