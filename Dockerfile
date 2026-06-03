FROM archlinux:latest AS runtime-base

RUN pacman -Syu --needed --noconfirm \
  base-devel \
  bash \
  bat \
  bind \
  bun \
  bzip2 \
  ca-certificates \
  cmake \
  curl \
  diffutils \
  eza \
  fd \
  file \
  findutils \
  fzf \
  gawk \
  github-cli \
  git \
  git-lfs \
  gnupg \
  go \
  go-yq \
  grep \
  gzip \
  inetutils \
  iproute2 \
  iputils \
  jq \
  less \
  lsof \
  nano \
  nodejs-lts-jod \
  npm \
  openbsd-netcat \
  openssh \
  patch \
  pkgconf \
  pnpm \
  procps-ng \
  psmisc \
  python \
  python-pip \
  python-pipx \
  python-setuptools \
  ripgrep \
  rq \
  rsync \
  rustup \
  sudo \
  tar \
  tmux \
  tree \
  unzip \
  uv \
  vim \
  wget \
  which \
  xz \
  yarn \
  zip \
  zsh \
  zstd && \
  pacman -Scc --noconfirm

FROM runtime-base AS build-deps

WORKDIR /build

COPY package.json package-lock.json ./

RUN ELECTRON_SKIP_BINARY_DOWNLOAD=1 npm ci

FROM build-deps AS tessera-build

COPY . .

RUN npm run npm:prepack

FROM runtime-base AS production-deps

WORKDIR /build

COPY package.json package-lock.json ./

# Only this production dependency tree is copied into the final image.
RUN npm ci --omit=dev

FROM runtime-base AS runtime

RUN useradd -m -s /bin/bash tessera && \
  install -d -o tessera -g tessera \
    /home/tessera/.cache \
    /home/tessera/.cargo \
    /home/tessera/.claude \
    /home/tessera/.codex \
    /home/tessera/.config \
    /home/tessera/.local \
    /home/tessera/.npm-global \
    /home/tessera/.ssh \
    /home/tessera/.tessera \
    /home/tessera/go \
    /home/tessera/workspaces \
    /opt/tessera && \
  printf 'tessera ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/tessera && \
  chmod 0440 /etc/sudoers.d/tessera

WORKDIR /opt/tessera

COPY --from=production-deps /build/node_modules ./node_modules
COPY --from=tessera-build /build/package.json ./package.json
COPY --from=tessera-build /build/next.config.mjs ./next.config.mjs
COPY --from=tessera-build /build/bin ./bin
COPY --from=tessera-build /build/dist-server ./dist-server
COPY --from=tessera-build /build/.next ./.next
COPY --from=tessera-build /build/public ./public
COPY --from=tessera-build /build/assets ./assets

RUN chmod +x /opt/tessera/bin/tessera.mjs && \
  chown -R root:root /opt/tessera

ENV NPM_CONFIG_PREFIX=/home/tessera/.npm-global
ENV PATH=/home/tessera/.bun/bin:/home/tessera/.cargo/bin:/home/tessera/.local/bin:/home/tessera/go/bin:${NPM_CONFIG_PREFIX}/bin:${PATH}
ENV SHELL=/bin/bash

USER tessera

RUN npm config set prefix /home/tessera/.npm-global && \
  npm i -g \
  @anthropic-ai/claude-code@latest \
  @openai/codex@latest \
  opencode-ai@latest

WORKDIR /home/tessera/workspaces

EXPOSE 32123

ENTRYPOINT ["node", "/opt/tessera/bin/tessera.mjs"]
