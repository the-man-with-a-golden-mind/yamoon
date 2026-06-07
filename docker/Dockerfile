# Use a base image with Urbit and Node.js
FROM node:22-bullseye

# Install Urbit
RUN apt-get update && apt-get install -y curl && \
    curl -L https://urbit.org/install/linux-x86_64/latest | tar xzk -C /usr/local/bin --strip-components=1

# Install Bun (used by some scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

WORKDIR /app

# Copy project files
COPY . .

# Install dependencies
RUN npm install

# Run the Docker test script
CMD ["bash", "scripts/run_docker_tests.sh"]
