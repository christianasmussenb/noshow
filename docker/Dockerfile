FROM intersystemsdc/irishealth-ml-community:2026.1
USER root
COPY iris105-chat/requirements.txt /tmp/chat-requirements.txt
RUN /usr/irissys/bin/irispython -m pip install --no-cache-dir -r /tmp/chat-requirements.txt
USER irisowner
