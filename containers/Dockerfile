# End-user environment: a clean Linux box with Claude Code and no AWS credentials, only a gateway token.
# Build context is the repository root (see scripts/run-user.sh).
FROM public.ecr.aws/amazonlinux/amazonlinux:2023@sha256:d9c9967b3d895c4c423f54b6562fbf5d18a5b68f5df54908c29e88cba4efcc04

RUN dnf install -y -q python3-pip tar gzip findutils procps-ng shadow-utils && dnf clean all \
 && useradd -m enduser
USER enduser
WORKDIR /home/enduser
ENV PATH="/home/enduser/.local/bin:${PATH}" PYTHONWARNINGS=ignore

# Claude Code: the official native installer, pinned to a version (bump deliberately)
ARG CLAUDE_CODE_VERSION=2.1.308
RUN curl -fsSL https://claude.ai/install.sh | bash -s ${CLAUDE_CODE_VERSION}

COPY --chown=enduser requirements-client.txt /tmp/requirements-client.txt
RUN pip3 install --user -q -r /tmp/requirements-client.txt

COPY --chown=enduser scripts/get-token-srp.py scripts/verify-gateway.sh containers/entrypoint.sh /home/enduser/gateway/
ENTRYPOINT ["/home/enduser/gateway/entrypoint.sh"]
CMD ["bash"]
