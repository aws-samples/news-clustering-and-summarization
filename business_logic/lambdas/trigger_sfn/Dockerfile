#checkov:skip=CKV_DOCKER_2: Ensure that HEALTHCHECK instructions have been added to container images
#checkov:skip=CKV2_DOCKER_1: Ensure that sudo isn't used

FROM amazon/aws-lambda-python:3.12@sha256:a108241bf16fab9559420cbd64d8a608d175f56551ae35bc304c5dcf55f0ec0d

USER root
RUN dnf update -y && dnf install shadow-utils sudo util-linux -y && dnf clean all 

# Set a non-root user
ARG USERNAME=lambda
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN /usr/sbin/groupadd --gid $USER_GID $USERNAME \
    && /usr/sbin/useradd --uid $USER_UID --gid $USER_GID -m $USERNAME -d /home/${USERNAME} \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

WORKDIR /var/task

COPY requirements.txt /var/task
COPY trigger_sfn.py /var/task

RUN chown -R ${user}:${user} /var/task && \
    chmod 755 /var/task/trigger_sfn.py /var/task/requirements.txt

RUN pip install --no-cache-dir -r /var/task/requirements.txt 

USER ${USERNAME}

CMD ["trigger_sfn.handler"]
