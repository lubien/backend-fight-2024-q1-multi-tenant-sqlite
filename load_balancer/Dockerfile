FROM rust:1.76.0
WORKDIR /usr/src/myapp
COPY . .
RUN apt-get update && apt-get install -y cmake #&& rm -rf /var/lib/apt/lists/*
RUN cargo install --path .
CMD ["load_balancer"]