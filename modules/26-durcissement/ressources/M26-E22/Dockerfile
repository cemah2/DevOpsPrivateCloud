FROM python:latest

ARG HARBOR_TOKEN
ENV HARBOR_TOKEN=$HARBOR_TOKEN \
    HARBOR_URL=https://registry.par1.medisphere.internal

RUN apt-get update && apt-get install -y curl vim netcat-openbsd tcpdump gcc

ADD https://dl.k8s.io/release/v1.36.5/bin/linux/amd64/kubectl /usr/local/bin/kubectl
RUN chmod 777 /usr/local/bin/kubectl

WORKDIR /app
COPY . /app
RUN pip install -r requirements.txt

EXPOSE 8080
CMD ["python", "-m", "inventaire", "--port", "8080"]
