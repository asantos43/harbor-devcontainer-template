# Harbor task-authoring devcontainer.
#
# Everything version-sensitive comes from versions.env, which is COPYed below: editing
# that file invalidates this build cache and the next rebuild reinstalls at the new
# pins. Do not hardcode versions here.

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dnsutils \
        git \
        iputils-ping \
        jq \
        less \
        locales \
        nano \
        net-tools \
        tmux \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/*

# Generate the UTF-8 locale (the base image ships with none, which breaks Rich's
# box-drawing output in the harbor CLI).
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

COPY versions.env /etc/harbor-devcontainer/versions.env

# uv, pinned. uv also provides the Python interpreter, so the base image's python
# version never constrains Harbor's ">=3.12" floor - bumping PYTHON_VERSION in
# versions.env is all it takes to move.
RUN . /etc/harbor-devcontainer/versions.env \
    && curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh

# /usr/local/bin MUST precede /root/.local/bin: the harbor shim installed below has to
# win over the real binary uv puts in /root/.local/bin.
ENV PATH="/usr/local/bin:/root/.local/bin:${PATH}"

RUN . /etc/harbor-devcontainer/versions.env \
    && uv python install "${PYTHON_VERSION}" \
    && uv tool install --python "${PYTHON_VERSION}" "harbor==${HARBOR_VERSION}" \
    && /root/.local/bin/harbor --version

# Path-translating wrapper; see the file's own header for why it exists.
COPY harbor-shim.sh /usr/local/bin/harbor
RUN chmod +x /usr/local/bin/harbor

# Optional agent CLIs, so `harbor run -a claude-code` works locally. Off by default.
RUN . /etc/harbor-devcontainer/versions.env \
    && if [ "${INSTALL_AGENT_CLIS}" = "1" ]; then \
         curl -fsSL https://claude.ai/install.sh | bash \
         && curl -fsSL https://opencode.ai/install | bash ; \
       else \
         echo "INSTALL_AGENT_CLIS=0; skipping agent CLIs" ; \
       fi

WORKDIR /workspace

CMD ["/bin/zsh"]
